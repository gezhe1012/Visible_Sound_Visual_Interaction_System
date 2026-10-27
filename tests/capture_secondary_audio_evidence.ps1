[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$out=Join-Path $root 'doc\secondary_display\audio'
$run=Join-Path $root 'src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\phy_1'
$build=Get-Content -LiteralPath (Join-Path $root 'secondary_audio_build.log') -Raw
if($build -notmatch 'All requested checks passed\.' -or $build -match 'HDL or constraints changed during this build|\[FAIL\]') {throw 'Incomplete, unstable-source or failing build.'}
$logs=@('secondary_audio_oracle.log','secondary_audio_simulation.log','secondary_audio_checks.log',
    'secondary_audio_live.log','secondary_audio_structure.log','secondary_audio_fft.log','secondary_audio_rom.log',
    'secondary_audio_ticker.log','secondary_audio_controls.log','secondary_audio_waveform.log',
    'secondary_audio_science.log','secondary_audio_melody.log')
$results=@()
foreach($name in $logs) {
    $body=Get-Content -LiteralPath (Join-Path $root $name) -Raw
    if($body -match '\*\* (Fatal|Error)|Unexpected EOF|regression failed|couldn.t read file|Script error|\[FAIL\]' -or $body -notmatch 'ALL .* TESTS PASSED') {throw "Failed/missing test: $name"}
    $results+=[ordered]@{log=$name;pass_lines=@($body -split "`n" | Where-Object {$_ -match 'ALL .* TESTS PASSED'} | ForEach-Object {$_.Trim()})}
}
$timing=Get-Content -LiteralPath (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_pr.timing') -Raw
$setup=[regex]::Match($timing,'SWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
$hold=[regex]::Match($timing,'HWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
if(!$setup -or !$hold -or [double]$setup -lt 0 -or [double]$hold -lt 0) {throw 'Do not package timing-failing bit.'}
$bit=Join-Path $run 'HDMI1.4b_Transmitter_v1.0.bit'
$sourceFiles=@(Get-ChildItem -LiteralPath (Join-Path $root 'src\user_source') -Recurse -File |
    Where-Object {$_.Extension -in '.v','.vhd','.sdc','.adc'})
$projectFile=Get-Item -LiteralPath (Join-Path $root 'src\td_project\HDMI1.4b_Transmitter_v1.0.al')
$sourceFiles+=@($projectFile)
$latest=$sourceFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if((Get-Item $bit).LastWriteTime -lt $latest.LastWriteTime) {throw 'Stale bit.'}
$netlist=Get-Item -LiteralPath (Join-Path $root 'tests\fft_gate_netlist.v')
if($netlist.LastWriteTime -lt (Get-Item $bit).LastWriteTime) {throw 'ROM audit used an older netlist; export after the final build.'}
Copy-Item -LiteralPath $bit -Destination (Join-Path $out 'HDMI_A_audio_analysis.bit')
Copy-Item -LiteralPath (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_pr.timing') -Destination (Join-Path $out 'routed_timing.txt')
Copy-Item -LiteralPath (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_phy.area') -Destination (Join-Path $out 'utilization.txt')
Copy-Item -LiteralPath (Join-Path $root 'secondary_audio_build.log') -Destination (Join-Path $out 'build_transcript.txt')
$logOut=Join-Path $out 'test_logs'
New-Item -ItemType Directory -Path $logOut -Force | Out-Null
foreach($name in $logs) {Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $logOut ($name -replace '\.log$','.txt'))}
$hashes=[ordered]@{}
foreach($file in $sourceFiles | Sort-Object FullName) {
    $name=$file.FullName.Substring($root.Length+1).Replace('\','/')
    $hashes[$name]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}
$area=Get-Content -LiteralPath (Join-Path $out 'utilization.txt') -Raw
$resources=[ordered]@{}
foreach($name in @('lut','reg','bram','dsp','pll')) {$resources[$name]=[int][regex]::Match($area,'(?m)^#'+$name+'\s+(\d+)').Groups[1].Value}
[ordered]@{
    stage='2-4 - Real FFT waterfall and monophonic measured pitch';base='a0bd824';interface_checkpoint='20b6fe2';
    branch='codex/secondary-display';phase1_board_confirmed_by_user=$true;new_analysis_board_verified=$false;
    spectrogram_implemented=$true;pitch_tracker_implemented=$true;optional_harmonics_implemented=$false;optional_lissajous_implemented=$false;
    tool='TD 6.2.168116';device='EG4S20BG256';built_at=(Get-Item $bit).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss');
    bit_bytes=(Get-Item $bit).Length;bit_sha256=(Get-FileHash -LiteralPath $bit).Hash;
    phase1_bit_sha256=(Get-FileHash -LiteralPath (Join-Path $root 'doc\secondary_display\phase1\HDMI_A_link_test.bit')).Hash;
    recovery_bit_sha256=(Get-FileHash -LiteralPath (Join-Path $root 'doc\secondary_display\phase1\stable_a0bd824.bit')).Hash;
    resources=$resources;delta_vs_interface=[ordered]@{lut=$resources.lut-12738;reg=$resources.reg-6816;bram=$resources.bram-56;dsp=$resources.dsp-26;pll=$resources.pll-3};
    setup_wns_ns=[double]$setup;hold_wns_ns=[double]$hold;
    sta_coverage_percent=[double][regex]::Match($timing,'STA coverage\s*:\s*([0-9.]+)%').Groups[1].Value;
    waterfall=[ordered]@{visible_columns=96;physical_columns=128;frequency_bands=64;intensity_bits=4;heat_bytes=4096;trace_bytes=128;sample_rate=48000;fft_points=1024;bin_hz=46.875;steady_column_ms=33.6;display_span_seconds=3.2256;frequency_axis='piecewise linear 0-1.5k / 1.5k-4.5k'};
    source_sha256=$hashes;regressions=$results
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'build_evidence.json') -Encoding UTF8
Write-Host 'PASS: real FFT secondary bit, source hashes and final tool evidence captured. New analysis board verification remains pending.'
