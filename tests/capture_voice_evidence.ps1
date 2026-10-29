[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$out=Join-Path $root 'doc/live_voice'
$run=Join-Path $root 'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1'
$build=Get-Content (Join-Path $root 'voice_build.log') -Raw
if($build -match '\[FAIL\]|HDL or constraints changed|USR-8159|HDL-7225' -or $build -notmatch 'All requested checks passed\.') {throw 'Build is failing, stale or has an unresolved new constraint/implicit-net warning'}
$logNames=@('voice_unit.log','voice_display.log','voice_compat.log','voice_structure.log','voice_regress_main.log','voice_regress_science.log','voice_regress_secondary.log','voice_regress_final.log','voice_rom.log','voice_cdc_audit.log')
$results=@()
foreach($name in $logNames) {
    $body=Get-Content (Join-Path $root $name) -Raw
    if($body -match '\*\* (Fatal|Error)|\[FAIL\]|regression failed' -or $body -notmatch 'ALL .* TESTS PASSED') {throw "Failed/missing test: $name"}
    $results+=[ordered]@{log=$name;pass_lines=@($body -split '\r?\n' | Where-Object {$_ -match 'ALL .* TESTS PASSED'})}
}
$bit=Get-Item (Join-Path $run 'HDMI1.4b_Transmitter_v1.0.bit')
$sources=@(Get-ChildItem (Join-Path $root 'src/user_source') -Recurse -File | Where-Object {$_.Extension -in '.v','.vhd','.adc','.sdc'})
$sources+=Get-Item (Join-Path $root 'src/td_project/HDMI1.4b_Transmitter_v1.0.al')
$sources+=Get-Item (Join-Path $root 'tests/secondary_enhanced_synthesis.tcl')
$sources+=Get-ChildItem (Join-Path $root 'src/td_project/al_ip') -File | Where-Object {$_.Extension -in '.v','.vhd','.ipc'}
if(($sources | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime -gt $bit.LastWriteTime) {throw 'Stale bit'}
$timing=Get-Content (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_pr.timing') -Raw
$setup=[double][regex]::Match($timing,'SWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
$hold=[double][regex]::Match($timing,'HWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
if($setup -lt 0 -or $hold -lt 0) {throw 'Do not package a timing-failing bit'}
$area=Get-Content (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_phy.area') -Raw
$resources=[ordered]@{}
foreach($name in @('lut','reg','bram','dsp','pll')) {$resources[$name]=[int][regex]::Match($area,'(?m)^#'+$name+'\s+(\d+)').Groups[1].Value}
$hashes=[ordered]@{}
foreach($file in $sources | Sort-Object FullName) {$hashes[$file.FullName.Substring($root.Length+1).Replace('\','/')]=(Get-FileHash $file.FullName).Hash}
$evidence=[ordered]@{
    base='6e58891';feature='INMP441 live voice on virtual page 6';device='EG4S20BG256';tool='TD 6.2.168116';
    built_at=$bit.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss');bit_bytes=$bit.Length;bit_sha256=(Get-FileHash $bit.FullName).Hash;
    implementation_verified=$true;physical_microphone_verified=$false;new_bit_board_regression_verified=$false;
    resources=$resources;setup_wns_ns=$setup;hold_wns_ns=$hold;
    sta_coverage_percent=[double][regex]::Match($timing,'STA coverage\s*:\s*([0-9.]+)%').Groups[1].Value;
    pins=[ordered]@{mic_sck='M15 / J1-31';mic_ws='L16 / J1-32';mic_sd='N16 / J1-33';power='3.3V J1-29 / GND J1-30';channel='L/R grounded'};
    audio=[ordered]@{source_clock_hz=25000000;sample_hz_average=48000;sck_hz_average=3072000;sck_half_ns=@(160,200);sck_period_ns=@(320,360);sample_valid_clocks=@(520,521);sample_bits=24;slots_per_frame=64;warmup_frames=4096;new_pll=0;new_bram=0;new_dsp=0};
    analysis=[ordered]@{fft_points=1024;bin_hz=46.875;main_frequency_range_hz=@(0,4500);mono=$true;gain_range=@(8,128);dds_pages='1-5';microphone_page=6;hdmi_microphone_playback=$false;original_bmp_count=5};
    timing_changes=@('One local sd_init_done qualification register before scaler; original scaler arithmetic unchanged','Only mic_sd external pad and existing video read_req -> memory first synchronizer D are false paths; second/third stages and all data remain timed');
    source_sha256=$hashes;regressions=$results
}
New-Item -ItemType Directory -Path (Join-Path $out 'test_logs') -Force | Out-Null
Copy-Item $bit.FullName (Join-Path $out 'HDMI_live_voice.bit')
Copy-Item (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_pr.timing') (Join-Path $out 'routed_timing.txt')
Copy-Item (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_phy.area') (Join-Path $out 'utilization.txt')
Copy-Item (Join-Path $root 'voice_build.log') (Join-Path $out 'build_transcript.txt')
foreach($name in $logNames) {Copy-Item (Join-Path $root $name) (Join-Path $out ('test_logs/'+($name -replace '\.log$','.txt')))}
$evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $out 'build_evidence.json') -Encoding UTF8
Write-Host 'ALL VOICE EVIDENCE TESTS PASSED: fresh bit, matching sources, positive timing, physical board checks explicitly pending'
