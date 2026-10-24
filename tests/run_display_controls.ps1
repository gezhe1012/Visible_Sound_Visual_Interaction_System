[CmdletBinding()]
param([string]$ModelSim='C:\modeltech64_10.6e\win64\vsim.exe')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    foreach($testTop in @('tb_video_picture_adjust','tb_display_key_controls','tb_osd_display_controls')) {
        $output=& $ModelSim -c -do "set TEST_TOP $testTop; do run_display_controls.do" 2>&1
        $code=$LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        if($code -ne 0 -or !($output -match 'ALL .* TESTS PASSED') -or
           ($output -match '\*\* (Fatal|Error)')) {
            throw "ModelSim test failed: $testTop"
        }
    }
    Write-Host 'All extension 4 regressions passed.'
} finally { Pop-Location }
