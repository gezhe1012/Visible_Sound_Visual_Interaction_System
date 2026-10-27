[CmdletBinding()]
param([string]$ModelSim='C:\modeltech64_10.6e\win64\vsim.exe')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    $output=& $ModelSim -c -do run_secondary_link.do 2>&1
    $code=$LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if($code -ne 0 -or !($output -match 'ALL SECONDARY LINK TESTS PASSED') -or ($output -match '\*\* (Fatal|Error)')) {
        throw 'Secondary link raster regression failed.'
    }
} finally { Pop-Location }
