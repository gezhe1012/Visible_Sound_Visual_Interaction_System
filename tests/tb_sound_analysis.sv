`timescale 1ns/1ps
module tb_sound_analysis #(parameter integer PICTURE_INDEX=0,PLAY_MELODY=0);
reg clk=0,rst=1,hs=1,vs=0,de=0,key3=1;
always #20 clk=~clk;
reg [23:0] rgb_in=0,audio_left=0,audio_right=0;
reg audio_valid=0;
wire requested_visible,panel_visible,wh,wv,wd,hs_out,vs_out,de_out;
wire [23:0] wrgb,rgb_out,osd_rgb,original_osd;
wire spectrum_write,result_done,result_ack;
wire [7:0] spectrum_address;
wire [6:0] spectrum_height;
waveform_key_control #(.CLK_HZ(1000),.DEBOUNCE_MS(5)) keys(.*);
audio_waveform_overlay wave(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb_in(rgb_in),
    .audio_valid(audio_valid),.requested_visible(requested_visible),.audio_left(audio_left),.audio_right(audio_right),
    .panel_visible(panel_visible),.hs_out(wh),.vs_out(wv),.de_out(wd),.rgb_out(wrgb));
audio_fft1024 fft(.*);
audio_spectrum_overlay spectrum(.clk(clk),.rst(rst),.hs(wh),.vs(wv),.de(wd),.rgb_in(wrgb),
    .panel_visible(panel_visible),.audio_valid(audio_valid),.spectrum_write(spectrum_write),
    .spectrum_address(spectrum_address),.spectrum_height(spectrum_height),.result_done(result_done),.result_ack(result_ack),
    .hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out));
video_osd_overlay osd(.clk(clk),.rst(rst),.hs(hs_out),.vs(vs_out),.de(de_out),.rgb_in(rgb_out),
    .lesson_idx(3'(PICTURE_INDEX)),.audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),
    .brightness(9'sd16),.contrast_q2(3'd5),.active_control(2'd0),.rgb_out(osd_rgb));
reg [23:0] original_pipe[0:3];
integer d;
always @(posedge clk) begin
    if(rst) for(d=0;d<4;d=d+1) original_pipe[d]<=0;
    else begin original_pipe[0]<=rgb_in; for(d=1;d<4;d=d+1) original_pipe[d]<=original_pipe[d-1]; end
end
video_osd_overlay original(.clk(clk),.rst(rst),.hs(hs_out),.vs(vs_out),.de(de_out),.rgb_in(original_pipe[3]),
    .lesson_idx(3'(PICTURE_INDEX)),.audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),
    .brightness(9'sd16),.contrast_q2(3'd5),.active_control(2'd0),.rgb_out(original_osd));
wire user,valid,last;
wire [23:0] data;
video_rgb_to_axis_640x480 axis(.I_clk(clk),.I_rst(rst),.I_vs(vs_out),.I_de(de_out),.I_rgb(osd_rgb),
    .O_video_user(user),.O_video_valid(valid),.O_video_last(last),.O_video_data(data));
integer sample_acc=0,sample_number=0;
reg run_audio=1;
wire music_bclk,music_lrck,music_dout,music_valid;
wire [23:0] music_left,music_right;
generate if(PLAY_MELODY) begin : g_music
    science_audio_i2s music(.clk(clk),.rst(rst),.enabled(!rst),.lesson(3'd4),
        .bclk(music_bclk),.lrck(music_lrck),.dout(music_dout),.sample_tick(),
        .pcm_left(),.pcm_right(),.lesson_step(),.melody_complete());
    I2S_receiver music_rx(.I_clk(clk),.I_rst(rst),.I_i2s_BCLK(music_bclk),.I_i2s_LRCK(music_lrck),.I_i2s_DOUT(music_dout),
        .O_audio_valid(music_valid),.O_audio_left_data(music_left),.O_audio_right_data(music_right));
end endgenerate
always @(negedge clk) begin
    audio_valid=0;
    if(!rst && run_audio && PLAY_MELODY) begin
        audio_valid=music_valid; audio_left=music_left; audio_right=music_right;
    end else if(!rst && run_audio) begin
        sample_acc=sample_acc+48000;
        if(sample_acc>=25000000) begin
            sample_acc=sample_acc-25000000; audio_valid=1;
            audio_left=$rtoi(1800000.0*$sin(6.283185307179586*440*sample_number/48000));
            audio_right=$rtoi(1800000.0*$sin(6.283185307179586*660*sample_number/48000));
            sample_number=sample_number+1;
        end
    end
end
integer xx,yy,phase,draw_x=0,draw_y=0,pixels=0,lines=0,starts=0,stream_x=0,fp,fp_hidden;
integer spectrum_pixels=0,wave_pixels=0,bank_swaps=0;
reg raster=0,expected_visible=0;
reg [3:0] eh=0,ev=0,ed=0,er=0,show=0;
integer xp[0:3],yp[0:3],n;
reg [23:0] rp[0:3];
reg [23:0] expected_color;
reg old_bank=1;
always @(posedge clk) if(!rst) begin
    // Writes cannot collide with the bank being scanned out.
    if(spectrum_write && spectrum.display_valid && spectrum.write_bank==spectrum.display_bank)
        $fatal(1,"Spectrum display-bank write collision");
    if(spectrum.display_bank!=old_bank) begin
        if(!spectrum.vs_d || spectrum.x!=0) $fatal(1,"Spectrum swapped during active video");
        bank_swaps=bank_swaps+1; old_bank=spectrum.display_bank;
    end
    for(n=3;n>0;n=n-1) begin xp[n]=xp[n-1]; yp[n]=yp[n-1]; rp[n]=rp[n-1]; end
    xp[0]=draw_x; yp[0]=draw_y; rp[0]=rgb_in;
    eh={eh[2:0],hs}; ev={ev[2:0],vs}; ed={ed[2:0],de}; er={er[2:0],raster&&de}; show={show[2:0],expected_visible};
    #1;
    if({hs_out,vs_out,de_out}!=={eh[3],ev[3],ed[3]}) $fatal(1,"Analysis timing not exactly four clocks");
    if(!de_out && rgb_out!==0) $fatal(1,"Analysis blanking not black");
    if(er[3]) begin
        pixels=pixels+1;
        if(wave.visible_frame!==expected_visible || spectrum.visible_frame!==expected_visible)
            $fatal(1,"Waveform and FFT visibility differ or changed mid-frame");
        if(!show[3] || xp[3]<48 || xp[3]>=592 || yp[3]<120 || yp[3]>=416 || (yp[3]>=236 && yp[3]<238)) begin
            if(rgb_out!==rp[3] || osd_rgb!==original_osd)
                $fatal(1,"Hidden/outside picture, logo or subtitle changed (%0d,%0d)",xp[3],yp[3]);
        end else begin
            if(xp[3]==48 || xp[3]==591 || yp[3]==120 || yp[3]==235 || yp[3]==238 || yp[3]==415)
                if(rgb_out!==24'h60849A) $fatal(1,"Panel border mismatch (%0d,%0d)",xp[3],yp[3]);
            if(xp[3]>=64 && xp[3]<576 && yp[3]>=148 && yp[3]<=214) begin
                expected_color={2'b0,rp[3][23:18],2'b0,rp[3][15:10],2'b0,rp[3][7:2]};
                if(xp[3]==64 || xp[3]==192 || xp[3]==320 || xp[3]==448 || xp[3]==575 || yp[3]==148 || yp[3]==170 || yp[3]==192 || yp[3]==214)
                    expected_color=24'h294052;
                if((xp[3]-64)%4<2) begin
                    if(spectrum.left_ram[{spectrum.display_bank,7'((xp[3]-64)/4)}]!=0 &&
                       yp[3]>214-spectrum.left_ram[{spectrum.display_bank,7'((xp[3]-64)/4)}]) expected_color=24'h52E3FF;
                end else if(spectrum.right_ram[{spectrum.display_bank,7'((xp[3]-64)/4)}]!=0 &&
                       yp[3]>214-spectrum.right_ram[{spectrum.display_bank,7'((xp[3]-64)/4)}]) expected_color=24'hFFE66D;
                if(rgb_out!==expected_color) $fatal(1,"Spectrum RAM/pixel latency mismatch (%0d,%0d):%h/%h",xp[3],yp[3],rgb_out,expected_color);
                if(rgb_out==24'h52E3FF || rgb_out==24'hFFE66D) spectrum_pixels=spectrum_pixels+1;
            end
            if(yp[3]>=255 && yp[3]<=401 && (rgb_out==24'h52E3FF || rgb_out==24'hFFE66D)) wave_pixels=wave_pixels+1;
        end
        if(phase==1) $fwrite(fp,"%c%c%c",osd_rgb[23:16],osd_rgb[15:8],osd_rgb[7:0]);
        if(phase==0 && PLAY_MELODY) $fwrite(fp_hidden,"%c%c%c",osd_rgb[23:16],osd_rgb[15:8],osd_rgb[7:0]);
    end
    if(valid) begin
        if(last!==(stream_x==639)) $fatal(1,"Analysis broke AXIS line end %0d",stream_x);
        if(user) begin if(stream_x!=0) $fatal(1,"SOF not first pixel"); starts=starts+1; end
        if(last) begin lines=lines+1; stream_x=0; end else stream_x=stream_x+1;
    end else if(last || user) $fatal(1,"AXIS framing outside valid");
end
task frame_edge;
    @(negedge clk); de=0; vs=0; repeat(16) @(negedge clk);
    vs=1; repeat(16) @(negedge clk);
endtask
reg [23:0] picture[0:307199];
initial begin
    $readmemh($sformatf("science_image_%0d.hex",PICTURE_INDEX),picture);
    repeat(5) @(negedge clk); rst=0;
    wait(result_done); frame_edge();
    if(!spectrum.display_valid || !wave.display_valid || requested_visible) $fatal(1,"Hidden live analysis startup failed");
    // Short bounces before the first active frame must not enable either panel.
    repeat(3) begin key3=0; repeat(2) @(negedge clk); key3=1; repeat(3) @(negedge clk); end
    if(requested_visible) $fatal(1,"KEY3 bounce enabled analysis");
    fp=$fopen(PLAY_MELODY ? "melody_preview.ppm" : "analysis_panel_preview.ppm","wb"); $fwrite(fp,"P6\n640 480\n255\n");
    if(PLAY_MELODY) begin fp_hidden=$fopen("melody_hidden_preview.ppm","wb"); $fwrite(fp_hidden,"P6\n640 480\n255\n"); end
    for(phase=0;phase<3;phase=phase+1) begin
        expected_visible=(phase==1); raster=1;
        for(yy=0;yy<480;yy=yy+1) begin
            for(xx=0;xx<640;xx=xx+1) begin
                // Scaler goldens are in BMP row order; the real frame writer
                // applies WRITE_V_FLIP=1 before display. Reproduce that here.
                @(negedge clk); de=1; hs=(xx>=96); draw_x=xx; draw_y=yy; rgb_in=picture[(479-yy)*640+xx];
                if(phase<2 && xx==100 && yy==100) key3=0;
            end
            @(negedge clk); de=0; repeat(159) @(negedge clk);
        end
        repeat(8) @(negedge clk); raster=0;
        if(phase<2) begin
            if(requested_visible!==(phase==0)) $fatal(1,"Held press did not toggle once");
            key3=1; repeat(20) @(negedge clk); frame_edge();
        end
    end
    $fclose(fp);
    if(PLAY_MELODY) $fclose(fp_hidden);
    if(pixels!=921600 || lines!=1440 || starts!=3 || spectrum_pixels<100 || wave_pixels<100 || bank_swaps<2)
        $fatal(1,"Incomplete panel checks %0d px %0d lines %0d SOF %0d spectrum %0d wave %0d banks",pixels,lines,starts,spectrum_pixels,wave_pixels,bank_swaps);
    // No audio: invalidate BOTH display snapshots at the next frame boundary.
    run_audio=0; repeat(6250100) @(negedge clk); frame_edge();
    if(spectrum.display_valid || wave.display_valid) $fatal(1,"Stale sound still displayed as live");
    key3=0; repeat(20) @(negedge clk); frame_edge();
    if(!wave.visible_frame || !spectrum.visible_frame) $fatal(1,"Third press failed");
    rst=1; repeat(5) @(negedge clk);
    if(requested_visible || wave.visible_frame || spectrum.visible_frame) $fatal(1,"Reset did not hide whole panel");
    $display("ALL SOUND ANALYSIS TESTS PASSED: KEY3 shared toggle, 921600 pixels, stereo bars, unchanged image/OSD, 1440 TLAST, 3 SOF, banks, stale/reset");
    $finish;
end
initial begin #500000000; $fatal(1,"Analysis test timeout"); end
endmodule

module tb_melody_panel;
tb_sound_analysis #(.PICTURE_INDEX(4),.PLAY_MELODY(1)) test();
endmodule
