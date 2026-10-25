[CmdletBinding()]
param([string]$ModelSim='C:\modeltech64_10.6e\win64\vsim.exe')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    foreach($testTop in @('tb_audio_waveform','tb_waveform_i2s')) {
        $output=& $ModelSim -c -do "set TEST_TOP $testTop; do run_waveform.do" 2>&1
        $code=$LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        if($code -ne 0 -or !($output -match 'ALL .* TESTS PASSED') -or
           ($output -match '\*\* (Fatal|Error)')) { throw "ModelSim test failed: $testTop" }
    }
    Write-Host 'All extension 5 regressions passed.'
} finally { Pop-Location }
