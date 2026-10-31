`timescale 1ns/1ps
module tb_nature_loader;
reg clk=0,rst=1,initialized=0,reader_ready=1,load_error=0;
always #5 clk=~clk;
reg scan_done=0,found_valid=0;
reg [31:0] found_sector=0,wav_offset=1801,samples=384000;
reg [1:0] found_photo=0;
reg write_finish_toggle=0,exit_async=0,autoplay_async=0,wav_idle=1;
wire owner,assets_ready,scan_start,load_start,initial_auto;
wire [31:0] load_sector,wav0,wav1,wav2,wav3,count0,count1,count2,count3;
wire [1:0] write_bank;
nature_intro_loader #(.ENABLE(1)) dut(.*);
task cycles(input integer n);repeat(n) @(negedge clk);endtask
integer i;
initial begin
    cycles(4);rst=0;initialized=1;wait(scan_start);cycles(3);
    // Out-of-order discovery must still produce the requested photo sequence.
    for(i=3;i>=0;i=i-1) begin
        found_photo=i;found_sector=1000+i*4000;found_valid=1;cycles(1);found_valid=0;cycles(2);
    end
    scan_done=1;
    for(i=0;i<4;i=i+1) begin
        wait(load_start);cycles(1);
        if(write_bank!=i || load_sector!=1000+i*4000) $fatal(1,"Photo identity/bank mapping failed");
        reader_ready=0;cycles(5);
        if(i%2==0) begin write_finish_toggle=~write_finish_toggle;cycles(8);reader_ready=1;end
        else begin reader_ready=1;cycles(8);if(assets_ready) $fatal(1,"Ready before SDRAM drained");write_finish_toggle=~write_finish_toggle;end
    end
    wait(assets_ready);cycles(3);
    if(!owner || wav3!=14801 || count3!=384000) $fatal(1,"Manifest/audio binding failed");
    wav_idle=0;autoplay_async=1;exit_async=1;cycles(10);
    if(!owner) $fatal(1,"Ownership released with SD sector still active");
    wav_idle=1;wait(!owner);cycles(2);
    if(!initial_auto || assets_ready) $fatal(1,"Autoplay state handoff failed");
    // An old TF card without intro materials falls back to teaching, not a hang.
    rst=1;cycles(3);rst=0;scan_done=0;exit_async=0;wait(scan_start);cycles(4);scan_done=1;
    wait(!owner);if(assets_ready) $fatal(1,"Missing assets marked valid");
    $display("ALL NATURE LOADER TESTS PASSED: four bank preload, out-of-order IDs, source/memory completion, bus handoff, old-card fallback");
    $finish;
end
initial begin #100000;$fatal(1,"Loader timeout");end
endmodule
