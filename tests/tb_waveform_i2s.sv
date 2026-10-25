`timescale 1ns/1ps
module tb_waveform_i2s;
reg clk=0,mclk=0,rst=1;
always #20 clk=~clk;
always #40.69 mclk=~mclk; // asynchronous 12.288MHz vs 25MHz
wire bclk,lrck,dout,audio_valid;
wire [23:0] left_data,right_data,rgb_out;
wire hs_out,vs_out,de_out;
reg vs=0;
integer samples=0,edges=0,frames=0,cycles=0;
integer captured=0,cell_address;
reg [5:0] expected_level;
reg previous_sign=0;
hdmi_audio_tone_i2s_64fs #(.NOTE_HOLD_FRAMES(64)) tone(
    .I_mclk(mclk),.I_rst(rst),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver rx(.I_clk(clk),.I_rst(rst),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),
    .O_audio_valid(audio_valid),.O_audio_left_data(left_data),.O_audio_right_data(right_data));
audio_waveform_overlay dut(.clk(clk),.rst(rst),.hs(1'b1),.vs(vs),.de(1'b0),.rgb_in(24'd0),
    .audio_valid(audio_valid),.audio_left(left_data),.audio_right(right_data),
    .hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out));
always @(negedge clk) begin
    if(!rst) begin cycles=cycles+1; vs=(cycles%50000>=10); end
end
always @(posedge clk) begin
    if(!rst && dut.capture_accept) begin
        if(dut.display_valid && dut.capture_bank==dut.display_bank)
            $fatal(1,"Capture wrote the displayed bank");
        cell_address={dut.capture_bank,dut.capture_index};
        expected_level=left_data[23] ? 6'd62 : 6'd1;
        captured=captured+1;
        #1;
        if(dut.wave_ram[cell_address][23:18]!==expected_level ||
           dut.wave_ram[cell_address][11:6]!==expected_level)
            $fatal(1,"Captured I2S does not match played PCM");
    end
end
always @(posedge clk) begin
    if(!rst && audio_valid) begin
        samples=samples+1;
        if(samples>5) begin
            if(left_data!==24'(2000000) && left_data!==24'(-2000000))
                $fatal(1,"Unexpected received PCM %h",left_data);
            if(left_data!==right_data) $fatal(1,"Stereo PCM mismatch %h/%h",left_data,right_data);
            if(left_data[23]!=previous_sign) edges=edges+1;
            previous_sign=left_data[23];
        end
    end
    if(!rst && dut.frame_tick && dut.pending) frames=frames+1;
end
initial begin
    repeat(12) @(negedge clk); rst=0;
    wait(samples>=1600); repeat(10) @(negedge clk);
    if(edges<10 || frames<3 || captured<768 || !dut.display_valid)
        $fatal(1,"I2S waveform not live: edges%0d frames%0d",edges,frames);
    $display("ALL I2S WAVEFORM TESTS PASSED: %0d original PCM pairs, %0d transitions, %0d frame snapshots, %0d checked captures",samples,edges,frames,captured);
    $finish;
end
initial begin #40000000; $fatal(1,"I2S integration timeout samples=%0d",samples); end
endmodule
