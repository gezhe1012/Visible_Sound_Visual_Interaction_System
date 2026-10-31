`timescale 1ns/1ps
// Real exported BMP bytes, mixed with the five unmodified teaching headers.
module tb_nature_card;
reg clk=0,rst=1;always #5 clk=~clk;
reg scan_start=0,scan_intro=1,load_start=0,write_req_ack=0,write_ready=1;
reg [31:0] load_sector=0;
wire ready,scan_done,scan_found_valid,write_req,load_error,sd_sec_read,bmp_data_wr_en;
wire [31:0] scan_found_sector,sd_sec_read_addr,intro_wav_offset,intro_samples;
wire [1:0] intro_photo;
wire [2:0] scan_found_total;
wire [3:0] state_code;wire [23:0] bmp_data;
reg [7:0] sd_sec_read_data=0;reg sd_sec_read_data_valid=0,sd_sec_read_end=0;
byte unsigned p0[0:1690623],p1[0:1690623],p2[0:1690623],p3[0:1690623];
byte unsigned h0[0:511],h1[0:511],h2[0:511],h3[0:511],h4[0:511];
integer fp,n,k,address,found=0,page,pixels=0,cycle=0;
integer ibase[0:3]='{10000,33000,19000,2000};
integer tbase[0:4]='{10,6000,14000,24000,38000};
integer order[0:3]='{3,0,2,1};
reg checking=0;reg [23:0] expected;
reg corrupt_catalog=0;
bmp_bilinear_reader #(.INTRO_SUPPORT(1)) dut(.*,
    .scan_start_sector(32'd0),.scan_max_sector(32'd45000),.scan_target_count(scan_intro ? 3'd4 : 3'd5),
    .sd_init_done(1'b1),.bmp_width(16'd640),.bmp_height(16'd480));
function automatic [7:0] byte_at(input integer a);
    integer offset;
    begin
        byte_at=0;
        if(a>=ibase[0]*512 && a<ibase[0]*512+1690624) byte_at=p0[a-ibase[0]*512];
        if(a>=ibase[1]*512 && a<ibase[1]*512+1690624) byte_at=p1[a-ibase[1]*512];
        if(a>=ibase[2]*512 && a<ibase[2]*512+1690624) byte_at=p2[a-ibase[2]*512];
        if(a>=ibase[3]*512 && a<ibase[3]*512+1690624) byte_at=p3[a-ibase[3]*512];
        if(a>=tbase[0]*512 && a<tbase[0]*512+512) byte_at=h0[a-tbase[0]*512];
        if(a>=tbase[1]*512 && a<tbase[1]*512+512) byte_at=h1[a-tbase[1]*512];
        if(a>=tbase[2]*512 && a<tbase[2]*512+512) byte_at=h2[a-tbase[2]*512];
        if(a>=tbase[3]*512 && a<tbase[3]*512+512) byte_at=h3[a-tbase[3]*512];
        if(a>=tbase[4]*512 && a<tbase[4]*512+512) byte_at=h4[a-tbase[4]*512];
    end
endfunction
always @(posedge clk) begin
    cycle<=cycle+1;write_req_ack<=write_req;write_ready<=cycle%97<61;
    if(!rst && scan_found_valid) begin
        if(scan_intro) begin
            if(corrupt_catalog) begin
                if(intro_photo==2 || intro_photo==3 && found!=0 || intro_photo==0 && found!=1 || intro_photo==1 && found!=2)
                    $fatal(1,"Corrupt intro identity was accepted");
            end else if(found>=4 || intro_photo!=order[found] || scan_found_sector!=ibase[order[found]] ||
               intro_wav_offset!=1801 || intro_samples!=384000) $fatal(1,"Intro catalog/manifest mismatch");
        end else if(found>=5 || scan_found_sector!=tbase[found]) $fatal(1,"Intro assets changed teaching order");
        found=found+1;
    end
    if(!rst && load_error) $fatal(1,"Exported BMP rejected");
    if(checking && bmp_data_wr_en) begin
        expected={byte_at(ibase[page]*512+128+pixels*3+2),byte_at(ibase[page]*512+128+pixels*3+1),byte_at(ibase[page]*512+128+pixels*3)};
        if(pixels>=307200 || bmp_data!==expected) $fatal(1,"Intro pixel mismatch p%0d n%0d %h/%h",page,pixels,bmp_data,expected);
        pixels=pixels+1;
    end
end
initial forever begin
    @(negedge clk);
    if(sd_sec_read && !rst) begin
        address=sd_sec_read_addr;repeat(3) @(negedge clk);
        for(k=0;k<512;k=k+1) begin
            sd_sec_read_data=byte_at(address*512+k);sd_sec_read_data_valid=1;
            @(negedge clk);sd_sec_read_data_valid=0;
        end
        @(negedge clk);sd_sec_read_end=1;@(negedge clk);sd_sec_read_end=0;@(negedge clk);
    end
end
initial begin
    fp=$fopen("../output/nature_intro_tf/INTRO1.BMP","rb");n=$fread(p0,fp);$fclose(fp);if(n!=1690624)$fatal(1,"Missing exported photo 1");
    fp=$fopen("../output/nature_intro_tf/INTRO2.BMP","rb");n=$fread(p1,fp);$fclose(fp);if(n!=1690624)$fatal(1,"Missing exported photo 2");
    fp=$fopen("../output/nature_intro_tf/INTRO3.BMP","rb");n=$fread(p2,fp);$fclose(fp);if(n!=1690624)$fatal(1,"Missing exported photo 3");
    fp=$fopen("../output/nature_intro_tf/INTRO4.BMP","rb");n=$fread(p3,fp);$fclose(fp);if(n!=1690624)$fatal(1,"Missing exported photo 4");
    fp=$fopen("../doc/science_kiosk/bmp/01_pitch.bmp","rb");n=$fread(h0,fp);$fclose(fp);
    fp=$fopen("../doc/science_kiosk/bmp/02_level.bmp","rb");n=$fread(h1,fp);$fclose(fp);
    fp=$fopen("../doc/science_kiosk/bmp/03_timbre.bmp","rb");n=$fread(h2,fp);$fclose(fp);
    fp=$fopen("../doc/science_kiosk/bmp/04_stereo.bmp","rb");n=$fread(h3,fp);$fclose(fp);
    fp=$fopen("../doc/science_kiosk/bmp/05_melody.bmp","rb");n=$fread(h4,fp);$fclose(fp);
    repeat(5) @(negedge clk);rst=0;
    @(negedge clk);scan_start=1;@(negedge clk);scan_start=0;
    wait(scan_done);repeat(4) @(negedge clk);if(found!=4)$fatal(1,"Intro count mismatch");
    found=0;scan_intro=0;scan_start=1;@(negedge clk);scan_start=0;
    wait(!scan_done);wait(scan_done);repeat(4) @(negedge clk);if(found!=5)$fatal(1,"Teaching count mismatch");
    // Malformed new materials must not masquerade as an old teaching page.
    corrupt_catalog=1;p2[62]=7;scan_intro=1;found=0;scan_start=1;@(negedge clk);scan_start=0;
    wait(!scan_done);wait(scan_done);repeat(4) @(negedge clk);if(found!=3)$fatal(1,"Invalid intro ID not rejected");
    scan_intro=0;found=0;scan_start=1;@(negedge clk);scan_start=0;
    wait(!scan_done);wait(scan_done);repeat(4) @(negedge clk);if(found!=5)$fatal(1,"Corrupt intro polluted teaching catalog");
    p2[62]=2;corrupt_catalog=0;
    for(page=0;page<4;page=page+1) begin
        checking=1;pixels=0;load_sector=ibase[page];load_start=1;@(negedge clk);load_start=0;
        wait(!ready);wait(ready);repeat(4) @(negedge clk);checking=0;
        if(pixels!=307200)$fatal(1,"Incomplete intro photo");
        $display("PASS exported intro BMP %0d: 307200 unchanged pixels, offset=128, WAV tail skipped",page);
    end
    $display("ALL NATURE CARD TESTS PASSED: four actual BMP packages, manifest identity, original five-page order, 1228800 pixels");$finish;
end
initial begin #1800000000;$fatal(1,"Nature card timeout p%0d pixels%0d",page,pixels);end
endmodule
