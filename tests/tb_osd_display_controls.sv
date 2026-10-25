`timescale 1ns/1ps
module tb_osd_display_controls;
reg clk=0,rst=1,hs=1,vs=0,de=0;
always #5 clk=~clk;
reg [23:0] rgb_in=24'h808080;
reg signed [8:0] brightness=0;
reg [2:0] contrast_q2=4;
reg [1:0] active_control=0;
wire [23:0] rgb_out;
integer b,c,i,x,y,fp,cleared_pixels=0;
string text_expected;
video_osd_overlay dut(.*);
initial begin
    repeat(4) @(negedge clk); rst=0;
    for(b=-64;b<=64;b=b+16)
        for(c=2;c<=6;c=c+1) begin
            brightness=b; contrast_q2=c; #1;
            text_expected=$sformatf("BRI:%s%1d%1d CON:%1d%1d%1d%%",(b<0)?"-":"+",
                ((b<0)?-b:b)/10,((b<0)?-b:b)%10,(c*25)/100,((c*25)/10)%10,(c*25)%10);
            for(i=0;i<16;i=i+1)
                if(dut.parameter_char(i)!==text_expected[i])
                    $fatal(1,"OSD parameter text mismatch %s char%0d",text_expected,i);
        end
    @(negedge clk); brightness=-64; contrast_q2=2; active_control=1; vs=1;
    repeat(4) @(negedge clk);
    fp=$fopen("extension4_osd_preview.ppm","wb");
    if(!fp) $fatal(1,"Unable to create OSD raster");
    $fwrite(fp,"P6\n640 480\n255\n");
    for(y=0;y<480;y=y+1) begin
        for(x=0;x<640;x=x+1) begin
            @(negedge clk); de=1; #1;
            $fwrite(fp,"%c%c%c",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
            if(x==24 && y==70 && rgb_out!==24'hFFE66D) $fatal(1,"BRI highlight/font not rendered");
            if(x>=18 && x<338 && y>=92 && y<116) begin
                if(rgb_out!==rgb_in) $fatal(1,"Removed HOLD strip still changes pixel (%0d,%0d)",x,y);
                cleared_pixels=cleared_pixels+1;
            end
            if(x==20 && y==64 && rgb_out!==24'h33383E) $fatal(1,"Parameter panel Alpha is incorrect");
            if(x==400 && y==200 && rgb_out!==rgb_in) $fatal(1,"OSD altered background outside panels");
        end
        @(negedge clk); de=0;
        repeat(4) @(negedge clk);
    end
    $fclose(fp);
    if(cleared_pixels!=7680) $fatal(1,"Removed strip test incomplete");
    $display("ALL OSD CONTROL TESTS PASSED: 45 numeric labels, highlight, Alpha, 7680 restored HOLD-strip pixels, background and full raster");
    $finish;
end
initial begin #5000000; $fatal(1,"OSD timeout"); end
endmodule
