[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$out=Join-Path $root 'doc\secondary_display\phase1'
$run=Join-Path $root 'src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\phy_1'
$build=Get-Content -LiteralPath (Join-Path $root 'secondary_link_build.log') -Raw
if($build -notmatch 'All requested checks passed\.' -or $build -match 'HDL or constraints changed during this build') { throw 'Incomplete or unstable-source build.' }
$logs=@('secondary_link_simulation.log','secondary_structure.log','secondary_fft_regression.log',
    'secondary_ticker_regression.log','secondary_controls_regression.log','secondary_waveform_regression.log',
    'secondary_science_regression.log','secondary_melody_regression.log')
$results=@()
foreach($name in $logs) {
    $body=Get-Content -LiteralPath (Join-Path $root $name) -Raw
    if($body -match '\*\* (Fatal|Error)|Unexpected EOF|regression failed' -or $body -notmatch 'ALL .* TESTS PASSED') { throw "Failed/missing test: $name" }
    $results+=[ordered]@{log=$name;pass_lines=@($body -split "`n" | Where-Object { $_ -match 'ALL .* TESTS PASSED' } | ForEach-Object { $_.Trim() })}
}
$timing=Get-Content -LiteralPath (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_pr.timing') -Raw
$setup=[regex]::Match($timing,'SWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
$hold=[regex]::Match($timing,'HWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
if(!$setup -or !$hold -or [double]$setup -lt 0 -or [double]$hold -lt 0) { throw 'Do not package timing-failing bit.' }
$bit=Join-Path $run 'HDMI1.4b_Transmitter_v1.0.bit'
$latest=Get-ChildItem -LiteralPath (Join-Path $root 'src\user_source') -Recurse -File |
    Where-Object { $_.Extension -in '.v','.vhd','.sdc','.adc' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if((Get-Item $bit).LastWriteTime -lt $latest.LastWriteTime) { throw 'Stale bit.' }
Copy-Item -LiteralPath $bit -Destination (Join-Path $out 'HDMI_A_link_test.bit')
Copy-Item -LiteralPath (Join-Path $root '.git\secondary_display_backup\a0bd824\stable_a0bd824.bit') -Destination (Join-Path $out 'stable_a0bd824.bit')
Copy-Item -LiteralPath (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_pr.timing') -Destination (Join-Path $out 'routed_timing.txt')
Copy-Item -LiteralPath (Join-Path $run 'HDMI1.4b_Transmitter_v1.0_phy.area') -Destination (Join-Path $out 'utilization.txt')
Copy-Item -LiteralPath (Join-Path $root 'secondary_link_build.log') -Destination (Join-Path $out 'build_transcript.txt')
$hashes=[ordered]@{}
foreach($name in @('src/user_source/hdl_source/secondary_link_pattern.v','src/user_source/hdl_source/secondary_hdmi_tx.v',
    'src/user_source/hdl_source/top_tf_hdmi_audio.v','src/user_source/constraints_source/pin.adc',
    'src/user_source/constraints_source/timing.sdc','src/td_project/HDMI1.4b_Transmitter_v1.0.al')) {
    $hashes[$name]=(Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash
}
[ordered]@{
    stage='1 - Independent HDMI_A link test';base='a0bd824';branch='codex/secondary-display';
    full_secondary_features_complete=$false;physical_dual_display_verified=$false;
    spectrogram_implemented=$false;pitch_tracker_implemented=$false;
    tool='TD 6.2.168116';device='EG4S20BG256';built_at=(Get-Item $bit).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss');
    bit_bytes=(Get-Item $bit).Length;bit_sha256=(Get-FileHash -LiteralPath $bit).Hash;
    recovery_bit_sha256=(Get-FileHash -LiteralPath (Join-Path $out 'stable_a0bd824.bit')).Hash;
    setup_wns_ns=[double]$setup;hold_wns_ns=[double]$hold;
    source_sha256=$hashes;regressions=$results
} | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $out 'build_evidence.json') -Encoding UTF8
Write-Host 'PASS: stage-1 tool evidence and both test/recovery bits captured. Board verification and full features remain pending.'
