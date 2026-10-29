`timescale 1ns/1ps
module tb_voice_input;
reg clk=0,rst=1,sd=0;
always #20 clk=~clk;
wire sck,ws,valid,ready;
wire signed [23:0] pcm;
inmp441_i2s_rx #(.STARTUP_FRAMES(8)) rx(.clk(clk),.rst(rst),.mic_sd(sd),
    .mic_sck(sck),.mic_ws(ws),.mic_pcm(pcm),.mic_valid(valid),.ready(ready));
integer bit_no=0,frame_no=0,words=0,edges=0,half_edges=0,cycles=0,last_valid_cycle=0;
integer checked=0;
reg previous_ws=0,last_valid=0;
reg [23:0] word=24'h123456;
time last_edge=0,last_rise=0,first_word_time=0,last_word_time=0;
function automatic [23:0] pattern(input integer n);
    case(n%6)
        0:pattern=24'h123456;1:pattern=24'hfedcba;2:pattern=24'h800000;
        3:pattern=24'h7fffff;4:pattern=24'h000001;default:pattern=24'hffffff;
    endcase
endfunction
// Independent external slave: one dummy bit at WS edge, then 24 MSB-first
// bits on FALLING SCK; 60ns external/board delay exercises the input sampler.
always @(negedge sck) if(!rst) begin
    if(ws!=previous_ws) begin
        previous_ws=ws;bit_no=0;sd<=#60 0;
        if(!ws) begin frame_no=frame_no+1;word=pattern(frame_no);end
    end else begin
        bit_no=bit_no+1;
        if(!ws && bit_no>=1 && bit_no<=24) sd<=#60 word[24-bit_no];
        else sd<=#60 0;
    end
end
always @(sck) if(!rst && $time>500) begin
    if(last_edge!=0 && $time-last_edge<160) $fatal(1,"SCK high/low too short");
    last_edge=$time;
end
always @(posedge sck) if(!rst) begin
    if(last_rise!=0 && ($time-last_rise<320 || $time-last_rise>360)) $fatal(1,"SCK period outside verified bounds");
    last_rise=$time;edges=edges+1;half_edges=half_edges+1;
end
always @(ws) if(!rst && $time>500) begin
    if(half_edges!=32) $fatal(1,"WS half-frame not 32 SCK: %0d",half_edges);
    half_edges=0;
end
always @(posedge clk) begin
    cycles=cycles+1;
    #1;
    if(!rst) begin
        if(valid && last_valid) $fatal(1,"mic_valid longer than one video clock");
        last_valid=valid;
        if(valid) begin
            if(!ready || frame_no<8) $fatal(1,"Startup suppression failed");
            if(pcm!==word) $fatal(1,"I2S word/sign/delay mismatch frame%0d got%h expected%h",frame_no,pcm,word);
            if(last_valid_cycle!=0 && cycles-last_valid_cycle!=520 && cycles-last_valid_cycle!=521)
                $fatal(1,"Sample cadence wrong: %0d",cycles-last_valid_cycle);
            last_valid_cycle=cycles;words=words+1;
            if(words==1) first_word_time=$time;
            last_word_time=$time;
        end
    end
end
reg [2:0] lesson=0;
reg dds_valid=0,mic_valid=0;
reg signed [23:0] mic_pcm=0;
wire analysis_valid,source_clear,active,clipped;
wire [23:0] analysis_left,analysis_right;
wire [3:0] gain_shift;
voice_analysis_source source(.clk(clk),.rst(rst),.lesson(lesson),.lesson_valid(1'b1),
    .dds_valid(dds_valid),.dds_left(24'habcd12),.dds_right(24'h1234ab),.mic_valid(mic_valid),.mic_pcm(mic_pcm),
    .analysis_valid(analysis_valid),.analysis_left(analysis_left),.analysis_right(analysis_right),
    .source_clear(source_clear),.active(active),.clipped(clipped),.gain_shift(gain_shift));
task sample(input integer value);
    @(negedge clk);mic_pcm=value;mic_valid=1;
    @(negedge clk);mic_valid=0;
endtask
integer i;
initial begin
    repeat(8) @(negedge clk);rst=0;
    repeat(4) @(negedge clk);dds_valid=1;
    for(i=0;i<5;i=i+1) begin
        lesson=i;repeat(3) @(negedge clk);
        if(!analysis_valid || analysis_left!==24'habcd12 || analysis_right!==24'h1234ab) $fatal(1,"DDS page changed");
    end
    lesson=5;repeat(4) @(negedge clk);
    for(i=0;i<8192;i=i+1) sample((i%32)<16 ? 10000 : -10000);
    if(!active || gain_shift<5 || analysis_left!=analysis_right) $fatal(1,"Voice gain/mono/level adaptation failed");
    sample(8388607);#1;if(analysis_left!==24'h7fffff) $fatal(1,"Positive saturation failed %h",analysis_left);
    sample(-8388608);#1;if(analysis_left!==24'h800000) $fatal(1,"Negative saturation failed %h",analysis_left);
    for(i=0;i<16384;i=i+1) sample(10000);
    if(active || source.gate_open) $fatal(1,"DC rejection/quiet noise gate failed");
    lesson=0;repeat(4) @(negedge clk);
    if(!analysis_valid || analysis_left!==24'habcd12 || analysis_right!==24'h1234ab) $fatal(1,"DDS return failed");
    wait(words>=2049);
    if(last_word_time-first_word_time<42666600 || last_word_time-first_word_time>42666720) $fatal(1,"Average sample rate not 48K");
    $display("ALL VOICE INPUT TESTS PASSED: 2049 exact signed words, 60ns slave delay, 32-bit slots, 64 clocks/frame, 48K average, 160ns minimum half-period, DDS isolation, gain, clipping, DC gate");
    $finish;
end
initial begin #60000000;$fatal(1,"Voice receiver timeout words%0d",words);end
endmodule
