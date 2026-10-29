`timescale 1ns/1ps
// Independent display-address/RGB reference, plus exact secondary comparison
// to bf35426 outside the requested note/PK/HZ rectangle. No FFT stubs in the
// separate serial-input integration regression (run_voice_display.do).
module tb_voice_focus;
reg clk=0,rst=1;
always #20 clk=~clk;
integer col=0,line=0,frames=0;
always @(posedge clk) if(!rst) begin
    if(col==799) begin col<=0;if(line==524) begin line<=0;frames<=frames+1;end else line<=line+1;end
    else col<=col+1;
end
wire hs=col>=96,vs=line>=2,de=col>=160 && line>=45;
reg spectrum_write=0,result_done=0;
reg panel_visible=1;
reg [7:0] spectrum_address=0;
reg [6:0] spectrum_height=0;
wire result_ack,hs_out,vs_out,de_out;
wire [23:0] rgb_out;
audio_spectrum_overlay spectrum(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb_in(24'h204060),
    .audio_valid(1'b1),.voice_mode(1'b1),.*);
reg [2:0] lesson=5;
reg [79:0] shown_feature={1'b1,15'd882,20'h00882,4'd9,3'd5,1'b1,36'd0};
wire frame_tick,scene_clear,axis_user,axis_valid,axis_last;
wire [6:0] read_column;
wire [5:0] read_band;
wire [11:0] xy_read_address;
wire [23:0] axis_data;
secondary_audio_renderer sec(.lesson_valid(1'b1),.video_locked(1'b1),
    .heat_q(4'd10),.trace_q(8'h94),.shown_head(7'd110),.shown_count(7'd96),.shown_right(1'b0),
    .peak_left(8'd100),.peak_right(8'd70),.average_left(8'd40),.average_right(8'd30),.harmonic_heights(30'd0),
    .harmonic_valid(1'b0),.xy_q(1'b0),.xy_visible(1'b0),.*);
wire old_tick,old_clear,old_user,old_valid,old_last;
wire [6:0] old_column;
wire [5:0] old_band;
wire [11:0] old_xy;
wire [23:0] old_data;
voice_baseline_focus_secondary old(.clk(clk),.rst(rst),.lesson(lesson),.shown_feature(shown_feature),
    .lesson_valid(1'b1),.video_locked(1'b1),.heat_q(4'd10),.trace_q(8'h94),
    .shown_head(7'd110),.shown_count(7'd96),.shown_right(1'b0),.peak_left(8'd100),.peak_right(8'd70),
    .average_left(8'd40),.average_right(8'd30),.harmonic_heights(30'd0),.harmonic_valid(1'b0),.xy_q(1'b0),.xy_visible(1'b0),
    .frame_tick(old_tick),.scene_clear(old_clear),.read_column(old_column),.read_band(old_band),.xy_read_address(old_xy),
    .axis_user(old_user),.axis_valid(old_valid),.axis_last(old_last),.axis_data(old_data));
function integer band_height(input integer b);
    // Deliberately large out-of-view values expose unintended DC/high bands.
    band_height=(b<2 || b>37) ? 66 : (b%5+1)*8;
endfunction
integer i,px,py,sx,sy,b,bin_no,h,graph_checks=0,header_checks=0,unchanged=0,removed_ink=0,address_checks=0;
integer hidden_checks=0,acks=0;
reg [127:0] visited=0;
reg [23:0] expected;
reg main_valid,main_visible;
always @(posedge clk) begin
    px=spectrum.px;py=spectrum.py;sx=sec.px;sy=sec.py;main_valid=spectrum.valid_q;main_visible=spectrum.visible_q;
    if(!rst && spectrum.x>=64 && spectrum.x<576) begin
        bin_no=2+(spectrum.x-64)*42/512;
        b=bin_no<32 ? bin_no : 32+(bin_no-32)/2;
        if(spectrum.read_band_index!==b[6:0]) $fatal(1,"Voice frequency/address mapping mismatch");
        visited[b]=1;address_checks=address_checks+1;
    end
    #2;
    if(!rst) begin
        if(result_ack) acks=acks+1;
        if({axis_user,axis_valid,axis_last,frame_tick,scene_clear,read_column,read_band,xy_read_address}!==
           {old_user,old_valid,old_last,old_tick,old_clear,old_column,old_band,old_xy}) $fatal(1,"Secondary timing/address changed");
        if(axis_valid && frames>=1 && frames<3) begin
            if(sx>=40 && sx<320 && sy>=74 && sy<108) begin
                if(axis_data!==24'h071622) $fatal(1,"Note/PK/HZ/placeholder not fully hidden %0d,%0d",sx,sy);
                if(old_data!=24'h071622) removed_ink=removed_ink+1;
                header_checks=header_checks+1;
            end else begin
                if(axis_data!==old_data) $fatal(1,"Secondary changed outside allowed rectangle %0d,%0d",sx,sy);
                unchanged=unchanged+1;
            end
        end
        if(de_out && frames==2 && px>=48 && px<592 && py>=120 && py<236) begin
            if(rgb_out!==24'h204060) $fatal(1,"Hidden voice FFT did not pass through original image");
            hidden_checks=hidden_checks+1;
        end
        if(de_out && main_valid && main_visible && frames>=1 && px>=64 && px<576 && py>=149 && py<=214) begin
            bin_no=2+(px-64)*42/512;b=bin_no<32 ? bin_no : 32+(bin_no-32)/2;
            h=band_height(b);expected=24'h081018;
            if(px==64 || px==192 || px==320 || px==448 || px==575 || py==170 || py==192 || py==214) expected=24'h294052;
            if(py>214-h) expected=24'h5BDAC6;
            if(rgb_out!==expected) $fatal(1,"Voice band RAM->RGB mismatch x%0d y%0d bin%0d band%0d got%h expected%h",px,py,bin_no,b,rgb_out,expected);
            graph_checks=graph_checks+1;
        end
    end
end
initial begin
    repeat(8) @(negedge clk);rst=0;
    for(i=0;i<256;i=i+1) begin
        @(negedge clk);spectrum_write=1;spectrum_address=i;spectrum_height=band_height(i%128);
    end
    @(negedge clk);spectrum_write=0;result_done=1;
    @(negedge clk);result_done=0;
    wait(frames==2);@(negedge clk);shown_feature=0;panel_visible=0;
    // Results must still publish/ack while the shared KEY3 display is hidden.
    for(i=0;i<256;i=i+1) begin
        @(negedge clk);spectrum_write=1;spectrum_address=i;spectrum_height=band_height(i%128);
    end
    @(negedge clk);spectrum_write=0;result_done=1;
    @(negedge clk);result_done=0;
    wait(frames==3);@(negedge clk);panel_visible=1;
    wait(frames==4);repeat(3) @(negedge clk);
    for(i=0;i<128;i=i+1) if(visited[i] !== (i>=2 && i<=37)) $fatal(1,"Missing/unwanted displayed FFT band %0d",i);
    if(graph_checks<60000 || header_checks!=19040 || unchanged!=595360 || removed_ink<500 || hidden_checks!=63104 || acks<2)
        $fatal(1,"Incomplete UI coverage graph%0d header%0d unchanged%0d removed%0d",graph_checks,header_checks,unchanged,removed_ink);
    // Placeholder state must be hidden too, not only valid A5/882Hz text.
    $display("ALL VOICE FOCUS UI TESTS PASSED: FFT bins2..43/bands2..37, %0d independently checked graph pixels, %0d header pixels blank including no-signal placeholders, %0d other secondary pixels exact to bf35426, %0d old note/PK/HZ ink pixels removed, unchanged framing/addresses; %0d hidden pixels pass through; %0d acks and restored spectrum",graph_checks,header_checks,unchanged,removed_ink,hidden_checks,acks);
    $finish;
end
initial begin #90000000;$fatal(1,"Voice focus UI timeout");end
endmodule
