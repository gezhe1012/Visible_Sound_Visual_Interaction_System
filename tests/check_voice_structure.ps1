[CmdletBinding()]
param([switch]$CheckRouted)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
function Assert-Voice([bool]$ok,[string]$text) {if(!$ok){throw $text};Write-Host "PASS: $text"}
try {
    $top=Get-Content src/user_source/hdl_source/top_tf_hdmi_audio.v -Raw
    $pins=Get-Content src/user_source/constraints_source/pin.adc -Raw
    $active=@($pins -split '\r?\n' | Where-Object {$_ -match '^\s*set_pin_assignment'})
    foreach($pair in @(@('mic_sck','M15'),@('mic_ws','L16'),@('mic_sd','N16'))) {
        $hits=@($active | Where-Object {$_ -match ('LOCATION\s*=\s*'+$pair[1]+'\s*;')})
        Assert-Voice ($hits.Count -eq 1 -and $hits[0] -match ('\{\s*'+$pair[0]+'\s*\}')) "Exclusive microphone pad $($pair[0])=$($pair[1])"
    }
    Assert-Voice ($top -match '\.SCAN_TARGET_COUNT\s*\(3.d5\)' -and $top -match '\.LIVE_VOICE_PAGE\s*\(1\)') 'Five real BMP files plus a virtual sixth page'
    Assert-Voice ($top -match '\.I_audio_valid\s*\(audio_valid\)' -and $top -match '\.I_audio_left_data\s*\(audio_left_data\)' -and $top -match '\.I_audio_right_data\s*\(audio_right_data\)') 'HDMI packetizer still consumes original decoded DDS PCM'
    Assert-Voice ($top -match '\.audio_valid\(analysis_valid\)' -and $top -match '\.audio_left\(analysis_left\)') 'Waveform/FFT/secondary use the selected analysis source'
    Assert-Voice (([regex]::Matches($top,'\.spectrum_height\(displayed_spectrum_height\)')).Count -eq 2 -and
        $top -match 'displayed_spectrum_height=\(voice_page && spectrum_height<7.d8\) \? 7.d0 : spectrum_height' -and
        ([regex]::Matches($top,'\.spectrum_height\(spectrum_height\)')).Count -eq 1) 'Shared microphone-only residual floor feeds both displays; raw FFT and five DDS pages stay unmasked'
    foreach($name in @('src/user_source/constraints_source','src/user_source/hdl_source/inmp441_i2s_rx.v','src/user_source/hdl_source/live_voice_background.v','src/user_source/hdl_source/SD')) {
        git diff --quiet b2feea7 -- $name
        Assert-Voice ($LASTEXITCODE -eq 0) "Noise iteration preserves interface/timing/layout: $name"
    }
    $baseline=(git show b2feea7:src/user_source/hdl_source/voice_analysis_source.v) -join "`n"
    $fixture=(Get-Content tests/voice_baseline_conditioner.v -Raw).Replace("`r",'').Trim()
    Assert-Voice ($fixture -ceq $baseline.Replace('module voice_analysis_source(','module voice_baseline_conditioner(').Trim()) 'Noise A/B fixture exactly matches b2feea7, except its module name'
    foreach($name in @('voice_analysis_source.v','inmp441_i2s_rx.v','top_tf_hdmi_audio.v','secondary_feature_store.v','secondary_pitch_estimator.v','audio_waveform_overlay.v')) {
        git diff --quiet bf35426 -- "src/user_source/hdl_source/$name"
        Assert-Voice ($LASTEXITCODE -eq 0) "Voice-focus iteration preserves acquisition/analysis/control chain: $name"
    }
    $priorRenderer=(git show bf35426:src/user_source/hdl_source/secondary_audio_renderer.v) -join "`n"
    $priorFixture=(Get-Content tests/voice_baseline_focus_secondary.v -Raw).Replace("`r",'').Trim()
    Assert-Voice ($priorFixture -ceq $priorRenderer.Replace('module secondary_audio_renderer(','module voice_baseline_focus_secondary(').Trim()) 'Voice-focus secondary reference exactly matches bf35426'
    $oldLogo=(git show f915d8c:src/user_source/hdl_source/video_osd_overlay.v) -join "`n"
    $oldLogoFixture=(Get-Content tests/voice_baseline_logo_osd.v -Raw).Replace("`r",'').Trim()
    Assert-Voice ($oldLogoFixture -ceq $oldLogo.Replace('module video_osd_overlay #(','module voice_baseline_logo_osd #(').Trim()) 'Logo-only OSD reference exactly matches f915d8c; independent six-page pixel test covers its intentional replacement'
    foreach($name in @('audio_spectrum_overlay.v','secondary_audio_renderer.v','sound_theme_footer.v')) {
        git diff --quiet f915d8c -- "src/user_source/hdl_source/$name"
        Assert-Voice ($LASTEXITCODE -eq 0) "Logo replacement preserves prior spectrum/secondary/footer implementation: $name"
    }
    $protected=@('I2S_receiver.v','science_audio_i2s.v','audio_arc_calculate.v','audio_fft1024.v','display_key_controls.v','waveform_key_control.v','video_fade_transition.v','video_picture_adjust.v','science_sys_pll.v','SD/bmp_bilinear_reader.v','SD/frame_fifo_read.v','SD/frame_read_write.v')
    foreach($name in $protected) {
        git diff --quiet 6e58891 -- "src/user_source/hdl_source/$name"
        Assert-Voice ($LASTEXITCODE -eq 0) "Protected original source unchanged: $name"
    }
    git diff --quiet 6e58891 -- src/td_project/al_ip src/user_source/hdl_source/IP src/user_source/hdl_source/hdmi1.4b_transmitter_core
    Assert-Voice ($LASTEXITCODE -eq 0) 'PLL/IP/vendor sources are unchanged'
    $sdc=(Get-Content src/user_source/constraints_source/timing.sdc -Raw).Replace("`r",'')
    Assert-Voice ($sdc -match '(?m)^set_false_path -from \[get_ports \{mic_sd\}\]$') 'Microphone exception starts only at the external SD pad'
    Assert-Voice (([regex]::Matches($sdc,'(?m)^\s*set_false_path')).Count -eq 2 -and $sdc -match 'read_req_d0_reg\*\.d' -and $sdc -notmatch 'read_req_d[12]_reg') 'Exactly two narrow exceptions: microphone pad and held-request first synchronizer D; no clock-group or data-path cut'
    $rx=Get-Content src/user_source/hdl_source/inmp441_i2s_rx.v -Raw
    Assert-Voice ($rx -match 'sd_meta<=mic_sd;sd_sync<=sd_meta;' -and $rx -notmatch '@\(posedge mic_sck') 'Dedicated two-stage SD sampler; no fabric clock domain'
    foreach($name in @('inmp441_i2s_rx','voice_analysis_source','live_voice_background')) {
        foreach($project in @('src/td_project/HDMI1.4b_Transmitter_v1.0.al','src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/HDMI1.4b_Transmitter_v1.0.prj','src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0.prj')) {
            Assert-Voice ((Get-Content $project -Raw) -match ($name+'\.v')) "Project references $name in $project"
        }
    }
    if($CheckRouted) {
        $area=Get-Content src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0_phy.area -Raw
        foreach($pair in @(@('mic_sck','M15'),@('mic_ws','L16'),@('mic_sd','N16'))) {
            Assert-Voice ($area -match ('(?m)^\s*'+$pair[0]+'\s+\S+\s+'+$pair[1]+'\s+')) "Routed pad confirmed: $($pair[0])=$($pair[1])"
        }
        $timing=Get-Content src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0_pr.timing -Raw
        $setup=[regex]::Match($timing,'SWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
        $hold=[regex]::Match($timing,'HWNS:\s*(-?[0-9.]+)ns').Groups[1].Value
        Assert-Voice ($setup -ne '' -and $hold -ne '' -and [double]$setup -ge 0 -and [double]$hold -ge 0) "Routed setup/hold passed: $setup / $hold ns"
    }
    Write-Host 'ALL VOICE STRUCTURE TESTS PASSED: protected DDS/audio/video/IP, five assets plus sixth page, single analysis chain, explicit microphone pins and sampler'
} finally {Pop-Location}
