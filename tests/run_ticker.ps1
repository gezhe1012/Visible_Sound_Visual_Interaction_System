[CmdletBinding()]
param([string]$ModelSim='C:\modeltech64_10.6e\win64\vsim.exe')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    & 'C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' build_logo_asset.py --generate-test-assets
    if($LASTEXITCODE -ne 0) {throw 'Logo test asset build failed'}
    foreach($testTop in @('tb_theme_ticker','tb_ticker_animation')) {
    $output=& $ModelSim -c -do "set TEST_TOP $testTop; do run_ticker.do" 2>&1
    $code=$LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if($code -ne 0 -or !($output -match 'ALL .* TESTS PASSED') -or
       ($output -match '\*\* (Fatal|Error)')) { throw 'Themed ticker regression failed.' }
    }
} finally { Pop-Location }
