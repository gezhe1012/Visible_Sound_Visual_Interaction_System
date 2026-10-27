`timescale 1ns/1ps
module tb_secondary_link;
reg clk=0,rst=1,lesson_valid=1,video_locked=0;
reg [2:0] lesson=0;
always #20 clk=~clk;
wire axis_user,axis_valid,axis_last;
wire [23:0] axis_data;
secondary_link_pattern dut(.*);
integer h=0,v=0,fr=0,x,y,pixels=0,lines=0,starts=0,bar_checks=0,cycles=0,last_start=-1;
integer fp=0;
reg [2:0] expected_lesson;
reg expected_valid,expected_lock;
reg [23:0] expected;
reg active;
reg [34:0] g_bits=35'b01111_10000_10000_10111_10001_10001_01111;
always @(posedge clk) if(!rst && fr<8) begin
    active=h>=160 && v>=45;x=h-160;y=v-45;
    if(h==0 && v==0) begin
        expected_lesson=lesson;expected_valid=lesson_valid;expected_lock=video_locked;
        fp=$fopen($sformatf("secondary_link_frame_%0d.ppm",fr),"wb");$fwrite(fp,"P6\n640 480\n255\n");
    end
    #1;
    if(axis_valid!==active || axis_last!==(active && h==799) || axis_user!==(h==160 && v==45))
        $fatal(1,"Secondary AXIS framing mismatch frame%0d h%0d v%0d",fr,h,v);
    if(dut.shown_lesson!==expected_lesson || dut.shown_valid!==expected_valid || dut.shown_locked!==expected_lock)
        $fatal(1,"Secondary metadata changed inside a frame");
    if(!active && axis_data!==0) $fatal(1,"Secondary blanking not black");
    if(active) begin
        pixels=pixels+1;
        if(axis_last) lines=lines+1;
        if(axis_user) begin
            starts=starts+1;
            if(last_start>=0 && cycles-last_start!=420000) $fatal(1,"Frame cadence changed");
            last_start=cycles;
        end
        if(x>=64 && x<576 && y>=160 && y<288) begin
            case((x-64)/64)
                0:expected=24'hE4F0F4;
                1:expected=24'hE9C477;
                2:expected=24'h5BDAC6;
                3:expected=24'h32AEB2;
                4:expected=24'h31778F;
                5:expected=24'h244B68;
                6:expected=24'h16364D;
                7:expected=24'h0A1B2D;
            endcase
            if(y%32==0) expected={1'b0,expected[23:17],1'b0,expected[15:9],1'b0,expected[7:1]};
            if(axis_data!==expected) $fatal(1,"Independent palette/grid mismatch at%0d,%0d",x,y);
            bar_checks=bar_checks+1;
        end
        if(y>=332 && y<344 && x==64+2*fr && axis_data!==24'h5BDAC6) $fatal(1,"Live cursor frozen or misaligned");
        if(x==592 && y==32 && axis_data!==(expected_lock ? 24'h5BDAC6 : 24'hE9C477)) $fatal(1,"Lock indicator wrong");
        if(expected_valid && x>=80 && x<90 && y>=400 && y<414)
            if(axis_data!==(g_bits[34-((y-400)/2)*5-(x-80)/2] ? 24'h5BDAC6 : 24'h102A3B)) $fatal(1,"PAGE glyph missing");
        if(x>=320 && x<336 && y>=304 && y<311 && axis_data!==24'h102A3B) $fatal(1,"Coordinate text wrapped");
        $fwrite(fp,"%c%c%c",axis_data[23:16],axis_data[15:8],axis_data[7:0]);
    end
    cycles=cycles+1;
    if(h==799) begin
        h=0;
        if(v==524) begin v=0;$fclose(fp);fr=fr+1;end
        else v=v+1;
    end else h=h+1;
end
initial begin
    repeat(5) @(negedge clk);rst=0;
    repeat(100000) @(negedge clk);lesson=1;video_locked=1;
    repeat(420000) @(negedge clk);lesson=2;
    repeat(420000) @(negedge clk);lesson=3;
    repeat(420000) @(negedge clk);lesson=4;
    repeat(420000) @(negedge clk);lesson_valid=0;
    repeat(420000) @(negedge clk);lesson=0;lesson_valid=1;
    wait(fr==8);@(negedge clk);
    if(pixels!=2457600 || lines!=3840 || starts!=8 || bar_checks!=524288) $fatal(1,"Missing raster coverage");
    rst=1;repeat(3) @(negedge clk);
    if(axis_valid || axis_user || axis_last || axis_data!=0 || dut.col!=0 || dut.line!=0 || dut.frame!=0) $fatal(1,"Reset failed");
    $display("ALL SECONDARY LINK TESTS PASSED: 8 complete 640x480 rasters, 2457600 pixels, 3840 TLAST, 8 SOF, 524288 reference palette pixels, 5 page states, frame-atomic changes, cursor, lock, reset");
    $finish;
end
initial begin #200000000;$fatal(1,"Secondary raster timeout");end
endmodule
