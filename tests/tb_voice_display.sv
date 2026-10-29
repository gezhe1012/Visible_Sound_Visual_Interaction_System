`timescale 1ns/1ps
// External serial microphone -> real conditioning -> real FFT -> main raster
// and secondary history/renderer. Independent sine reference, no FFT stubs.
module tb_voice_display;
reg clk=0,rst=1,sd=0;
always #20 clk=~clk;
wire sck,ws,mic_valid,ready;
wire signed [23:0] mic_pcm;
inmp441_i2s_rx #(.STARTUP_FRAMES(4)) mic(.clk(clk),.rst(rst),.mic_sd(sd),.mic_sck(sck),.mic_ws(ws),.mic_valid(mic_valid),.mic_pcm(mic_pcm),.ready(ready));
reg [2:0] lesson=5;
wire lesson_valid=1;
wire audio_valid,source_clear,active,clipped;
wire [23:0] audio_left,audio_right;
wire [3:0] gain_shift;
voice_analysis_source source(.clk(clk),.rst(rst),.lesson(lesson),.lesson_valid(lesson_valid),
    .dds_valid(1'b0),.dds_left(24'd0),.dds_right(24'd0),.mic_valid(mic_valid),.mic_pcm(mic_pcm),
    .analysis_valid(audio_valid),.analysis_left(audio_left),.analysis_right(audio_right),.source_clear(source_clear),
    .active(active),.clipped(clipped),.gain_shift(gain_shift));
integer bit_no=0,frame_no=0;
reg previous_ws=0;
reg [23:0] sample_word=0;
integer tone_hz=440;
reg quiet_mode=0;
integer voice_amplitude=12000;
reg [31:0] noise_rng=32'h9e51a27d;
always @(negedge sck) if(!rst) begin
    if(ws!=previous_ws) begin
        previous_ws=ws;bit_no=0;sd<=#60 0;
        if(!ws) begin
            frame_no=frame_no+1;
            // Voice-like fundamental + harmonics, modest raw microphone level.
            noise_rng={noise_rng[30:0],noise_rng[31]^noise_rng[21]^noise_rng[1]^noise_rng[0]};
            if(quiet_mode) sample_word=$signed({1'b0,noise_rng[9:0]})-512;
            else sample_word=$rtoi(voice_amplitude*$sin(6.283185307179586*tone_hz*frame_no/48000.0)+
                (voice_amplitude/4)*$sin(6.283185307179586*2*tone_hz*frame_no/48000.0)+
                (voice_amplitude/8)*$sin(6.283185307179586*3*tone_hz*frame_no/48000.0));
        end
    end else begin
        bit_no=bit_no+1;
        if(!ws && bit_no>=1 && bit_no<=24) sd<=#60 sample_word[24-bit_no];else sd<=#60 0;
    end
end
integer col=0,line=0,frames=0;
always @(posedge clk) if(!rst) begin
    if(col==799) begin col<=0;if(line==524) begin line<=0;frames<=frames+1;end else line<=line+1;end
    else col<=col+1;
end
wire hs=col>=96,vs=line>=2,de=col>=160 && line>=45;
wire wh,wv,wd,sh,sv,sdv,panel_visible;
wire [23:0] background,wave_rgb,spectrum_rgb,osd_rgb;
wire spectrum_write,result_done,result_ack,capture_start,bin_valid,bin_channel;
wire [7:0] spectrum_address;
wire [6:0] spectrum_height;
wire [6:0] displayed_spectrum_height=(lesson==5 && spectrum_height<8) ? 7'd0 : spectrum_height;
wire [8:0] bin_number;
wire [16:0] bin_magnitude;
live_voice_background bg(.clk(clk),.rst(rst),.vs(vs),.de(de),.ready(ready),.active(active),.clipped(clipped),.panel_visible(1'b1),.rgb(background));
wire ar=rst|source_clear;
audio_waveform_overlay wave(.clk(clk),.rst(ar),.hs(hs),.vs(vs),.de(de),.rgb_in(background),
    .voice_mode(1'b1),.audio_valid(audio_valid),.requested_visible(1'b1),.audio_left(audio_left),.audio_right(audio_right),
    .hs_out(wh),.vs_out(wv),.de_out(wd),.panel_visible(panel_visible),.rgb_out(wave_rgb));
audio_fft1024 fft(.clk(clk),.rst(ar),.*);
audio_spectrum_overlay spectrum(.clk(clk),.rst(ar),.hs(wh),.vs(wv),.de(wd),.rgb_in(wave_rgb),.voice_mode(1'b1),
    .panel_visible(panel_visible),.audio_valid(audio_valid),.spectrum_write(spectrum_write),.result_done(result_done),
    .result_ack(result_ack),.spectrum_address(spectrum_address),.spectrum_height(displayed_spectrum_height),
    .hs_out(sh),.vs_out(sv),.de_out(sdv),.rgb_out(spectrum_rgb));
video_osd_overlay osd(.clk(clk),.rst(rst),.hs(sh),.vs(sv),.de(sdv),.rgb_in(spectrum_rgb),
    .brightness(9'sd0),.contrast_q2(3'd4),.active_control(2'd0),.lesson_idx(lesson),
    .audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),.rgb_out(osd_rgb));
wire frame_tick,scene_clear,shown_right;
wire [6:0] read_column,shown_head,shown_count;
wire [5:0] read_band;
wire [3:0] heat_q;
wire [7:0] trace_q,peak_left,peak_right,average_left,average_right;
wire [79:0] shown_feature,analysis_feature;
wire analysis_ready,audio_stale;
secondary_feature_store features(.spectrum_height(displayed_spectrum_height),.*);
wire axis_user,axis_valid,axis_last;
wire [23:0] axis_data;
wire [11:0] xy_read_address;
secondary_audio_renderer renderer(.video_locked(1'b1),.harmonic_heights(30'd0),.harmonic_valid(1'b0),
    .xy_q(1'b0),.xy_visible(1'b0),.*);
integer good440=0,good880=0,blocks=0,published=0;
reg [6:0] prior_head=0;
always @(posedge clk) if(!rst) begin
    if(result_done) blocks=blocks+1;
    #1;
    if(shown_head!=prior_head) begin
        prior_head=shown_head;published=published+1;
        if(renderer.col!=1 || renderer.line!=0) $fatal(1,"Voice history tore during active frame");
        if(shown_feature[79]) begin
            if(shown_feature[78:64]>=420 && shown_feature[78:64]<=460) good440=good440+1;
            if(shown_feature[78:64]>=860 && shown_feature[78:64]<=900) good880=good880+1;
        end
    end
end
integer main_fp,secondary_fp,main_pixels=0,secondary_pixels=0,wave_pixels=0,fft_pixels=0,check_index;
reg dump=0,main_dump=0,secondary_dump=0;
reg [9:0] main_x=0,main_y=0;
reg prior_sdv=0;
always @(posedge clk) begin
    #2;
    if(!rst) begin
        prior_sdv=sdv;
        if(dump && main_pixels<307200 && sdv) begin
            $fwrite(main_fp,"%c%c%c",osd_rgb[23:16],osd_rgb[15:8],osd_rgb[7:0]);main_pixels=main_pixels+1;
            if((osd_rgb==24'h52E3FF || osd_rgb==24'hFFE66D)) wave_pixels=wave_pixels+1;
            if(osd_rgb==24'h5BDAC6) fft_pixels=fft_pixels+1;
        end
        if(dump && axis_valid && secondary_pixels<307200) begin
            $fwrite(secondary_fp,"%c%c%c",axis_data[23:16],axis_data[15:8],axis_data[7:0]);secondary_pixels=secondary_pixels+1;
        end
    end
end
initial begin
    repeat(8) @(negedge clk);rst=0;
    wait(frames==12);@(negedge clk);
    if(good440<3 || !active || shown_count<3) $fatal(1,"440Hz microphone FFT/history not live");
    tone_hz=880;
    wait(frames==24);@(negedge clk);
    if(good880<3 || !wave.display_valid || !spectrum.display_valid) $fatal(1,"Microphone tone/trace response failed");
    main_fp=$fopen("voice_main.ppm","wb");secondary_fp=$fopen("voice_secondary.ppm","wb");
    $fwrite(main_fp,"P6\n640 480\n255\n");$fwrite(secondary_fp,"P6\n640 480\n255\n");dump=1;
    wait(main_pixels==307200 && secondary_pixels==307200);dump=0;
    $fclose(main_fp);$fclose(secondary_fp);
    if(wave_pixels<500 || fft_pixels<500 || blocks<8 || published<8) $fatal(1,"Voice display coverage too small");
    // Abort an in-flight block on source change, then re-enter microphone.
    @(negedge clk);lesson=0;wait(source_clear);@(negedge clk);
    if(fft.capture_index!=0 || fft.state!=0) $fatal(1,"Mixed-source FFT block survived exit");
    wait(frames==27);@(negedge clk);lesson=5;wait(source_clear);@(negedge clk);
    if(fft.capture_index!=0 || fft.state!=0) $fatal(1,"Mixed-source FFT block survived re-entry");
    wait(frames==33);@(negedge clk);
    if(shown_count<1 || !shown_feature[79] || shown_feature[78:64]<860 || shown_feature[78:64]>900)
        $fatal(1,"Microphone source re-entry did not recover new FFT/history");
    quiet_mode=1;
    wait(frames==47);@(negedge clk);
    if(active || gain_shift!=4 || shown_feature[79] || peak_left!=0 || average_left!=0)
        $fatal(1,"Quiet microphone left stale peak/pitch/level");
    // Inspect the actual PUBLISHED display RAM banks, not just input words.
    for(check_index=0;check_index<128;check_index=check_index+1)
        if(spectrum.left_ram[{spectrum.display_bank,7'd0}+check_index]!==0)
            $fatal(1,"Quiet FFT display RAM has noise at band%0d",check_index);
    for(check_index=0;check_index<256;check_index=check_index+1)
        if(wave.wave_ram[{wave.display_bank,8'd0}+check_index]!=={6'd31,6'd31,6'd31,6'd31})
            $fatal(1,"Quiet waveform is not flat in published RAM");
    for(check_index=0;check_index<64;check_index=check_index+1)
        if(features.heat_ram[{shown_head-7'd1,6'd0}+check_index]!==0)
            $fatal(1,"New quiet waterfall column has energy at band%0d",check_index);
    if(features.trace_ram[shown_head-7'd1][7]!==0) $fatal(1,"New quiet pitch trace not quiet");
    // Dump quiet frame after RAM checks. Historical waterfall rows correctly
    // remain as history, rather than blanking valid earlier voice activity.
    main_pixels=0;secondary_pixels=0;
    main_fp=$fopen("voice_quiet_main.ppm","wb");secondary_fp=$fopen("voice_quiet_secondary.ppm","wb");
    $fwrite(main_fp,"P6\n640 480\n255\n");$fwrite(secondary_fp,"P6\n640 480\n255\n");dump=1;
    wait(main_pixels==307200 && secondary_pixels==307200);dump=0;
    $fclose(main_fp);$fclose(secondary_fp);
    voice_amplitude=3000;tone_hz=440;quiet_mode=0;
    wait(frames==59);@(negedge clk);
    if(!active || !shown_feature[79] || shown_feature[78:64]<420 || shown_feature[78:64]>460)
        $fatal(1,"Weak voice did not recover FFT/pitch after silence");
    $display("ALL VOICE DISPLAY TESTS PASSED: serial mic -> DC/AGC -> real FFT, 440/880Hz checks %0d/%0d, %0d frame-atomic histories, voice/quiet rasters, %0d wave and %0d FFT pixels, source exit/re-entry, flat published quiet wave, zero FFT/new waterfall, invalid quiet pitch, weak-voice recovery",good440,good880,published,wave_pixels,fft_pixels);
    $finish;
end
initial begin #1100000000;$fatal(1,"Voice display timeout");end
endmodule
