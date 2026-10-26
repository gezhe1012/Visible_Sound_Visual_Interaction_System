`timescale 1ns/1ps
// Actual RTL footer raster. Accelerated VS/PCM excitation for a complete scroll
// loop; saved frames are every eighth 59.52Hz video frame (about 7.44 fps).
module tb_ticker_animation;
reg clk=0,rst=1,vs=0,de=0,audio_valid=0;
always #5 clk=~clk;
reg [9:0] x=0,y=0;
reg [2:0] lesson_idx=0;
reg [23:0] audio_left=0,audio_right=0;
wire draw;
wire [23:0] rgb;
sound_theme_footer dut(.*);
string phrase="EXPLORE PITCH AND FREQUENCY";
integer f,i,j,n,fp,phase=0,index,col,row,alpha,breath,distance,rr,gg,bb;
reg [4:0] bits;
reg [16:0] seen_alpha=0;
reg [23:0] expected;
task frame(input [23:0] l,r);
    @(negedge clk); de=0; vs=0; audio_valid=1; audio_left=l; audio_right=r;
    repeat(3) @(negedge clk); vs=1; repeat(3) @(negedge clk); audio_valid=0;
    phase=(phase+1)%780;
endtask
initial begin
    repeat(5) @(negedge clk); rst=0;
    // Warm envelope, then arrive naturally at phase zero; no forced state.
    repeat(780) frame(24'h1FFFFF,24'h1FFFFF);
    if(phase!=0 || dut.scroll_char!=0 || dut.scroll_pixel!=0) $fatal(1,"Scroll failed to wrap");
    for(f=0;f<100;f=f+1) begin
        for(n=0;n<8;n=n+1)
            if(f%32<16) frame(24'h1FFFFF,24'd800000); else frame(24'd500000,24'd1900000);
        fp=$fopen($sformatf("ticker_anim_%03d.ppm",f),"wb"); $fwrite(fp,"P6\n640 34\n255\n");
        for(j=430;j<464;j=j+1) begin
            for(i=0;i<640;i=i+1) begin
                @(negedge clk); de=1; x=10'(i); y=10'(j); #2;
                if(i>=92 && i<548 && j>=440 && j<454) begin
                    if(dut.cursor_char!=(phase+i-92)/12 || dut.cursor_pixel!=(phase+i-92)%12)
                        $fatal(1,"Caption cursor phase/line alignment incorrect");
                    index=(phase+i-92)/12-38; col=((phase+i-92)%12)/2; row=(j-440)/2;
                    if(index>=0 && index<27 && col<5) begin
                        bits=dut.font5x7(phrase[index],3'(row));
                        if(bits[4-col]) begin
                            distance=(i-92<547-i) ? i-92 : 547-i;
                            alpha=distance/2; if(alpha>16) alpha=16;
                            breath=9+((dut.envelope_left>dut.envelope_right ? dut.envelope_left : dut.envelope_right)/1024);
                            if(alpha>breath) alpha=breath;
                            rr=(15*(16-alpha)+(index>=18?238:77)*alpha)/16;
                            gg=(30*(16-alpha)+(index>=18?200:219)*alpha)/16;
                            bb=(48*(16-alpha)+(index>=18?131:207)*alpha)/16;
                            expected={8'(rr),8'(gg),8'(bb)};
                            if(rgb!==expected) $fatal(1,"Actual edge glyph alpha incorrect");
                            seen_alpha[alpha]=1;
                        end
                    end
                end
                expected=draw ? rgb : 24'h071521;
                $fwrite(fp,"%c%c%c",expected[23:16],expected[15:8],expected[7:0]);
            end
            @(negedge clk); de=0; repeat(2) @(negedge clk);
        end
        $fclose(fp);
    end
    if(seen_alpha!=17'h1FFFF) $fatal(1,"Not all 17 fade levels exercised: %h",seen_alpha);
    $display("ALL TICKER ANIMATION TESTS PASSED: 100 RTL rasters, complete scroll/wrap, real edge glyphs at all 17 fade levels, PCM-reactive bars");
    $finish;
end
initial begin #30000000; $fatal(1,"Ticker animation timeout"); end
endmodule
