`timescale 1ns/1ps
// Control-plane regression with a controllable source and SD-init stub.
// Pixel arithmetic is covered independently by tb_bmp_bilinear_reader.
module tb_sd_card_commit;
reg clk=0, rst=1, key_next=1, key_auto=1;
always #5 clk=~clk;
reg write_finish_toggle=0, transition_done_toggle=0;
wire [3:0] state_code;
wire [1:0] write_buf_idx,disp_buf_idx,transition_buf_idx;
wire display_valid,transition_start_toggle,write_req,write_en;
wire [31:0] write_data;
wire SD_nCS,SD_DCLK,SD_MOSI;
reg write_req_ack=0;
integer cycle=0,loads=0,load_at=-1,commits=0,transition_at=-1;
reg transition_seen=0;
sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(.*,
    .bmp_width(16'd640),.bmp_height(16'd480),.write_ready(1'b1),.SD_MISO(1'b1));
always @(posedge clk) begin
    cycle<=cycle+1;
    write_req_ack<=write_req;
    if(!rst && dut.load_start_pulse) begin
        loads=loads+1; load_at=cycle;
    end
    if(load_at>=0) begin
        // First frame: SDRAM completion arrives before source-ready.
        // Second frame: SDRAM completion arrives after source-ready.
        if((loads==1 && cycle==load_at+12) || (loads==2 && cycle==load_at+55))
            write_finish_toggle<=~write_finish_toggle;
    end
    if(transition_start_toggle!=transition_seen) begin
        transition_seen=transition_start_toggle;
        commits=commits+1;
        if(!dut.bmp_ready) $fatal(1,"Transition before source completed");
        if(loads==1 && cycle<load_at+30) $fatal(1,"Early commit of first frame");
        if(loads==2 && cycle<load_at+55) $fatal(1,"Commit before memory completion");
        transition_at=cycle;
    end
    if(transition_at>=0 && cycle==transition_at+25)
        transition_done_toggle<=~transition_done_toggle;
end
task press_next;
    @(negedge clk); key_next=0;
    repeat(30) @(negedge clk);
    key_next=1;
    repeat(30) @(negedge clk);
endtask
initial begin
    repeat(6) @(negedge clk); rst=0;
    wait(display_valid && !dut.transition_pending);
    if(disp_buf_idx!=0 || commits!=1) $fatal(1,"First commit failed");
    press_next();
    wait(loads==2); wait(!dut.load_busy && !dut.transition_pending);
    if(disp_buf_idx!=1 || commits!=2) $fatal(1,"Second commit failed");
    press_next();
    wait(loads==3); repeat(60) @(negedge clk);
    if(dut.load_busy || commits!=2 || disp_buf_idx!=1 || !display_valid)
        $fatal(1,"Rejected source changed committed frame or deadlocked");
    $display("ALL COMMIT TESTS PASSED: early/late write_finish, transition ack, rejected source");
    $finish;
end
initial begin #100000; $fatal(1,"Controller timeout loads=%0d commits=%0d",loads,commits); end
endmodule

module bmp_bilinear_reader(
    input clk,rst, output reg ready,
    input scan_start,input [31:0] scan_start_sector,scan_max_sector,
    input [2:0] scan_target_count,
    output reg scan_done,scan_found_valid,output reg [31:0] scan_found_sector,
    output reg [2:0] scan_found_total,
    input load_start,input [31:0] load_sector,input sd_init_done,
    output [3:0] state_code,input [15:0] bmp_width,bmp_height,
    output write_req,input write_req_ack,write_ready,output reg load_error,
    output sd_sec_read,output [31:0] sd_sec_read_addr,input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid,sd_sec_read_end,
    output bmp_data_wr_en,output [23:0] bmp_data
);
integer scan_age=-1,load_age=-1,count=0;
assign write_req=load_age>=0 && load_age<5;
assign state_code=0;
assign sd_sec_read=0;
assign sd_sec_read_addr=0;
assign bmp_data_wr_en=0;
assign bmp_data=0;
always @(posedge clk) begin
    if(rst) begin
        ready<=1; scan_done<=0; scan_found_valid<=0; scan_found_sector<=0;
        scan_found_total<=0; load_error<=0; scan_age=-1; load_age=-1; count=0;
    end else begin
        scan_found_valid<=0; load_error<=0;
        if(scan_start) begin ready<=0; scan_age=0; end
        if(scan_age>=0) begin
            scan_age=scan_age+1;
            if(scan_age==2 || scan_age==4) begin
                scan_found_valid<=1; scan_found_sector<=scan_age*32'd100;
                scan_found_total<=scan_found_total+3'd1;
            end
            if(scan_age==8) begin ready<=1; scan_done<=1; scan_age=-1; end
        end
        if(load_start) begin ready<=0; load_age=0; count=count+1; end
        if(load_age>=0) begin
            load_age=load_age+1;
            if(load_age==30) begin
                ready<=1; load_age=-1;
                if(count==3) load_error<=1;
            end
        end
    end
end
endmodule

module sd_card_top(
    input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
    output sd_init_done,input sd_sec_read,input [31:0] sd_sec_read_addr,
    output [7:0] sd_sec_read_data,output sd_sec_read_data_valid,sd_sec_read_end,
    input sd_sec_write,input [31:0] sd_sec_write_addr,
    input [7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end
);
assign sd_init_done=!rst;
assign SD_nCS=1; assign SD_DCLK=0; assign SD_MOSI=0;
assign sd_sec_read_data=0; assign sd_sec_read_data_valid=0; assign sd_sec_read_end=0;
assign sd_sec_write_data_req=0; assign sd_sec_write_end=0;
endmodule
