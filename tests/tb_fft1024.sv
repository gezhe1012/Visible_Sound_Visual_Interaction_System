`timescale 1ns/1ps
module tb_fft1024;
reg clk=0,rst=1,audio_valid=0,result_ack=0;
always #20 clk=~clk;
reg [23:0] audio_left=0,audio_right=0;
wire spectrum_write,result_done;
wire [7:0] spectrum_address;
wire [6:0] spectrum_height;
audio_fft1024 dut(.*);
reg [31:0] inputs[0:8191],expected[0:16383];
reg [7:0] heights[0:2047];
integer block_index=0,i,k,complex_checked=0,height_checked=0,writes=0,cycles=0,compute_start=0;
reg [31:0] old_word;
always @(posedge clk) if(!rst) begin
    cycles=cycles+1;
    if(dut.state==1 && dut.channel==0 && dut.load_index==0) compute_start=cycles;
    if(dut.state==16 && dut.bin_index==0) begin
        for(k=0;k<1024;k=k+1) begin
            if(dut.fft_ram[k]!==expected[block_index*2048+dut.channel*1024+k])
                $fatal(1,"Complex mismatch block%0d ch%0d bin%0d: %h != %h",block_index,dut.channel,k,dut.fft_ram[k],expected[block_index*2048+dut.channel*1024+k]);
            complex_checked=complex_checked+1;
        end
    end
    if(spectrum_write) begin
        if(spectrum_address!==8'(writes) || spectrum_height!==heights[block_index*256+writes][6:0])
            $fatal(1,"Height mismatch block%0d addr%0d got%0d expected%0d",block_index,spectrum_address,spectrum_height,heights[block_index*256+writes]);
        writes=writes+1; height_checked=height_checked+1;
    end
    if(result_done && (writes!=256 || cycles-compute_start>130000))
        $fatal(1,"Incomplete or slow block: %0d heights, %0d clocks",writes,cycles-compute_start);
end
initial begin
    $readmemh("fft_input.hex",inputs); $readmemh("fft_complex.hex",expected); $readmemh("fft_height.hex",heights);
    repeat(5) @(negedge clk); rst=0;
    for(block_index=0;block_index<8;block_index=block_index+1) begin
        writes=0;
        for(i=0;i<1024;i=i+1) begin
            @(negedge clk); audio_valid=1;
            audio_left={inputs[block_index*1024+i][31:16],8'hA5};
            audio_right={inputs[block_index*1024+i][15:0],8'h5A};
            @(negedge clk); audio_valid=0; audio_left=24'hbadbad; audio_right=24'hbadbad;
            if(block_index==0) repeat(519) @(negedge clk);
            else repeat(2) @(negedge clk);
        end
        wait(result_done); repeat(3) @(negedge clk);
        // Source keeps sending while FFT waits: frozen capture must not change.
        old_word=dut.capture_ram[0];
        audio_valid=1; audio_left=24'h123456; audio_right=24'habcdef;
        repeat(20) @(negedge clk); audio_valid=0;
        if(dut.capture_ram[0]!==old_word || dut.state!=19) $fatal(1,"Pending block overwritten");
        result_ack=1; @(negedge clk); result_ack=0;
        repeat(2) @(negedge clk);
        $display("PASS FFT stereo block %0d",block_index);
    end
    if(complex_checked!=16384 || height_checked!=2048) $fatal(1,"Missing checks");
    rst=1; repeat(3) @(negedge clk);
    if(spectrum_write || result_done || dut.state!=0) $fatal(1,"FFT reset failed");
    $display("ALL FFT1024 TESTS PASSED: 16384 complex bins, 2048 heights, 48K capture, bounded latency, backpressure/reset");
    $finish;
end
initial begin #150000000; $fatal(1,"FFT timeout"); end
endmodule
