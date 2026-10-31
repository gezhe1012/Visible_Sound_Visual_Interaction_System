`timescale 1ns/1ps
module tb_nature_address;
reg clk=0,rst=1,frame_clear=0,enabled=1,request=0;
always #5 clk=~clk;
reg [1:0] photo_async=0;reg [5:0] slide_async=32;
wire mapped_request;wire [20:0] address;
nature_intro_address dut(.*);
integer expected[0:307202];
integer put=0,get=0,px,py,p,s,k,frames=0,burst_base=0;
function automatic integer reference(input integer x,y,photo,slide);
    integer left1,left2,top3,lx,ly,owner;
    begin
        left1=photo==1 ? -512+slide*16+(slide*3)/4 : 24;
        left2=photo==2 ? 640-slide*16-(slide*3)/4 : 104;
        left1=(left1>>>2)<<<2;left2=(left2>>>2)<<<2;
        top3=photo==3 ? -384+slide*12+slide/4 : 8;
        lx=x;ly=y;owner=0;
        if(photo>=1 && x>=left1 && x<left1+512 && y>=24 && y<408) begin lx=x-left1;ly=y-24;owner=1;end
        if(photo>=2 && x>=left2 && x<left2+512 && y>=40 && y<424) begin lx=x-left2;ly=y-40;owner=2;end
        if(photo>=3 && x>=64 && x<576 && y>=top3 && y<top3+384) begin lx=x-64;ly=y-top3;owner=3;end
        reference=owner*307200+ly*640+lx;
    end
endfunction
always @(negedge clk) if(!rst && mapped_request) begin
    if(get>=put || address!==expected[get]) $fatal(1,"Address/pipeline mismatch p%0d s%0d n%0d got%0d expected%0d",p,s,get,address,expected[get]);
    if(address>=1228800) $fatal(1,"SDRAM address escaped reserved four frames");
    if(get%4==0) begin
        if(address%4!=0) $fatal(1,"Unaligned SDRAM burst start");burst_base=address;
    end else if(address!=burst_base+get%4) $fatal(1,"Layer address breaks vendor BL4 contract");
    get=get+1;
end
initial begin
    repeat(4) @(negedge clk);rst=0;
    for(p=0;p<4;p=p+1) for(s=0;s<=32;s=s+1) begin
        photo_async=p;slide_async=s;frame_clear=1;request=0;
        repeat(6) @(posedge clk);@(negedge clk);frame_clear=0;put=0;get=0;
        for(py=0;py<480;py=py+1) for(px=0;px<640;px=px+1) begin
            // Exercise stalls, bank edges, scaling repeats and complete frames.
            if((px+py)%19==0) begin request=0;@(negedge clk);end
            request=1;expected[put]=reference(px,py,p,s);put=put+1;@(negedge clk);
        end
        request=0;repeat(6) @(negedge clk);
        if(get!=307200) $fatal(1,"Lost request in mapper");frames=frames+1;
    end
    $display("ALL NATURE ADDRESS TESTS PASSED: %0d full frames with stalls, all four layers, every slide position, aligned BL4 groups",frames);
    $finish;
end
initial begin #500000000;$fatal(1,"Address mapper timeout");end
endmodule
