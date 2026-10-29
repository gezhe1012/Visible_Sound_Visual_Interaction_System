`timescale 1ns/1ps
// Full six-page OSD comparison to f915d8c, except the explicitly replaced
// old logo rectangle. Golden RGB is compiled independently from supplied BMP.
module tb_logo_osd;
reg clk=0,rst=1,hs=1,vs=0,de=0;
always #20 clk=~clk;
reg [23:0] rgb_in=0,audio_left=0,audio_right=0;
reg audio_valid=0;
reg signed [8:0] brightness=0;
reg [2:0] contrast_q2=4,lesson_idx=0;
reg [1:0] active_control=0;
wire [23:0] rgb_out,baseline_rgb;
video_osd_overlay dut(.*);
voice_baseline_logo_osd baseline(.rgb_out(baseline_rgb),.*);
reg [23:0] logo[0:1487];
integer page,x,y,i,fp,pixels=0,outside_checked=0,cleared=0,badge_checked=0,icon_checked=0,changed=0;
reg [23:0] expected;
initial begin
    $readmemh("logo_expected.hex",logo);
    repeat(8) @(negedge clk);rst=0;
    for(page=0;page<6;page=page+1) begin
        @(negedge clk);de=0;vs=0;lesson_idx=page;brightness=page*16-32;contrast_q2=page%5+2;active_control=page%4;
        audio_valid=1;audio_left=page*400000;audio_right=-page*200000;
        repeat(8) @(negedge clk);vs=1;
        repeat(8) @(negedge clk);audio_valid=0;
        fp=$fopen($sformatf("logo_page_%0d.ppm",page),"wb");$fwrite(fp,"P6\n640 480\n255\n");
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk);de=1;
                rgb_in={8'(x+page*17),8'(y+page*11),8'(x^y^(page*43))};#2;
                if(dut.x!=x || dut.y!=y) $fatal(1,"Logo coordinate/framing mismatch");
                if(x>=18 && x<174 && y>=14 && y<50) begin
                    if(x<74) begin
                        expected=24'hFFFFFF;
                        if(x>=22 && x<70 && y>=16 && y<47) begin
                            expected=logo[(y-16)*48+x-22];icon_checked=icon_checked+1;
                        end
                        badge_checked=badge_checked+1;
                    end else begin expected=rgb_in;cleared=cleared+1;end
                    if(rgb_out!==expected) $fatal(1,"Supplied-logo RGB/mirror/removal mismatch page%0d %0d,%0d got%h expected%h",page,x,y,rgb_out,expected);
                    if(rgb_out!=baseline_rgb) changed=changed+1;
                end else begin
                    if(rgb_out!==baseline_rgb) $fatal(1,"Unrequested OSD change page%0d %0d,%0d",page,x,y);
                    outside_checked=outside_checked+1;
                end
                $fwrite(fp,"%c%c%c",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);pixels=pixels+1;
            end
            @(negedge clk);de=0;#2;
            if(rgb_out!==0) $fatal(1,"Blanking changed");
            repeat(4) @(negedge clk);
        end
        $fclose(fp);
    end
    if(pixels!=1843200 || outside_checked!=1809504 || cleared!=21600 || badge_checked!=12096 || icon_checked!=8928 || changed<20000)
        $fatal(1,"Logo coverage incomplete %0d %0d %0d %0d %0d %0d",pixels,outside_checked,cleared,badge_checked,icon_checked,changed);
    $display("ALL LOGO OSD TESTS PASSED: six pages, 1843200 pixels, 1809504 exact pixels outside replaced ROI vs f915d8c, 8928 BMP-derived icon pixels, 12096 white-badge pixels, 21600 old-text/blue-panel pixels restored, timer/BRI/CON/footer/blanking preserved");
    $finish;
end
initial begin #85000000;$fatal(1,"Logo six-page test timeout");end
endmodule
