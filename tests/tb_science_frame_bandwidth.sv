`timescale 1ns/1ps
module tb_science_frame_bandwidth;
localparam N=3072;
reg rst=1,mem_clk=0,write_clk=0,read_clk=0;
always #12.5 mem_clk=~mem_clk; // 40MHz SDRAM
always #5 write_clk=~write_clk; // 100MHz source, throttled to 10M pixels/s
always #20 read_clk=~read_clk; // 25MHz active video
reg Sdr_busy=0,Sdr_init_ref_vld=0;
wire App_rd_en,App_wr_en,write_ready,write_req_ack,write_finish,read_req_ack,read_finish;
wire [20:0] App_rd_addr,App_wr_addr;
wire [31:0] App_wr_din,read_data;
wire [3:0] App_wr_dm;
reg Sdr_rd_en=0;
reg [31:0] Sdr_rd_dout=0;
reg write_req=0,write_en=0,read_req=0,read_en=0;
reg [31:0] write_data=0;
reg [1:0] write_addr_index=0,read_addr_index=0;
frame_read_write #(.BURST_BITS(10),.FRAME_WIDTH(64),.FRAME_HEIGHT(48)) dut(
    .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
    .App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),.Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout),
    .read_clk(read_clk),.read_req(read_req),.read_req_ack(read_req_ack),.read_finish(read_finish),
    .read_addr_0(21'd0),.read_addr_1(21'(N)),.read_addr_2(21'd0),.read_addr_3(21'd0),
    .read_addr_index(read_addr_index),.read_len(21'(N)),.read_en(read_en),.read_data(read_data),
    .App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),.App_wr_din(App_wr_din),.App_wr_dm(App_wr_dm),
    .write_clk(write_clk),.write_req(write_req),.write_req_ack(write_req_ack),.write_ready(write_ready),.write_finish(write_finish),
    .write_addr_0(21'd0),.write_addr_1(21'(N)),.write_addr_2(21'd0),.write_addr_3(21'd0),
    .write_addr_index(write_addr_index),.write_len(21'(N)),.write_en(write_en),.write_data(write_data));
reg [31:0] memory[0:2*N-1];
reg [7:0] valid_pipe=0;
reg [20:0] address_pipe[0:7];
integer q,refresh_count=0,refresh_hold=0,refreshes=0,writes=0,reads=0;
function [31:0] pattern(input integer frame,index);
    pattern=(32'h5A000000 | (frame<<20) | index);
endfunction
always @(posedge mem_clk) begin
    if(rst) begin valid_pipe<=0; Sdr_rd_en<=0; end
    else begin
        if(Sdr_busy && (App_wr_en || App_rd_en)) $fatal(1,"Command launched during refresh");
        if(App_wr_en) begin
            if(App_wr_addr>=2*N) $fatal(1,"Write address out of range");
            memory[App_wr_addr]<=App_wr_din; writes=writes+1;
        end
        valid_pipe<={valid_pipe[6:0],App_rd_en}; address_pipe[0]<=App_rd_addr;
        for(q=1;q<8;q=q+1) address_pipe[q]<=address_pipe[q-1];
        Sdr_rd_en<=valid_pipe[7];
        if(valid_pipe[7]) Sdr_rd_dout<=memory[address_pipe[7]];
    end
end
always @(negedge mem_clk) begin
    if(!rst) begin
        if(refresh_hold>0) begin
            refresh_hold=refresh_hold-1;
            if(refresh_hold==0) begin Sdr_busy=0; Sdr_init_ref_vld=0; end
        end else begin
            refresh_count=refresh_count+1;
            if(refresh_count>=625 && !dut.O_wr_busy && !dut.O_rd_busy && valid_pipe==0) begin
                refresh_count=0; refresh_hold=20; refreshes=refreshes+1;
                Sdr_busy=1; Sdr_init_ref_vld=1;
            end
        end
    end
end
task write_frame(input integer frame);
    integer n;
    @(negedge write_clk); write_addr_index=2'(frame); write_req=1;
    wait(write_req_ack); @(negedge write_clk); write_req=0; wait(!write_req_ack);
    for(n=0;n<N;n=n+1) begin
        repeat(9) @(negedge write_clk);
        while(!write_ready) @(negedge write_clk);
        write_data=pattern(frame,n); write_en=1;
        @(negedge write_clk); write_en=0;
    end
    wait(write_finish); @(negedge write_clk);
endtask
task read_frame(input integer frame);
    integer x,y,index,source_index;
    @(negedge read_clk); read_addr_index=2'(frame); read_req=1;
    wait(read_req_ack); @(negedge read_clk); read_req=0; wait(!read_req_ack);
    repeat(400) @(negedge read_clk); // blanking/refill margin
    index=0;
    for(y=0;y<48;y=y+1) begin
        for(x=0;x<64;x=x+1) begin
            @(negedge read_clk); read_en=1;
            @(posedge read_clk);
            if(dut.read_buf.empty_flag) $fatal(1,"40MHz read FIFO underflow");
            #1; // Read FIFO is registered, not show-ahead (matches video_delay).
            source_index=(47-y)*64+x; // existing vertical flip policy
            if(read_data!==pattern(frame,source_index))
                $fatal(1,"40MHz underflow/data mismatch f%0d pixel%0d got%h expected%h empty%0b used%h rstate%0d wstate%0d refresh%0b",frame,index,read_data,pattern(frame,source_index),dut.read_buf.empty_flag,dut.wrusedw,dut.frame_fifo_read_m0.state,dut.frame_fifo_write_m0.state,Sdr_busy);
            index=index+1; reads=reads+1;
        end
        @(negedge read_clk); read_en=0; repeat(16) @(negedge read_clk);
    end
    wait(dut.frame_fifo_read_m0.state==0); // prefetched final words may still be draining
endtask
initial begin
    repeat(10) @(negedge write_clk); rst=0;
    write_frame(0);
    fork
        write_frame(1);
        read_frame(0);
    join
    read_frame(1);
    if(writes!=2*N || reads!=2*N || refreshes<2) $fatal(1,"Bandwidth test incomplete");
    $display("ALL FRAME BANDWIDTH TESTS PASSED: 40MHz memory / 25MHz video / 100MHz writer, 6144 ordered pixels and refresh arbitration");
    $finish;
end
initial begin #10000000; $fatal(1,"Bandwidth timeout writes%0d reads%0d state%0d req%0b ack%0b ready%0b used=%h wused=%h full%0b",writes,reads,dut.frame_fifo_write_m0.state,write_req,write_req_ack,write_ready,dut.rdusedw,dut.write_used_words,dut.write_fifo_full); end
endmodule
