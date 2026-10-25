[CmdletBinding()]
param([string]$ModelSim='C:\modeltech64_10.6e\win64\vsim.exe')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    foreach($testTop in @('tb_video_axis_framing','tb_science_fade','tb_science_audio','tb_science_frame_bandwidth','tb_science_card')) {
        $output=& $ModelSim -c -do "set TEST_TOP $testTop; do run_science.do" 2>&1
        $code=$LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        if($code -ne 0 -or !($output -match 'ALL .* TESTS PASSED') -or
           ($output -match '\*\* (Fatal|Error)')) { throw "ModelSim test failed: $testTop" }
    }
    Write-Host 'All science kiosk regressions passed.'
} finally { Pop-Location }
