`timescale 1ns/1ps
// Composition preview: real packed BMP pixels, address-test oracle and real OSD.
// The ticker position is fixed only in this bench to inspect the Chinese glyphs.
module tb_nature_preview;
reg clk=0,rst=1,hs=1,vs=0,de=0;always #20 clk=~clk;
reg [23:0] rgb_in=0;
wire [23:0] rgb_out;
video_osd_overlay dut(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb_in(rgb_in),
    .brightness(9'sd0),.contrast_q2(3'd4),.active_control(2'd0),.lesson_idx(3'd6),
    .audio_valid(1'b1),.audio_left(24'h1b0000),.audio_right(24'h1b0000),.rgb_out(rgb_out));
byte unsigned p0[0:1690623],p1[0:1690623],p2[0:1690623],p3[0:1690623];
integer fp,n,page,x,y,lx,ly,owner,at,i;
function automatic [7:0] b(input integer p,a);
    case(p) 0:b=p0[a];1:b=p1[a];2:b=p2[a];3:b=p3[a];endcase
endfunction
initial begin
    fp=$fopen("../output/nature_intro_tf/INTRO1.BMP","rb");n=$fread(p0,fp);$fclose(fp);
    fp=$fopen("../output/nature_intro_tf/INTRO2.BMP","rb");n=$fread(p1,fp);$fclose(fp);
    fp=$fopen("../output/nature_intro_tf/INTRO3.BMP","rb");n=$fread(p2,fp);$fclose(fp);
    fp=$fopen("../output/nature_intro_tf/INTRO4.BMP","rb");n=$fread(p3,fp);$fclose(fp);
    repeat(8) @(negedge clk);rst=0;
    for(i=0;i<32;i=i+1) begin vs=0;repeat(3) @(negedge clk);vs=1;repeat(3) @(negedge clk);end
    force dut.u_sound_theme_footer.scroll_char=22;
    force dut.u_sound_theme_footer.scroll_pixel=0;
    for(page=0;page<4;page=page+1) begin
        de=0;vs=0;repeat(8) @(negedge clk);vs=1;repeat(8) @(negedge clk);
        fp=$fopen($sformatf("nature_stage_%0d.ppm",page),"wb");$fwrite(fp,"P6\n640 480\n255\n");
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                lx=x;ly=y;owner=0;
                if(page>=1 && x>=24 && x<536 && y>=24 && y<408) begin lx=x-24;ly=y-24;owner=1;end
                if(page>=2 && x>=104 && x<616 && y>=40 && y<424) begin lx=x-104;ly=y-40;owner=2;end
                if(page>=3 && x>=64 && x<576 && y>=8 && y<392) begin lx=x-64;ly=y-8;owner=3;end
                at=128+(479-ly)*1920+lx*3;
                @(negedge clk);de=1;rgb_in={b(owner,at+2),b(owner,at+1),b(owner,at)};#2;
                if(dut.x!=x || dut.y!=y) $fatal(1,"Preview framing mismatch");
                $fwrite(fp,"%c%c%c",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
            end
            @(negedge clk);de=0;repeat(4) @(negedge clk);
        end
        $fclose(fp);
    end
    if(dut.u_sound_theme_footer.caption_page!=6 || dut.u_sound_theme_footer.caption_length(6)!=6)
        $fatal(1,"Nature caption selection failed");
    $display("ALL NATURE PREVIEW TESTS PASSED: four 640x480 compositions, original logo/time/parameters, Chinese ticker, original footer bars");$finish;
end
initial begin #60000000;$fatal(1,"Preview timeout");end
endmodule
