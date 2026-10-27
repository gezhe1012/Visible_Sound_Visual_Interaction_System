[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location -LiteralPath $root
function Assert-True([bool]$Condition,[string]$Message) {
    if(!$Condition) { throw $Message }
    Write-Host "PASS: $Message"
}
function Compact([string]$Text) { return [regex]::Replace($Text,'\s','') }
try {
    $top='src/user_source/hdl_source/top_tf_hdmi_audio.v'
    $oldTop=(git show "a0bd824:$top") -join "`n"
    $newTop=Get-Content -LiteralPath $top -Raw -Encoding UTF8
    $withoutPorts=[regex]::Replace($newTop,'(?s)// Independent HDMI_A output; handbook p8\..*?inout\s+HDMIA_DDC_SDA,','')
    $withoutSecondary=[regex]::Replace($withoutPorts,'(?s)// Stage-1 hardware gate:.*?(?=endmodule)','')
    Assert-True ((Compact $oldTop) -ceq (Compact $withoutSecondary)) 'Main top-level logic is exactly a0bd824 after removing the added ports/secondary instance.'
    $pin='src/user_source/constraints_source/pin.adc'
    $oldPin=(git show "a0bd824:$pin") -join "`n"
    $newPin=(Get-Content -LiteralPath $pin -Encoding UTF8 | Where-Object { $_ -notmatch '^# HDMI_A:|^# CLK K1|^set_pin_assignment \{ HDMIA_' }) -join "`n"
    Assert-True ((Compact $oldPin) -ceq (Compact $newPin)) 'All original main-screen/key/TF constraints are unchanged.'
    git diff --exit-code a0bd824 -- src/user_source/constraints_source/timing.sdc | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'No clock constraint or timing exception was added.'
    $changed=@(git diff --name-only a0bd824 -- src/user_source)
    Assert-True (@($changed | Where-Object { $_ -notin @($top,$pin) -and $_ -notmatch '/secondary_(link_pattern|hdmi_tx)\.v$' }).Count -eq 0) 'Original audio, FFT, wave, OSD, footer, SDRAM, IP and clocks are unmodified.'
    $area=Get-Content -LiteralPath 'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0_phy.area' -Raw
    $pads=@{'HDMIA_CLK_P'='K1';'HDMIA_CLK_P(n)'='J1';'HDMIA_D0_P'='F5';'HDMIA_D0_P(n)'='F4';
        'HDMIA_D1_P'='E3';'HDMIA_D1_P(n)'='E4';'HDMIA_D2_P'='B3';'HDMIA_D2_P(n)'='D3';'HDMIA_DDC_SCL'='P1';'HDMIA_DDC_SDA'='R1'}
    foreach($name in $pads.Keys) {
        $pattern='(?m)^\s*'+[regex]::Escape($name)+'\s+\S+\s+'+$pads[$name]+'\s+'
        Assert-True ($area -match $pattern) "Routed HDMI_A pad $name = $($pads[$name]) agrees with handbook p8."
    }
    $timing=Get-Content -LiteralPath 'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0_pr.timing' -Raw
    $setup=[regex]::Match($timing,'SWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
    $hold=[regex]::Match($timing,'HWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
    Assert-True ($setup -ne '' -and $hold -ne '' -and [double]$setup -ge 0 -and [double]$hold -ge 0) "Global routed setup/hold is nonnegative ($setup / $hold ns)."
    Write-Host 'ALL SECONDARY STRUCTURE TESTS PASSED: protected main logic, exact A pads including paired N, unchanged clocks, global timing.'
} finally { Pop-Location }
