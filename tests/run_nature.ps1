[CmdletBinding()]
param([string]$ModelSim='C:\modeltech64_10.6e\win64\vsim.exe')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    foreach($name in @('tb_nature_controls','tb_nature_address','tb_nature_loader','tb_nature_wav','tb_nature_bandwidth','tb_nature_card','tb_nature_preview')) {
        $output=& $ModelSim -c -do "set TEST_TOP $name; do run_nature.do" 2>&1
        $code=$LASTEXITCODE
        $output | ForEach-Object {Write-Host $_}
        if($code -ne 0 -or !($output -match 'ALL NATURE .* TESTS PASSED') -or ($output -match '\*\* (Fatal|Error)')) {
            throw "Nature test failed: $name"
        }
    }
} finally {Pop-Location}
