`timescale 1ns/1ps
module tb_audio_waveform;
reg clk=0,rst=1,hs=1,vs=0,de=0,audio_valid=0;
always #5 clk=~clk;
reg [23:0] rgb_in=24'h8090A0,audio_left=0,audio_right=0;
wire hs_out,vs_out,de_out;
wire [23:0] rgb_out,osd_rgb;
integer i,j,fp,checked=0,accepted=0;
integer draw_x=0,draw_y=0;
reg raster=0;
reg [23:0] gold [0:511];
audio_waveform_overlay #(.NO_AUDIO_CYCLES(1024)) dut(.*);
video_osd_overlay osd(.clk(clk),.rst(rst),.hs(hs_out),.vs(vs_out),.de(de_out),
    .rgb_in(rgb_out),.brightness(9'sd16),.contrast_q2(3'd5),.active_control(2'd0),.rgb_out(osd_rgb));
function automatic integer level(input logic [23:0] bits);
    integer signed v,s;
    begin
        v=$signed(bits);
        s=(v<0) ? -((-v+65535)/65536) : v/65536;
        if(s>31) s=31;
        if(s< -31) s= -31;
        level=31-s;
    end
endfunction
function automatic bit in_segment(input integer y,a,b);
    in_segment=(a<b) ? y>=a && y<=b : y>=b && y<=a;
endfunction
function automatic [23:0] pixel_reference(input integer xx,yy);
    reg [23:0] word_at,color;
    reg [4:0] glyph;
    integer row,col;
    begin
        color=24'h8090A0;
        if(xx>=48 && xx<592 && yy>=238 && yy<416) begin
            color=24'h202428;
            if(xx==48 || xx==591 || yy==238 || yy==415) color=24'h60849A;
            if(xx>=64 && xx<576 && yy>=255 && yy<=401) begin
                word_at=gold[(xx-64)/2];
                if(xx%64==0 || yy==255 || yy==286 || yy==317 || yy==339 || yy==370 || yy==401)
                    color=24'h294052;
                if(yy>=255 && yy<=317 && in_segment(yy-255,word_at[23:18],word_at[17:12])) color=24'h52E3FF;
                if(yy>=339 && yy<=401 && in_segment(yy-339,word_at[11:6],word_at[5:0])) color=24'hFFE66D;
            end
            if(xx>=52 && xx<62 && yy>=279 && yy<293) begin
                row=(yy-279)/2; col=(xx-52)/2;
                glyph=(row==6)?5'b11111:5'b10000;
                if(glyph[4-col]) color=24'h52E3FF;
            end
            if(xx>=52 && xx<62 && yy>=363 && yy<377) begin
                row=(yy-363)/2; col=(xx-52)/2;
                case(row)
                    0,3:glyph=5'b11110; 1,2,6:glyph=5'b10001;
                    4:glyph=5'b10100; default:glyph=5'b10010;
                endcase
                if(glyph[4-col]) color=24'hFFE66D;
            end
        end
        pixel_reference=color;
    end
endfunction
task sample(input [23:0] l,r);
    @(negedge clk); audio_valid=1; audio_left=l; audio_right=r;
    @(negedge clk); audio_valid=0; audio_left=24'hBADBAD; audio_right=24'hFEDCBA;
    repeat(3) @(negedge clk);
endtask
task frame_edge;
    @(negedge clk); vs=0; repeat(3) @(negedge clk);
    vs=1; repeat(3) @(negedge clk);
endtask
task reset_all;
    @(negedge clk); rst=1; audio_valid=0; vs=0; de=0;
    repeat(4) @(negedge clk); rst=0;
endtask
// Independent capture oracle, including all four sample fields and RAM writes.
reg [23:0] expected_word;
integer addr,l_ref,r_ref,prev_l=31,prev_r=31;
always @(posedge clk) begin
    if(!rst && dut.capture_accept) begin
        addr={dut.capture_bank,dut.capture_index};
        l_ref=level(audio_left); r_ref=level(audio_right);
        expected_word={6'(l_ref),6'((dut.capture_index==0)?l_ref:prev_l),
                       6'(r_ref),6'((dut.capture_index==0)?r_ref:prev_r)};
        prev_l=l_ref; prev_r=r_ref;
        gold[addr]=expected_word; accepted=accepted+1;
        #1;
        if(dut.wave_ram[addr]!==expected_word) $fatal(1,"RAM mismatch at %0d",addr);
    end
end
// Timing scoreboard for EVERY clock; RGB reference covers the whole raster.
reg [1:0] eh=0,ev=0,ed=0,er=0;
integer ex0=0,ex1=0,ey0=0,ey1=0;
always @(posedge clk) begin
    if(rst) begin eh=0; ev=0; ed=0; er=0; end
    else begin
        eh={eh[0],hs}; ev={ev[0],vs}; ed={ed[0],de}; er={er[0],raster && de};
        ex1=ex0; ex0=draw_x; ey1=ey0; ey0=draw_y;
        #1;
        if({hs_out,vs_out,de_out}!=={eh[1],ev[1],ed[1]}) $fatal(1,"Timing pipeline mismatch");
        if(!de_out && rgb_out!==0) $fatal(1,"Blanking not black");
        if(er[1]) begin
            if(rgb_out!==pixel_reference(ex1,ey1))
                $fatal(1,"Raster mismatch (%0d,%0d): got%h expected%h",ex1,ey1,rgb_out,pixel_reference(ex1,ey1));
            $fwrite(fp,"%c%c%c",osd_rgb[23:16],osd_rgb[15:8],osd_rgb[7:0]);
            checked=checked+1;
        end
    end
end
initial begin
    reset_all();
    // Exhaustive signed-byte magnitudes plus boundary low bits and full-scale.
    for(i=0;i<256;i=i+1)
        if(dut.sample_level({8'(i),16'h8123})!==6'(level({8'(i),16'h8123}))) $fatal(1,"Sample scaling mismatch %0d",i);
    if(dut.sample_level(24'h7FFFFF)!==0 || dut.sample_level(24'h800000)!==62 ||
       dut.sample_level(24'hFFFFFF)!==32) $fatal(1,"Signed saturation mismatch");
    sample(-24'sd2000000,24'sd2000000);
    if(dut.capturing || accepted!=0) $fatal(1,"Captured before trigger");
    sample(24'sd2000000,-24'sd2000000);
    if(dut.capture_index!=1) $fatal(1,"Rising zero-cross trigger missed");
    for(i=1;i<256;i=i+1) sample(24'((i-128)*65536),24'((127-i)*65536));
    if(!dut.pending || dut.display_valid || accepted!=256) $fatal(1,"Snapshot completed incorrectly");
    for(i=0;i<20;i=i+1) sample(24'h123456,24'h654321);
    if(accepted!=256) $fatal(1,"Pending buffer was overwritten");
    sample(0,0); frame_edge();
    if(!dut.display_valid || dut.display_bank!=0 || dut.capture_bank!=1 || dut.pending)
        $fatal(1,"Frame bank exchange incorrect");
    fp=$fopen("extension5_waveform_preview.ppm","wb");
    if(!fp) $fatal(1,"Cannot create waveform raster");
    $fwrite(fp,"P6\n640 480\n255\n"); raster=1;
    for(j=0;j<480;j=j+1) begin
        for(i=0;i<640;i=i+1) begin
            @(negedge clk); de=1; draw_x=i; draw_y=j; hs=(i>=96);
        end
        @(negedge clk); de=0; repeat(5) @(negedge clk);
    end
    repeat(4) @(negedge clk); raster=0; $fclose(fp);
    if(checked!=307200) $fatal(1,"Wrong raster count: %0d",checked);
    if(!dut.display_valid) $fatal(1,"Display changed mid-frame on timeout");
    frame_edge();
    if(dut.display_valid || dut.pending || dut.capturing) $fatal(1,"Missing audio did not clear at frame boundary");
    reset_all(); accepted=0;
    // Silence has no edge: timeout in SAMPLE counts must still capture flat PCM.
    for(i=0;i<255;i=i+1) sample(0,0);
    if(dut.capturing || accepted!=0) $fatal(1,"Auto trigger occurred too early");
    sample(0,0);
    for(i=1;i<256;i=i+1) sample(0,0);
    if(!dut.pending || accepted!=256) $fatal(1,"Silence/DC auto trigger failed");
    for(i=0;i<256;i=i+1) if(dut.wave_ram[i]!=={4{6'd31}}) $fatal(1,"Silence not flat");
    frame_edge();
    if(!dut.display_valid) $fatal(1,"Audio did not recover after timeout");
    reset_all();
    if(dut.display_valid || dut.pending || dut.capturing) $fatal(1,"Reset failed");
    $display("ALL WAVEFORM TESTS PASSED: signed gain, saturation, trigger, silence, freeze, frame swap, timeout/recovery, 307200 RGB pixels and timing");
    $finish;
end
initial begin #10000000; $fatal(1,"Waveform timeout"); end
endmodule
