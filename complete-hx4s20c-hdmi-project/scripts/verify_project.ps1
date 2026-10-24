[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$RunSynthesis,
    [switch]$RunImplementation
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$script:FailureCount = 0

function Write-Pass([string]$Message) {
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail([string]$Message) {
    $script:FailureCount++
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Require-File([string]$RelativePath) {
    $fullPath = Join-Path $ProjectRoot $RelativePath
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        Write-Pass $RelativePath
        return $fullPath
    }

    Write-Fail "Missing file: $RelativePath"
    return $null
}

function Require-Text([string]$Path, [string]$Pattern, [string]$Description) {
    if ($Path -and (Select-String -LiteralPath $Path -Pattern $Pattern -Quiet)) {
        Write-Pass $Description
    } else {
        Write-Fail $Description
    }
}

function Invoke-TdFlow([string]$TdCommand, [string]$FlowScript, [string]$RunDirectory, [string]$Label) {
    Write-Host "`n== $Label ==" -ForegroundColor Cyan
    Push-Location -LiteralPath $RunDirectory
    try {
        $output = & $TdCommand $FlowScript 2>&1
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }

        $fatalText = $output | Select-String -Pattern '\bERROR\b|\bFATAL\b|couldn.t read file|Script error|return -code error'
        $flowCompleted = $output | Select-String -Pattern 'start command "export_flow_status'
        if (($exitCode -ne 0) -or $fatalText -or -not $flowCompleted) {
            Write-Fail "$Label failed (exit code $exitCode)."
        } else {
            Write-Pass "$Label completed."
        }
    } finally {
        Pop-Location
    }
}

Write-Host "Project root: $ProjectRoot" -ForegroundColor Cyan
Write-Host "`n== Required project files ==" -ForegroundColor Cyan

$pptPath = Require-File '赛题解析一.pptx'
$projectPath = Require-File 'src\td_project\HDMI1.4b_Transmitter_v1.0.al'
$topPath = Require-File 'src\user_source\hdl_source\top_tf_hdmi_audio.v'
$sdBmpPath = Require-File 'src\user_source\hdl_source\SD\sd_card_bmp.v'
$scalerPath = Require-File 'src\user_source\hdl_source\SD\bmp_bilinear_reader.v'
$axisPath = Require-File 'src\user_source\hdl_source\video_rgb_to_axis_640x480.v'
$fadePath = Require-File 'src\user_source\hdl_source\video_fade_transition.v'
$osdPath = Require-File 'src\user_source\hdl_source\video_osd_overlay.v'
$audioPath = Require-File 'src\user_source\hdl_source\hdmi_audio_tone_i2s_64fs.v'
$pinPath = Require-File 'src\user_source\constraints_source\pin.adc'
$timingPath = Require-File 'src\user_source\constraints_source\timing.sdc'

Write-Host "`n== Structural checks ==" -ForegroundColor Cyan
Require-Text $topPath '^\s*module\s+top\b' 'Top module is present.'
Require-Text $sdBmpPath '^\s*module\s+sd_card_bmp\b' 'TF/BMP controller is present.'
Require-Text $scalerPath '^\s*module\s+bmp_bilinear_reader\b' 'Bilinear BMP loader is present.'
Require-Text $sdBmpPath 'bmp_bilinear_reader\s+bmp_read_m0' 'Bilinear loader is instantiated.'
Require-Text $projectPath 'bmp_bilinear_reader\.v' 'Tang Dynasty project references bilinear loader.'
Require-Text $fadePath '^\s*module\s+video_fade_transition\b' 'Fade transition module is present.'
Require-Text $osdPath '^\s*module\s+video_osd_overlay\b' 'OSD overlay module is present.'
Require-Text $topPath 'u_video_fade_transition' 'Fade transition is instantiated in top.'
Require-Text $topPath 'u_video_osd_overlay' 'OSD overlay is instantiated in top.'
Require-Text $projectPath 'video_fade_transition\.v' 'Tang Dynasty project references fade module.'
Require-Text $projectPath 'video_osd_overlay\.v' 'Tang Dynasty project references OSD module.'
Require-Text $pinPath 'HDMI_DDC_SCL' 'HDMI DDC constraint is present.'
Require-Text $pinPath 'sd_ncs' 'TF-card constraint is present.'
Require-Text $pinPath 'key1' 'KEY1 constraint is present.'
Require-Text $pinPath 'key2' 'KEY2 constraint is present.'

Write-Host "`n== BMP test assets ==" -ForegroundColor Cyan
$bmpDirectory = Join-Path $ProjectRoot 'doc\TF卡图片'
if (Test-Path -LiteralPath $bmpDirectory -PathType Container) {
    $bmpFiles = @(Get-ChildItem -LiteralPath $bmpDirectory -Filter '*.bmp' -File)
    if ($bmpFiles.Count -eq 0) {
        Write-Warn 'No BMP files found in doc\TF卡图片.'
    }

    foreach ($bmp in $bmpFiles) {
        $stream = $null
        $reader = $null
        try {
            $stream = [System.IO.File]::OpenRead($bmp.FullName)
            $reader = New-Object System.IO.BinaryReader($stream)
            $stream.Position = 18
            $width = $reader.ReadInt32()
            $height = $reader.ReadInt32()
            $stream.Position = 28
            $bitsPerPixel = $reader.ReadInt16()
            $compression = $reader.ReadInt32()

            if (($width -eq 640) -and ([Math]::Abs($height) -eq 480) -and
                ($bitsPerPixel -eq 24) -and ($compression -eq 0)) {
                Write-Pass "$($bmp.Name): 640x480, 24-bit, uncompressed"
            } else {
                Write-Warn "$($bmp.Name): ${width}x${height}, ${bitsPerPixel}-bit, compression=$compression"
            }
        } catch {
            Write-Warn "$($bmp.Name): unable to parse BMP header ($($_.Exception.Message))"
        } finally {
            if ($reader) { $reader.Dispose() }
            elseif ($stream) { $stream.Dispose() }
        }
    }
} else {
    Write-Warn 'Missing BMP asset directory: doc\TF卡图片'
}

if ($RunImplementation) {
    $RunSynthesis = $true
}

if ($RunSynthesis) {
    $tdCommand = $null
    $commandInfo = Get-Command 'td_commands_prompt.exe' -ErrorAction SilentlyContinue
    if ($commandInfo) {
        $tdCommand = $commandInfo.Source
    }

    $knownTd = 'F:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe'
    if (-not $tdCommand -and (Test-Path -LiteralPath $knownTd -PathType Leaf)) {
        $tdCommand = $knownTd
    }

    if (-not $tdCommand) {
        Write-Fail 'Tang Dynasty td_commands_prompt.exe was not found.'
    } else {
        $tdRoot = Split-Path -Parent (Split-Path -Parent $tdCommand)
        $flowScript = Join-Path $tdRoot 'doc\scripts\DefaultFlow.tcl'
        $synDirectory = Join-Path $ProjectRoot 'src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\syn_1'
        $phyDirectory = Join-Path $ProjectRoot 'src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\phy_1'

        if (-not (Test-Path -LiteralPath $flowScript -PathType Leaf)) {
            Write-Fail "TD flow script not found: $flowScript"
        } elseif (-not (Test-Path -LiteralPath $synDirectory -PathType Container)) {
            Write-Fail "Synthesis run directory not found: $synDirectory"
        } else {
            Invoke-TdFlow $tdCommand ($flowScript -replace '\\','/') $synDirectory 'TD synthesis'
        }

        if ($RunImplementation -and $script:FailureCount -eq 0) {
            if (-not (Test-Path -LiteralPath $phyDirectory -PathType Container)) {
                Write-Fail "Implementation run directory not found: $phyDirectory"
            } else {
                Invoke-TdFlow $tdCommand ($flowScript -replace '\\','/') $phyDirectory 'TD implementation and bitgen'
            }
        }
    }
}

Write-Host "`n== Bitstream freshness ==" -ForegroundColor Cyan
$bitPath = Join-Path $ProjectRoot 'src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\phy_1\HDMI1.4b_Transmitter_v1.0.bit'
if (Test-Path -LiteralPath $bitPath -PathType Leaf) {
    $latestHdl = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'src\user_source\hdl_source') -Recurse -File |
        Where-Object { $_.Extension -in '.v', '.vhd' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $bitFile = Get-Item -LiteralPath $bitPath

    if ($latestHdl -and ($bitFile.LastWriteTime -ge $latestHdl.LastWriteTime)) {
        Write-Pass "Bitstream is newer than the latest HDL file ($($latestHdl.Name))."
    } else {
        if ($RunImplementation) {
            Write-Fail 'Implementation did not produce a bitstream newer than the HDL source.'
        } else {
            Write-Warn 'Bitstream is older than the latest HDL source; rerun implementation.'
        }
    }
} else {
    Write-Warn 'No implementation bitstream found.'
}

Write-Host "`n== Result ==" -ForegroundColor Cyan
if ($script:FailureCount -gt 0) {
    Write-Host "$script:FailureCount check(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host 'All requested checks passed.' -ForegroundColor Green
exit 0

