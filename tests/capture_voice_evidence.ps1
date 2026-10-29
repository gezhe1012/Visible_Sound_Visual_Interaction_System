[CmdletBinding()]
param([switch]$NoiseReduced,[switch]$VoiceFocus,[switch]$AnlogicLogo)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$out=Join-Path $root 'doc/live_voice'
if($AnlogicLogo) {$VoiceFocus=$true;$NoiseReduced=$true;$out=Join-Path $root 'doc/logo_overlay'}
elseif($VoiceFocus) {$NoiseReduced=$true;$out=Join-Path $out 'voice_focus'}
elseif($NoiseReduced) {$out=Join-Path $out 'noise_reduced'}
$run=Join-Path $root 'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1'
$buildLog=if($NoiseReduced) {'voice_noise_build.log'} else {'voice_build.log'}
$bitName=if($NoiseReduced) {'HDMI_live_voice_noise_reduced.bit'} else {'HDMI_live_voice.bit'}
if($VoiceFocus) {$buildLog='voice_focus_build.log';$bitName='HDMI_live_voice_focus.bit'}
if($AnlogicLogo) {$buildLog='logo_build.log';$bitName='HDMI_anlogic_logo.bit'}
$build=Get-Content (Join-Path $root $buildLog) -Raw
if($build -match '\[FAIL\]|HDL or constraints changed|USR-8159|HDL-7225' -or $build -notmatch 'All requested checks passed\.') {throw 'Build is failing, stale or has an unresolved new constraint/implicit-net warning'}
$logNames=@('voice_unit.log','voice_display.log','voice_compat.log','voice_structure.log','voice_regress_main.log','voice_regress_science.log','voice_regress_secondary.log','voice_regress_final.log','voice_rom.log','voice_cdc_audit.log')
if($NoiseReduced) {$logNames=@('voice_noise_unit.log','voice_noise_display.log','voice_noise_compat.log','voice_noise_fft.log','voice_noise_controls.log','voice_noise_secondary.log','voice_noise_structure.log','voice_noise_rom.log','voice_noise_cdc.log')}
if($VoiceFocus) {$logNames=@('voice_focus_unit.log','voice_focus_display.log','voice_focus_compat.log','voice_focus_fft.log','voice_focus_controls.log','voice_focus_secondary.log','voice_focus_structure.log','voice_focus_rom.log','voice_focus_cdc.log','voice_focus_ui.log')}
if($AnlogicLogo) {$logNames=@('logo_unit.log','logo_display.log','logo_compat.log','logo_fft.log','logo_controls.log','logo_secondary.log','logo_structure.log','logo_rom.log','logo_cdc.log','logo_ui.log','logo_osd.log','logo_ticker.log','logo_asset.log')}
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
if($AnlogicLogo) {
    $sources+=Get-Item (Join-Path $root 'doc/TF卡图片/logo_640x480_24bit_不翻转.bmp')
    $sources+=Get-Item (Join-Path $root 'tests/logo_timing_implementation.tcl')
}
if(($sources | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime -gt $bit.LastWriteTime) {throw 'Stale bit'}
if($NoiseReduced) {
    $latestHdl=($sources | Where-Object {$_.Extension -in '.v','.vhd','.adc','.sdc','.al'} | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    foreach($name in $logNames) {
        if((Get-Item (Join-Path $root $name)).LastWriteTime -lt $latestHdl) {throw "Stale regression: $name"}
    }
}
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
    bit_file=$bitName;
    implementation_verified=$true;physical_microphone_verified=$false;new_bit_board_regression_verified=$false;
    resources=$resources;setup_wns_ns=$setup;hold_wns_ns=$hold;
    sta_coverage_percent=[double][regex]::Match($timing,'STA coverage\s*:\s*([0-9.]+)%').Groups[1].Value;
    pins=[ordered]@{mic_sck='M15 / J1-31';mic_ws='L16 / J1-32';mic_sd='N16 / J1-33';power='3.3V J1-29 / GND J1-30';channel='L/R grounded'};
    audio=[ordered]@{source_clock_hz=25000000;sample_hz_average=48000;sck_hz_average=3072000;sck_half_ns=@(160,200);sck_period_ns=@(320,360);sample_valid_clocks=@(520,521);sample_bits=24;slots_per_frame=64;warmup_frames=4096;new_pll=0;new_bram=0;new_dsp=0};
    analysis=[ordered]@{fft_points=1024;bin_hz=46.875;main_frequency_range_hz=@(0,4500);mono=$true;gain_range=@(8,128);dds_pages='1-5';microphone_page=6;hdmi_microphone_playback=$false;original_bmp_count=5};
    timing_changes=@('One local sd_init_done qualification register before scaler; original scaler arithmetic unchanged','Only mic_sd external pad and existing video read_req -> memory first synchronizer D are false paths; second/third stages and all data remain timed');
    source_sha256=$hashes;regressions=$results
}
if($NoiseReduced) {
    $evidence.base='b2feea7'
    $evidence.feature='Page-6 microphone visual noise reduction; original five pages preserved'
    $evidence.analysis.quiet_gain=16
    $evidence.analysis.noise_reduction=[ordered]@{
        detector='mean absolute raw centered PCM';block_samples=256;noise_estimate_range_raw=@(128,1024);
        open='max(768, 3*noise)';close='max(384, 2*noise)';attack_blocks=2;nominal_attack_ms=10.667;
        block_alignment_attack_bound_ms=16;release_blocks=18;release_ms=96;quiet_output='valid zero PCM, not stopped sampling';
        mic_only_display_floor_pixels=8;real_environment_calibration_verified=$false
    }
    $evidence.regression_scope='Reran voice/noise, real-FFT dual-screen, five-page pixel compatibility, FFT, keys, secondary store/renderer, structure, ROM and CDC. Unmodified FAT32/SDRAM/full-melody suites were not rerun; see b2feea7 evidence.'
    $evidence.timing_changes=@('No clocks, pins, timing constraints, FIFOs, memory interfaces, HDMI audio or FFT arithmetic changed in this iteration')
}
if($VoiceFocus) {
    $evidence.base='bf35426'
    $evidence.feature='Voice page only: remove secondary note/PK/HZ; focus primary FFT near 100-2000Hz'
    $evidence.analysis.main_frequency_range_hz=@(100,2000)
    $evidence.analysis.main_fft_bin_centers_hz=@(93.75,2015.625)
    $evidence.analysis.main_fft_bins=@(2,43)
    $evidence.analysis.mapping='42 linearly spaced bin slots across 512 pixels; existing paired maxima above bin31 reused; 46.875Hz FFT resolution unchanged'
    $evidence.analysis.secondary_numeric_note_visible=$false
    $evidence.analysis.secondary_numeric_peak_visible=$false
    $evidence.analysis.secondary_history_range_hz=@(0,4500)
    $evidence.analysis.noise_frontend_unchanged_from='bf35426'
    $evidence.regression_scope='Reran noise/receiver/player, serial mic real-FFT dual-screen, independent focus UI RGB/address oracle, five-page pixel compatibility, FFT/KEY3, keys, secondary store/renderer, structure, ROM/CDC. Unmodified FAT32/SDRAM/full melody suites not rerun.'
}
if($AnlogicLogo) {
    $evidence.base='f915d8c'
    $evidence.feature='Replace legacy main-screen ANLOGIC text/blue strip with the supplied red/navy logo on all six pages'
    $evidence.logo_asset=Get-Content (Join-Path $out 'logo_asset.json') -Raw | ConvertFrom-Json
    $evidence.logo_physical_verified=$false
    $evidence.implementation_strategy='TD official TimingMedium placement options; normal route, hold fix and bitgen; no extra SDC exceptions or RTL changes'
    $evidence.regression_scope='Six-page full OSD RGB comparison against f915d8c except the requested old-logo rectangle; BMP-derived golden pixels; unchanged clock/pipeline. Reran original caption/animation, keys, microphone/noise/player, serial mic real-FFT dual-screen, focus UI, five-page analysis pixel compatibility, FFT, secondary store/renderer, ROM/CDC. Unmodified FAT32/SDRAM/full melody not rerun.'
}
New-Item -ItemType Directory -Path (Join-Path $out 'test_logs') -Force | Out-Null
Copy-Item $bit.FullName (Join-Path $out $bitName)
Copy-Item (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_pr.timing') (Join-Path $out 'routed_timing.txt')
Copy-Item (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_phy.area') (Join-Path $out 'utilization.txt')
Copy-Item (Join-Path $root $buildLog) (Join-Path $out 'build_transcript.txt')
foreach($name in $logNames) {Copy-Item (Join-Path $root $name) (Join-Path $out ('test_logs/'+($name -replace '\.log$','.txt')))}
$evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $out 'build_evidence.json') -Encoding UTF8
Write-Host 'ALL VOICE EVIDENCE TESTS PASSED: fresh bit, matching sources, positive timing, physical board checks explicitly pending'
