`timescale 1ns/1ps
module tb_theme_ticker;
reg clk=0,rst=1,hs=1,vs=0,de=0,audio_valid=0;
always #5 clk=~clk;
reg [2:0] lesson_idx=0,contrast_q2=4;
reg [23:0] audio_left=0,audio_right=0,rgb_in=0;
reg signed [8:0] brightness=0;
reg [1:0] active_control=0;
wire [23:0] rgb_out,baseline_rgb;
video_osd_overlay dut(.*);
video_osd_overlay_baseline baseline(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb_in(rgb_in),
    .brightness(brightness),.contrast_q2(contrast_q2),.active_control(active_control),.rgb_out(baseline_rgb));
string phrases[0:4]='{"EXPLORE PITCH AND FREQUENCY","DISCOVER SOUND AMPLITUDE","EXPLORE TIMBRE AND HARMONICS","EXPLORE STEREO SOUND","FROM WAVEFORMS TO MUSIC"};
integer lengths[0:4]='{27,24,28,20,23},accents[0:4]='{18,15,19,15,18};
integer peak_l=0,peak_r=0,env_l=0,env_r=0,motion=0,mdiv=0,ref_page=0,ref_scroll=0;
integer bars_l[0:6],bars_r[0:6];
reg ref_vs=0;
integer a,b,t,target,k;
function automatic integer envelope(input integer old_value,peak);
    integer v;
    begin
        v=peak/256; if(v>7936) v=7936;
        envelope=(v>old_value) ? old_value+(v-old_value+3)/4 : old_value-(old_value-v+15)/16;
    end
endfunction
function automatic integer bar(input integer level,shape);
    case(shape)
        0,4:bar=3+level/4;
        1,6:bar=3+level/2;
        2,5:bar=3+level/2+level/4;
        default:bar=3+level/2+level/8;
    endcase
endfunction
always @(posedge clk) begin
    if(rst) begin
        peak_l=0; peak_r=0; env_l=0; env_r=0; motion=0; mdiv=0; ref_page=0; ref_scroll=0; ref_vs=0;
        for(k=0;k<7;k=k+1) begin bars_l[k]=3; bars_r[k]=3; end
    end else begin
        if(audio_valid) begin
            a=$signed(audio_left); if(a<0) a=-a;
            b=$signed(audio_right); if(b<0) b=-b;
            if(a>peak_l) peak_l=a; if(b>peak_r) peak_r=b;
        end
        if(vs && !ref_vs) begin
            env_l=envelope(env_l,peak_l); env_r=envelope(env_r,peak_r); peak_l=0; peak_r=0;
            for(k=0;k<7;k=k+1) begin
                target=bar(env_l/256,(motion+k)%8);
                if(target>bars_l[k]) bars_l[k]=bars_l[k]+1; else if(target<bars_l[k]) bars_l[k]=bars_l[k]-1;
                target=bar(env_r/256,(motion+6-k)%8);
                if(target>bars_r[k]) bars_r[k]=bars_r[k]+1; else if(target<bars_r[k]) bars_r[k]=bars_r[k]-1;
            end
            mdiv=mdiv+1; if(mdiv==8) begin mdiv=0; motion=(motion+1)%8; end
            if(lesson_idx!=ref_page) begin ref_page=lesson_idx<=4 ? lesson_idx : 0; ref_scroll=0; end
            else ref_scroll=(ref_scroll+1)%((38+lengths[ref_page])*12);
        end
        ref_vs=vs;
    end
    #1;
    if(dut.u_sound_theme_footer.envelope_left!==13'(env_l) || dut.u_sound_theme_footer.envelope_right!==13'(env_r))
        $fatal(1,"PCM envelope mismatch %0d/%0d",env_l,env_r);
    if(dut.u_sound_theme_footer.caption_page!==3'(ref_page) ||
       dut.u_sound_theme_footer.scroll_char*12+dut.u_sound_theme_footer.scroll_pixel!=ref_scroll)
        $fatal(1,"Caption changed mid-frame or phase mismatch");
    for(k=0;k<7;k=k+1)
        if(dut.u_sound_theme_footer.bars_left[k]!==5'(bars_l[k]) || dut.u_sound_theme_footer.bars_right[k]!==5'(bars_r[k]))
            $fatal(1,"Side bar smoothing mismatch %0d",k);
end
function automatic [23:0] mix(input integer alpha,input bit gold);
    integer r,g,b;
    begin
        r=(15*(16-alpha)+(gold?238:77)*alpha)/16;
        g=(30*(16-alpha)+(gold?200:219)*alpha)/16;
        b=(48*(16-alpha)+(gold?131:207)*alpha)/16;
        mix={8'(r),8'(g),8'(b)};
    end
endfunction
function automatic [4:0] font(input byte c,input integer row);
    reg [34:0] bits;
    begin
        case(c)
            "Q":bits={5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
            "S":bits={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
            "V":bits={5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b01010,5'b00100};
            "W":bits={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b11011,5'b10001};
            "X":bits={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
            "Y":bits={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
            default:bits=0;
        endcase
        if(c=="Q" || c=="S" || c=="V" || c=="W" || c=="X" || c=="Y") font=5'((bits>>(30-row*5))&31);
        else font=baseline.font5x7(c,3'(row));
    end
endfunction
function automatic [23:0] pixel(input integer x,y,input [23:0] source);
    integer distance,cut,side,col,index,h,level,alpha,offset;
    reg gold,in_panel;
    reg [4:0] bits;
    begin
        pixel=source;
        if(y>=430 && y<464 && x>=8 && x<632) begin
            distance=(y<447) ? y-430 : 463-y;
            case(distance) 0:cut=8; 1:cut=4; 2,3:cut=2; 4,5:cut=1; default:cut=0; endcase
            in_panel=x>=8+cut && x<632-cut;
            if(in_panel) begin
                pixel=24'h0F1E30;
                if((x>=22 && x<78) || (x>=566 && x<622)) begin
                    side=x>=566; offset=side ? x-566 : x-22; index=offset/8; col=offset%8;
                    if(index<7 && col<4) begin
                        h=side ? bars_r[index] : bars_l[index]; level=side ? env_r : env_l;
                        if(y>=459-h && y<=458 && ((y!=459-h && y!=458) || (col!=0 && col!=3)))
                            pixel=mix(9+level/1024,index==0 || index==3 || index==6);
                    end
                end
                if(x>=92 && x<548 && y>=440 && y<454) begin
                    index=(ref_scroll+x-92)/12-38; col=((ref_scroll+x-92)%12)/2;
                    if(index>=0 && index<lengths[ref_page] && col<5) begin
                        bits=font(phrases[ref_page][index],(y-440)/2);
                        distance=(x-92<547-x) ? x-92 : 547-x;
                        alpha=distance/2; if(alpha>16) alpha=16;
                        level=(env_l>env_r) ? env_l : env_r;
                        if(alpha>9+level/1024) alpha=9+level/1024;
                        if(bits[4-col]) pixel=mix(alpha,index>=accents[ref_page]);
                    end
                end
            end
        end
    end
endfunction
task frame(input [23:0] left,right);
    @(negedge clk); de=0; vs=0; audio_valid=1; audio_left=left; audio_right=right;
    repeat(3) @(negedge clk); vs=1;
    repeat(3) @(negedge clk); audio_valid=0;
endtask
reg [23:0] picture[0:307199];
reg [23:0] logo_gold[0:1487];
reg [23:0] logo_expected;
integer page,x,y,i,j,fp,outside_checked=0,footer_checked=0;
initial begin
    $readmemh("logo_expected.hex",logo_gold);
    repeat(5) @(negedge clk); rst=0;
    // Exhaustive exact strings, every font row, all blend levels.
    for(page=0;page<5;page=page+1) begin
        for(i=0;i<32;i=i+1) begin
            if(dut.u_sound_theme_footer.caption_char(3'(page),5'(i))!==(i<lengths[page] ? phrases[page][i] : 8'h20))
                $fatal(1,"Caption page%0d char%0d incorrect",page,i);
            if(i<lengths[page]) for(j=0;j<7;j=j+1)
                if(dut.u_sound_theme_footer.font5x7(phrases[page][i],3'(j))!==font(phrases[page][i],j)) $fatal(1,"Missing/incorrect font");
        end
    end
    for(i=0;i<=16;i=i+1) for(j=0;j<2;j=j+1)
        if(dut.u_sound_theme_footer.footer_color(5'(i),1'(j))!==mix(i,1'(j))) $fatal(1,"Alpha gradient incorrect");
    repeat(50) frame(24'h7FFFFF,24'h800000);
    if(env_l<7900 || env_r<7900) $fatal(1,"Full-scale clipping not tested");
    repeat(256) frame(0,0);
    if(env_l || env_r) $fatal(1,"Silence did not decay to zero");
    repeat(60) frame(0,24'h1F0000);
    if(env_l || env_r<7900 || bars_l[2]!=3 || bars_r[2]<=3) $fatal(1,"Stereo independence failed");
    lesson_idx=4; frame(0,0); // ensure page 1 starts from a fresh entry phase
    for(page=0;page<5;page=page+1) begin
        lesson_idx=3'(page); frame(0,0);
        // Put each complete phrase near the center using normal VS clocks.
        for(i=0;i<228+lengths[page]*6;i=i+1) frame(24'd1800000,24'd900000);
        $readmemh($sformatf("science_image_%0d.hex",page),picture);
        fp=$fopen($sformatf("ticker_page_%0d.ppm",page),"wb"); $fwrite(fp,"P6\n640 480\n255\n");
        brightness=9'(page*16-32); contrast_q2=3'(page+2); active_control=2'(page%4);
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk); de=1; rgb_in=picture[(479-y)*640+x]; #2;
                if(y<430 || y>=464) begin
                    if(x>=18 && x<174 && y>=14 && y<50) begin
                        logo_expected=rgb_in;
                        if(x<74) begin
                            logo_expected=24'hFFFFFF;
                            if(x>=22 && x<70 && y>=16 && y<47) logo_expected=logo_gold[(y-16)*48+x-22];
                        end
                        if(rgb_out!==logo_expected) $fatal(1,"Supplied logo mismatch in ticker regression");
                    end else if(rgb_out!==baseline_rgb) $fatal(1,"Changed non-footer pixel page%0d (%0d,%0d)",page,x,y);
                    outside_checked=outside_checked+1;
                end else begin
                    if(rgb_out!==pixel(x,y,rgb_in)) $fatal(1,"Footer pixel mismatch page%0d (%0d,%0d):%h/%h",page,x,y,rgb_out,pixel(x,y,rgb_in));
                    footer_checked=footer_checked+1;
                end
                $fwrite(fp,"%c%c%c",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
                if(x==350 && y==240) lesson_idx=3'((page+1)%5); // no mid-frame change
            end
            @(negedge clk); de=0; repeat(4) @(negedge clk);
        end
        $fclose(fp); $display("PASS themed page %0d: exact bottom raster, all outside pixels unchanged",page);
    end
    if(outside_checked!=1427200 || footer_checked!=108800) $fatal(1,"Missing whole-screen checks");
    rst=1; repeat(4) @(negedge clk);
    $display("ALL THEME TICKER TESTS PASSED: five exact captions/fonts, 1536000 pixels, BMP logo goldens, unchanged other outside-footer/BRI/timing, PCM/stereo/attack/release, frame-atomic switches, gradients/reset");
    $finish;
end
initial begin #30000000; $fatal(1,"Themed ticker timeout"); end
endmodule
