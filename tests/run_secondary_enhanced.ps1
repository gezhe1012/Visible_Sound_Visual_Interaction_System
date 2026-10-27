[CmdletBinding()]
param([string]$ModelSim='C:\modeltech64_10.6e\win64\vsim.exe')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    $output=& $ModelSim -c -do 'do run_secondary_enhanced.do' 2>&1
    $code=$LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if($code -ne 0 -or !($output -match 'ALL ENHANCED UNIT TESTS PASSED') -or ($output -match '\*\* (Fatal|Error)')) {throw 'Enhanced secondary unit regression failed.'}
} finally {Pop-Location}
