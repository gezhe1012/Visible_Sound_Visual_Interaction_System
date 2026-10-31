`timescale 1ns/1ps
// Vendor controller + command-level single-data-rate memory model. This checks
// address acceptance, not electrical setup/hold or a physical board.
module tb_nature_sdram_contract;
reg clk=0,rst=1;always #12.5 clk=~clk;
wire mclk,cke,ras,cas,we;wire [1:0] bank;wire [10:0] ma;wire [3:0] dm;tri [31:0] dq;
wire initialized,refresh,busy,valid;wire [31:0] data;
reg write_en=0,read_en=0;reg [20:0] wa=0,ra=0;reg [31:0] wd=0;
sdram dut(.Clk(clk),.Clk_sft(~clk),.Rst(rst),.Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
    .App_wr_en(write_en),.App_wr_addr(wa),.App_wr_dm(4'd0),.App_wr_din(wd),
    .App_rd_en(read_en),.App_rd_addr(ra),.Sdr_rd_en(valid),.Sdr_rd_dout(data),
    .SDRAM_CLK(mclk),.SDR_CKE(cke),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(bank),.SDR_ADDR(ma),.SDR_DM(dm),.SDR_DQ(dq));
reg [31:0] memory[0:2097151];reg [10:0] open_row[0:3];
reg [31:0] read_data[0:3];reg [3:0] read_valid=0;
reg [31:0] dq_value=0;reg dq_enable=0;
integer cl=2,bl=1,idx,j,writes=0,reads=0,put=0,get=0,b,n,mode,mismatches=0;
integer write_left=0,read_left=0,write_base=0,read_base=0,write_col=0,read_col=0;
integer requests[0:1023];
assign dq=dq_enable ? dq_value : 32'bz;
always @(posedge mclk) if(!rst && cke) begin
    read_valid<={read_valid[2:0],1'b0};
    for(j=1;j<4;j=j+1) read_data[j]<=read_data[j-1];
    // SDRAM CAS count includes the command edge; sample on the opposite
    // half-cycle, matching the vendor controller's 180-degree SDRAM clock.
    dq_enable<=read_valid[cl-2];dq_value<=read_data[cl-2];
    if(write_left>0) begin
        memory[write_base+(write_col&(bl-1))]<=dq;
        write_col=write_col+1;write_left=write_left-1;writes=writes+1;
    end
    if(read_left>0) begin
        read_data[0]<=memory[read_base+(read_col&(bl-1))];read_valid[0]<=1;
        read_col=read_col+1;read_left=read_left-1;reads=reads+1;
    end
    if({ras,cas,we}==3'b000) begin
        cl=ma[6:4];bl=1<<ma[2:0];$display("SDRAM mode: CAS=%0d burst=%0d",cl,bl);
    end
    if({ras,cas,we}==3'b011) open_row[bank]<=ma;
    if({ras,cas,we}==3'b100) begin
        idx=(open_row[bank]*4+bank)*256+ma[7:0];
        if(writes<8) $display("WRITE idx=%0d data=%h t=%t",idx,dq,$time);
        memory[idx]<=dq;writes=writes+1;
        write_base=idx&~(bl-1);write_col=(idx&(bl-1))+1;write_left=bl-1;
    end
    if({ras,cas,we}==3'b101) begin
        idx=(open_row[bank]*4+bank)*256+ma[7:0];
        if(reads<8) $display("READ idx=%0d data=%h t=%t",idx,memory[idx],$time);
        read_data[0]<=memory[idx];read_valid[0]<=1;reads=reads+1;
        read_base=idx&~(bl-1);read_col=(idx&(bl-1))+1;read_left=bl-1;
    end
end
always @(posedge clk) if(!rst && valid) begin
    if(get>=put) $fatal(1,"Unexpected SDRAM valid");
    if(data!==32'h5a000000+requests[get]) begin
        if(mode<3) $fatal(1,"SDRAM controller/address contract mismatch mode%0d n%0d got%h expected%h",mode,get,data,32'h5a000000+requests[get]);
        else mismatches=mismatches+1;
    end
    get=get+1;
end
initial begin
    repeat(8) @(negedge clk);rst=0;wait(initialized);repeat(20) @(negedge clk);
    for(b=0;b<4;b=b+1) begin
        wait(!busy);@(negedge clk);
        for(n=0;n<128;n=n+1) begin
            write_en=1;wa=b*307200+n;wd=32'h5a000000+wa;@(negedge clk);
        end
        write_en=0;repeat(32) @(negedge clk);
    end
    // Baseline contiguous stream, then scaling repeats and cross-frame jumps.
    for(mode=0;mode<4;mode=mode+1) begin
        wait(!busy);@(negedge clk);
        for(n=0;n<64;n=n+1) begin
            case(mode)
                0:ra=n;
                1:ra=n<32 ? n : n+307200;
                2:ra=((n/4)%4)*307200+(n/16)*4+(n%4);
                3:ra=n*5/4; // deliberately unsupported naive pixel-address scaling
            endcase
            requests[put]=ra;put=put+1;read_en=1;@(negedge clk);
        end
        read_en=0;repeat(32) @(negedge clk);
        if(get!=put) $fatal(1,"Vendor controller lost accepted requests");
    end
    if(mismatches==0) $fatal(1,"Negative control did not detect unsupported unaligned resampling");
    $display("ALL NATURE SDRAM CONTRACT TESTS PASSED: vendor encrypted controller, %0d writes, %0d reads; aligned layer jumps; negative control detects %0d unsafe resampling addresses",writes,reads,mismatches);$finish;
end
initial begin #5000000;$fatal(1,"SDRAM contract timeout");end
endmodule
