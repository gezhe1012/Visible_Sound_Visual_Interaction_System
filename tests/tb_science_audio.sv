`timescale 1ns/1ps
module tb_science_audio;
reg clk=0,rst=1,enabled=0;
always #20 clk=~clk; // 25MHz
reg [1:0] lesson=0;
wire bclk,lrck,dout,sample_tick;
wire [23:0] pcm_left,pcm_right,rx_left,rx_right;
wire [1:0] lesson_step;
wire rx_valid;
reg vs=0;
wire wave_hs,wave_vs,wave_de;
wire [23:0] wave_rgb;
integer snapshots=0;
science_audio_i2s #(.STEP_SAMPLES(512)) dut(.*);
I2S_receiver rx(.I_clk(clk),.I_rst(rst),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),
    .O_audio_valid(rx_valid),.O_audio_left_data(rx_left),.O_audio_right_data(rx_right));
audio_waveform_overlay wave_display(.clk(clk),.rst(rst),.hs(1'b1),.vs(vs),.de(1'b0),.rgb_in(24'd0),
    .audio_valid(rx_valid),.requested_visible(1'b1),.audio_left(rx_left),.audio_right(rx_right),
    .hs_out(wave_hs),.vs_out(wave_vs),.de_out(wave_de),.rgb_out(wave_rgb));
reg [47:0] vectors[0:8191];
reg [47:0] queue[0:9000];
integer wr=1,rd=0,checked=0,reference_index=0,page,total=0,clock_count=0,last_tick=0;
reg [47:0] expected;
reg check_frame;
always @(posedge clk) begin
    clock_count=clock_count+1;
    if(!rst && wave_display.frame_tick && wave_display.pending) snapshots=snapshots+1;
    if(!rst && wave_display.capture_accept && wave_display.display_valid &&
       wave_display.capture_bank==wave_display.display_bank) $fatal(1,"Teaching waveform bank collision");
    if(!rst) begin
        if(dut.mclk_enable && dut.bclk && dut.bit_count==63 && dut.lrck) begin
            if(last_tick!=0 && clock_count-last_tick!=520 && clock_count-last_tick!=521)
                $fatal(1,"48K sample interval invalid: %0d",clock_count-last_tick);
            last_tick=clock_count;
            check_frame=enabled && dut.active_lesson==lesson;
            if(check_frame) expected=vectors[lesson*2048+reference_index];
            else reference_index=0;
            #1;
            if(check_frame) begin
                if({pcm_left,pcm_right}!==expected)
                    $fatal(1,"PCM page%0d sample%0d: %h != %h",lesson,reference_index,{pcm_left,pcm_right},expected);
                reference_index=reference_index+1; checked=checked+1; total=total+1;
            end
        end
    end
end
always @(negedge clk) if(!rst) vs=(clock_count%10000>=5);
always @(posedge clk) begin
    if(!rst) begin
        if(sample_tick) begin queue[wr]={pcm_left,pcm_right}; wr=wr+1; end
        if(rx_valid) begin
            if(rd>=wr || {rx_left,rx_right}!==queue[rd])
                $fatal(1,"I2S roundtrip mismatch rx%0d tx%0d: %h/%h",rd,wr,{rx_left,rx_right},queue[rd]);
            rd=rd+1;
        end
    end
end
task wait_samples(input integer n);
    repeat(n) begin @(posedge sample_tick); @(negedge clk); end
endtask
initial begin
    $readmemh("science_audio_vectors.hex",vectors); queue[0]=0;
    repeat(8) @(negedge clk); rst=0;
    for(page=0;page<4;page=page+1) begin
        enabled=0; lesson=2'(page); wait_samples(3);
        checked=0; reference_index=0; enabled=1;
        wait(checked==2048); @(negedge clk); enabled=0;
        $display("PASS teaching audio page %0d: 2048 bit-exact PCM pairs across four stages",page);
    end
    wait_samples(3);
    if(total!=8192 || rd<8192 || snapshots<10) $fatal(1,"Audio regression incomplete");
    $display("ALL SCIENCE AUDIO TESTS PASSED: 8192 independent PCM pairs, stereo routing, envelopes, 48K clock-enable and I2S roundtrip");
    $finish;
end
initial begin #300000000; $fatal(1,"Science audio timeout checked=%0d rx=%0d",total,rd); end
endmodule
