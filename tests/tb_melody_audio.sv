`timescale 1ns/1ps
// Real 25MHz / real rational 48kHz. Full 8s phrase, no forced clock/sample pulse.
module tb_melody_audio;
reg clk=0,rst=1,enabled=0;
always #20 clk=~clk;
reg [2:0] lesson=4;
wire bclk,lrck,dout,sample_tick,melody_complete;
wire [23:0] pcm_left,pcm_right,rx_left,rx_right;
wire [1:0] lesson_step;
wire rx_valid;
science_audio_i2s dut(.*);
I2S_receiver rx(.I_clk(clk),.I_rst(rst),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),
    .O_audio_valid(rx_valid),.O_audio_left_data(rx_left),.O_audio_right_data(rx_right));
wire fft_write,fft_done,fft_ack;
wire [7:0] fft_address;
wire [6:0] fft_height;
wire wh,wv,wd,sh,sv,sd,panel_visible;
wire [23:0] wrgb,srgb;
reg vs=0,requested_visible=0;
audio_waveform_overlay wave(.clk(clk),.rst(rst),.hs(1'b1),.vs(vs),.de(1'b0),.rgb_in(24'd0),
    .audio_valid(rx_valid),.requested_visible(requested_visible),.audio_left(rx_left),.audio_right(rx_right),
    .panel_visible(panel_visible),.hs_out(wh),.vs_out(wv),.de_out(wd),.rgb_out(wrgb));
audio_fft1024 fft(.clk(clk),.rst(rst),.audio_valid(rx_valid),.audio_left(rx_left),.audio_right(rx_right),
    .result_ack(fft_ack),.spectrum_write(fft_write),.spectrum_address(fft_address),.spectrum_height(fft_height),.result_done(fft_done));
audio_spectrum_overlay spectrum(.clk(clk),.rst(rst),.hs(wh),.vs(wv),.de(wd),.rgb_in(wrgb),
    .panel_visible(panel_visible),.audio_valid(rx_valid),.spectrum_write(fft_write),.spectrum_address(fft_address),
    .spectrum_height(fft_height),.result_done(fft_done),.result_ack(fft_ack),
    .hs_out(sh),.vs_out(sv),.de_out(sd),.rgb_out(srgb));
reg [47:0] vectors[0:383999];
reg [47:0] fifo[0:3];
integer sent=1,received=0,blocks=0,cycles=0,last_tick=0,i;
integer active_note=-1,note_transitions=0;
reg [7:0] seen_notes=0;
integer peak_bin=0,peak_height=0,last_peak=-1,peak_changes=0;
always @(negedge clk) if(!rst) begin
    cycles=cycles+1; vs=(cycles%420000>=1600);
end
always @(posedge clk) if(!rst) begin
    if(sample_tick) begin
        if(last_tick!=0 && cycles-last_tick!=520 && cycles-last_tick!=521) $fatal(1,"Melody sample cadence changed");
        last_tick=cycles; fifo[sent%4]={pcm_left,pcm_right}; sent=sent+1;
    end
    if(rx_valid) begin
        if(received>=sent || {rx_left,rx_right}!==fifo[received%4]) $fatal(1,"Melody I2S/HDMI PCM altered");
        received=received+1;
    end
    if(fft_write && !fft_address[7]) begin
        if(fft_address==0) begin peak_height=0; peak_bin=0; end
        if(fft_height>peak_height) begin peak_height=fft_height; peak_bin=fft_address; end
        if(fft_address==127 && peak_height>0) begin
            if(last_peak>=0 && peak_bin!=last_peak) peak_changes=peak_changes+1;
            last_peak=peak_bin;
        end
    end
    if(fft_done) blocks=blocks+1;
end
task tick;
    @(posedge sample_tick); #1; @(negedge clk);
endtask
initial begin
    $readmemh("melody_full_vectors.hex",vectors); fifo[0]=0;
    repeat(8) @(negedge clk); rst=0;
    repeat(3) tick(); enabled=1;
    for(i=0;i<384000;i=i+1) begin
        tick();
        if({pcm_left,pcm_right}!==vectors[i]) $fatal(1,"Full melody PCM %0d: %h != %h",i,{pcm_left,pcm_right},vectors[i]);
        if(i<383999 && melody_complete) $fatal(1,"Music completed before final note ended");
        if(dut.melody_note!=active_note) begin active_note=dut.melody_note; note_transitions=note_transitions+1; end
        // Same request that KEY3 produces: visibility must not affect the sound.
        if(i==96000) requested_visible=1;
        if(i==288000) requested_visible=0;
        if(i%48000==47999) $display("PASS full melody second %0d / 8",i/48000+1);
    end
    if(!melody_complete || pcm_left!=0 || note_transitions!=17) $fatal(1,"Melody completion boundary incorrect");
    repeat(200) begin tick(); if(!melody_complete || pcm_left || pcm_right) $fatal(1,"End of music is not silent/sticky"); end
    // Manual departure mid-note must still work and re-entry must start at C4.
    lesson=0; repeat(3) tick();
    if(melody_complete) $fatal(1,"Leaving music failed to clear completion");
    enabled=0; lesson=4; repeat(3) tick(); enabled=1;
    for(i=0;i<512;i=i+1) begin tick(); if({pcm_left,pcm_right}!==vectors[i]) $fatal(1,"Melody re-entry did not restart"); end
    lesson=1; repeat(3) tick();
    if(dut.active_lesson!=1 || melody_complete) $fatal(1,"Manual override blocked by melody");
    if(blocks<150 || peak_changes<6 || received<384000) $fatal(1,"Live analysis incomplete blocks=%0d peaks=%0d",blocks,peak_changes);
    $display("ALL MELODY AUDIO TESTS PASSED: 384000 bit-exact stereo pairs, 17 notes, real 48K/I2S, %0d FFT blocks and %0d moving peaks, complete/silent/re-entry/manual override",blocks,peak_changes);
    $finish;
end
initial begin #(64'd8500000000); $fatal(1,"Full music timeout sample%0d",i); end
endmodule
