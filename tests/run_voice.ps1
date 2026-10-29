[CmdletBinding()]
param([string]$ModelSim='C:\modeltech64_10.6e\win64\vsim.exe')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    foreach($name in @('tb_voice_input','tb_six_page_player')) {
        $output=& $ModelSim -c -do "set TEST_TOP $name; do run_voice.do" 2>&1
        $code=$LASTEXITCODE
        $output | ForEach-Object {Write-Host $_}
        if($code -ne 0 -or !($output -match 'ALL .* TESTS PASSED') -or ($output -match '\*\* (Fatal|Error)')) {throw "Voice test failed: $name"}
    }
} finally {Pop-Location}
