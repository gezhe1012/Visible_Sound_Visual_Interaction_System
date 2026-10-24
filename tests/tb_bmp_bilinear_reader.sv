`timescale 1ns/1ps
module tb_bmp_bilinear_reader;
reg clk=0;
always #5 clk=~clk;
reg rst=1, scan_start=0, load_start=0;
reg [31:0] scan_start_sector=0, scan_max_sector=8, load_sector=8;
reg [2:0] scan_target_count=1;
wire ready,scan_done,scan_found_valid,write_req,sd_sec_read,bmp_data_wr_en,load_error;
wire [31:0] scan_found_sector,sd_sec_read_addr;
wire [2:0] scan_found_total;
wire [3:0] state_code;
wire [23:0] bmp_data;
reg write_req_ack=0,write_ready=0;
reg [7:0] sd_sec_read_data=0;
reg sd_sec_read_data_valid=0, sd_sec_read_end=0;
integer cycle=0, pixels=0, sw, sh, offset, stride, file_size;
integer x,y,c,j,expected, actual, channel, xx,yy,x0,x1,y0,y1,wx,wy,h0,h1;
integer cases_passed=0, found=0, errors_seen=0, request_address, k;
reg checking=0;
reg [7:0] card[0:2097151];
localparam BASE=4096;

bmp_bilinear_reader dut(.*,
    .sd_init_done(1'b1),.bmp_width(16'd640),.bmp_height(16'd480));

function integer source_channel(input integer px,py,ch);
    case(ch)
        0: source_channel=(px*3+py*5+17)&255;
        1: source_channel=(px*7+py*11+43)&255;
        2: source_channel=(px*13+py*19+91)&255;
    endcase
endfunction
function integer blend(input integer a,b,t);
    blend=(a*(256-t)+b*t+128)>>8;
endfunction
task put32(input integer at,value);
    for(integer n=0;n<4;n=n+1) card[BASE+at+n]=(value>>(8*n))&255;
endtask
task make_bmp(input integer w,h,pixel_at);
    sw=w; sh=h; offset=pixel_at;
    stride=(w*3+3)&~3; file_size=pixel_at+stride*((h<0)?-h:h);
    for(integer a=0;a<BASE+file_size+512;a=a+1) card[a]=0;
    card[BASE]="B"; card[BASE+1]="M";
    put32(2,file_size); put32(10,pixel_at); put32(14,40);
    put32(18,w); put32(22,h);
    card[BASE+26]=1; card[BASE+28]=24;
    for(integer sy=0;sy<((h<0)?-h:h);sy=sy+1)
        for(integer sx=0;sx<w;sx=sx+1)
            for(integer sc=0;sc<3;sc=sc+1)
                // Source function y=0 is the bottom of the image.
                card[BASE+pixel_at+sy*stride+sx*3+sc]=
                    source_channel(sx,(h<0)?(-h-1-sy):sy,sc);
endtask
task reset_dut;
    @(negedge clk); rst=1; checking=0;
    repeat(5) @(negedge clk);
    rst=0;
    repeat(5) @(negedge clk);
endtask
task run_image(input integer w,h,at);
    if(cases_passed==0) reset_dut();
    make_bmp(w,h,at); pixels=0; checking=1;
    @(negedge clk); load_start=1;
    @(negedge clk); load_start=0;
    wait(!ready); wait(ready);
    repeat(5) @(negedge clk);
    checking=0;
    if(pixels!=307200) $fatal(1,"Output size %0d instead of 307200 (%0dx%0d)",pixels,w,h);
    cases_passed=cases_passed+1;
    $display("PASS %0dx%0d offset=%0d: all 307200 pixels, bilinear oracle and backpressure",w,h,at);
endtask

always @(posedge clk) begin
    cycle<=cycle+1;
    write_req_ack<=write_req;
    // Long stalls as well as short periodic stalls exercise the ready interface.
    write_ready<=!rst && (cycle%97<61) && (cycle%100003<97000);
    if(scan_found_valid) begin
        if(scan_found_sector!=8) $fatal(1,"Scan returned wrong sector");
        found=found+1;
    end
    if(load_error) errors_seen=errors_seen+1;
    if(checking && bmp_data_wr_en) begin
        xx=pixels%640; yy=pixels/640;
        x0=(xx*(sw-1))/639; wx=((xx*(sw-1))%639)*256/639;
        y0=(yy*(((sh<0)?-sh:sh)-1))/479;
        wy=((yy*(((sh<0)?-sh:sh)-1))%479)*256/479;
        x1=(x0<sw-1)?x0+1:x0;
        y1=(y0<((sh<0)?-sh:sh)-1)?y0+1:y0;
        for(channel=0;channel<3;channel=channel+1) begin
            h0=blend(source_channel(x0,y0,channel),source_channel(x1,y0,channel),wx);
            h1=blend(source_channel(x0,y1,channel),source_channel(x1,y1,channel),wx);
            expected=blend(h0,h1,wy); actual=(bmp_data>>(8*channel))&255;
            if(actual!==expected) $fatal(1,"Pixel %0d (%0d,%0d) ch%0d got%0d expected%0d",pixels,xx,yy,channel,actual,expected);
        end
        pixels=pixels+1;
    end
end

// CMD17 behavioral sector server: captures the address, adds latency and
// byte-valid gaps, and never returns data beyond the generated card image.
initial forever begin
    @(negedge clk);
    if(sd_sec_read && !rst) begin
        request_address=sd_sec_read_addr;
        repeat(3) @(negedge clk);
        for(k=0;k<512;k=k+1) begin
            sd_sec_read_data=card[request_address*512+k];
            sd_sec_read_data_valid=1;
            @(negedge clk);
            sd_sec_read_data_valid=0;
            if(k%13==0) @(negedge clk);
        end
        @(negedge clk); sd_sec_read_end=1;
        @(negedge clk); sd_sec_read_end=0;
        @(negedge clk);
    end
end

initial begin
    run_image(1,1,54);
    run_image(2,3,54);
    run_image(321,241,1022); // padding and pixel BGR split across sectors
    run_image(640,480,54);  // pixel-exact pass-through
    run_image(800,600,122); // downscale, extended header offset
    run_image(480,-800,70); // portrait, top-down
    run_image(2048,2,54);  // maximum row length
    run_image(2,2048,54);  // maximum source height
    reset_dut(); make_bmp(321,241,54); found=0;
    @(negedge clk); scan_start=1;
    @(negedge clk); scan_start=0;
    wait(scan_done); repeat(3) @(negedge clk);
    if(found!=1 || scan_found_total!=1) $fatal(1,"Scan did not find variable-resolution BMP");
    $display("PASS variable-resolution sector scan");
    // Reject unsupported/truncated headers before any write request.
    for(j=0;j<5;j=j+1) begin
        reset_dut(); make_bmp(7,5,54); errors_seen=0;
        case(j)
            0: put32(30,1); // compression
            1: put32(22,0);
            2: put32(18,2049);
            3: put32(2,55); // truncated pixels
            4: card[BASE+28]=32;
        endcase
        @(negedge clk); load_start=1;
        @(negedge clk); load_start=0;
        wait(!ready); wait(ready); repeat(3) @(negedge clk);
        if(errors_seen!=1 || write_req) $fatal(1,"Invalid header was not rejected, case%0d",j);
    end
    $display("PASS 5 invalid header cases");
    $display("ALL SCALER TESTS PASSED (%0d complete frames)",cases_passed);
    $finish;
end
initial begin #2000000000; $fatal(1,"Testbench timeout state=%0d pixels=%0d",dut.state,pixels); end
endmodule
