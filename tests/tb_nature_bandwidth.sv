`timescale 1ns/1ps
module tb_nature_bandwidth;
reg rst=1,mem_clk=0,read_clk=0,write_clk=0;
always #12.5 mem_clk=~mem_clk;always #20 read_clk=~read_clk;always #5 write_clk=~write_clk;
reg intro_active=1;reg [1:0] intro_photo=0;reg [5:0] intro_slide=32;
reg read_req=0,read_en=0,Sdr_busy=0,Sdr_init_ref_vld=0,Sdr_rd_en=0;
reg [31:0] Sdr_rd_dout=0;
wire App_rd_en,App_wr_en,read_req_ack,read_finish;
wire [20:0] App_rd_addr,App_wr_addr;
wire [31:0] read_data;
frame_read_write #(.INTRO_SUPPORT(1)) dut(
    .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
    .intro_active(intro_active),.intro_photo(intro_photo),.intro_slide(intro_slide),
    .App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),.Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout),
    .read_clk(read_clk),.read_req(read_req),.read_req_ack(read_req_ack),.read_finish(read_finish),
    .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd614400),.read_addr_3(21'd921600),
    .read_addr_index(2'd0),.read_len(21'd307200),.read_en(read_en),.read_data(read_data),
    .App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),.App_wr_din(),.App_wr_dm(),
    .write_clk(write_clk),.write_req(1'b0),.write_req_ack(),.write_ready(),.write_finish(),
    .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd614400),.write_addr_3(21'd921600),
    .write_addr_index(2'd0),.write_len(21'd307200),.write_en(1'b0),.write_data(32'd0));
reg [7:0] valid_pipe=0;
reg [20:0] address_pipe[0:7];
integer q,refresh_count=0,refresh_hold=0,refreshes=0,p,x,y,reads=0,expected,lx,ly,owner;
always @(posedge mem_clk) begin
    if(rst) begin valid_pipe<=0;Sdr_rd_en<=0;end
    else begin
        if(App_wr_en || (Sdr_busy && App_rd_en)) $fatal(1,"Memory arbitration/refresh collision");
        valid_pipe<={valid_pipe[6:0],App_rd_en};address_pipe[0]<=App_rd_addr;
        for(q=1;q<8;q=q+1) address_pipe[q]<=address_pipe[q-1];
        Sdr_rd_en<=valid_pipe[7];if(valid_pipe[7]) Sdr_rd_dout<={11'd0,address_pipe[7]};
    end
end
always @(negedge mem_clk) if(!rst) begin
    if(refresh_hold>0) begin
        refresh_hold=refresh_hold-1;if(refresh_hold==0) begin Sdr_busy=0;Sdr_init_ref_vld=0;end
    end else begin
        refresh_count=refresh_count+1;
        if(refresh_count>=625 && !dut.O_rd_busy && valid_pipe==0) begin
            refresh_count=0;refresh_hold=20;refreshes=refreshes+1;Sdr_busy=1;Sdr_init_ref_vld=1;
        end
    end
end
initial begin
    repeat(10) @(negedge read_clk);rst=0;
    for(p=0;p<5;p=p+1) begin
        intro_photo=p;intro_active=p<4;read_req=1;
        wait(read_req_ack);@(negedge read_clk);read_req=0;wait(!read_req_ack);
        repeat(400) @(negedge read_clk);
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge read_clk);read_en=1;
                lx=x;ly=y;owner=0;
                if(p<4) begin
                    if(p>=1 && x>=24 && x<536 && y>=24 && y<408) begin lx=x-24;ly=y-24;owner=1;end
                    if(p>=2 && x>=104 && x<616 && y>=40 && y<424) begin lx=x-104;ly=y-40;owner=2;end
                    if(p>=3 && x>=64 && x<576 && y>=8 && y<392) begin lx=x-64;ly=y-8;owner=3;end
                end
                expected=owner*307200+ly*640+lx;
                @(posedge read_clk);
                if(dut.read_buf.empty_flag) $fatal(1,"Intro FIFO underflow p%0d x%0d y%0d",p,x,y);
                #1;if(read_data!==expected) $fatal(1,"Intro FIFO/order mismatch p%0d x%0d y%0d got%0d expected%0d",p,x,y,read_data,expected);
                reads=reads+1;
            end
            @(negedge read_clk);read_en=0;repeat(160) @(negedge read_clk);
        end
        wait(dut.frame_fifo_read_m0.state==0);
    end
    $display("ALL NATURE BANDWIDTH TESTS PASSED: %0d ordered pixels, 40/25MHz, %0d refreshes, all four banks and legacy bypass",reads,refreshes);$finish;
end
initial begin #100000000;$fatal(1,"Nature bandwidth timeout");end
endmodule
