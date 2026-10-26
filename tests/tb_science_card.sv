`timescale 1ns/1ps
module tb_science_card;
reg clk=0,rst=1;
always #5 clk=~clk;
wire ready,scan_done,scan_found_valid,write_req,load_error,sd_sec_read,bmp_data_wr_en;
wire [31:0] scan_found_sector,sd_sec_read_addr;
wire [2:0] scan_found_total;
wire [3:0] state_code;
wire [23:0] bmp_data;
reg scan_start=0,load_start=0,write_req_ack=0,write_ready=1;
reg [31:0] load_sector=0;
reg [7:0] sd_sec_read_data=0;
reg sd_sec_read_data_valid=0,sd_sec_read_end=0;
byte unsigned card[0:12582911];
reg [23:0] expected[0:307199];
integer fp,bytes_read,found=0,page,pixels=0,k,cycle=0;
integer sectors[0:4]='{4067,5868,8681,13290,20491};
integer request_address;
reg checking=0;
bmp_bilinear_reader dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(scan_start),
    .scan_start_sector(32'd0),.scan_max_sector(32'd131071),.scan_target_count(3'd5),
    .scan_done(scan_done),.scan_found_valid(scan_found_valid),.scan_found_sector(scan_found_sector),.scan_found_total(scan_found_total),
    .load_start(load_start),.load_sector(load_sector),.sd_init_done(1'b1),.state_code(state_code),
    .bmp_width(16'd640),.bmp_height(16'd480),.write_req(write_req),.write_req_ack(write_req_ack),.write_ready(write_ready),
    .load_error(load_error),.sd_sec_read(sd_sec_read),.sd_sec_read_addr(sd_sec_read_addr),
    .sd_sec_read_data(sd_sec_read_data),.sd_sec_read_data_valid(sd_sec_read_data_valid),.sd_sec_read_end(sd_sec_read_end),
    .bmp_data_wr_en(bmp_data_wr_en),.bmp_data(bmp_data));
always @(posedge clk) begin
    cycle<=cycle+1; write_req_ack<=write_req;
    write_ready<=cycle%97<61;
    if(!rst && scan_found_valid) begin
        if(found>=5 || scan_found_sector!=sectors[found]) $fatal(1,"Card scan order incorrect");
        found=found+1;
    end
    if(!rst && load_error) $fatal(1,"Actual teaching BMP rejected");
    if(checking && bmp_data_wr_en) begin
        if(pixels>=307200 || bmp_data!==expected[pixels])
            $fatal(1,"Card page%0d pixel%0d mismatch %h/%h",page,pixels,bmp_data,expected[pixels]);
        pixels=pixels+1;
    end
end
initial forever begin
    @(negedge clk);
    if(sd_sec_read && !rst) begin
        request_address=sd_sec_read_addr;
        if(request_address*512+511>12582911) $fatal(1,"Read outside test card window");
        repeat(3) @(negedge clk);
        for(k=0;k<512;k=k+1) begin
            sd_sec_read_data=card[request_address*512+k]; sd_sec_read_data_valid=1;
            @(negedge clk); sd_sec_read_data_valid=0;
            if(k%13==0) @(negedge clk);
        end
        @(negedge clk); sd_sec_read_end=1;
        @(negedge clk); sd_sec_read_end=0;
        @(negedge clk);
    end
end
initial begin
    fp=$fopen("../doc/science_kiosk/science_tf_64MiB.img","rb");
    if(!fp) $fatal(1,"Generate science assets first");
    bytes_read=$fread(card,fp); $fclose(fp);
    if(bytes_read!=12582912) $fatal(1,"Card image too short");
    repeat(5) @(negedge clk); rst=0;
    @(negedge clk); scan_start=1; @(negedge clk); scan_start=0;
    wait(scan_done); repeat(5) @(negedge clk);
    if(found!=5 || scan_found_total!=5) $fatal(1,"Did not scan five teaching files");
    for(page=0;page<5;page=page+1) begin
        $readmemh($sformatf("science_image_%0d.hex",page),expected);
        pixels=0; checking=1; load_sector=sectors[page];
        @(negedge clk); load_start=1; @(negedge clk); load_start=0;
        wait(!ready); wait(ready); repeat(5) @(negedge clk); checking=0;
        if(pixels!=307200) $fatal(1,"Incomplete card frame");
        $display("PASS actual teaching BMP %0d: 307200 bilinear pixels with backpressure",page);
    end
    $display("ALL SCIENCE CARD TESTS PASSED: real FAT32 five-page scan order and 1536000 teaching RGB pixels");
    $finish;
end
initial begin #1800000000; $fatal(1,"Actual card timeout page%0d pixel%0d",page,pixels); end
endmodule
