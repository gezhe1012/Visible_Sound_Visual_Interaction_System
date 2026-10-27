// 640x480, 25MHz, independent AXIS stream. Two-cycle RGB/framing pipeline.
// Counter-based cell addressing: 96 time cells x5, 64 bands x3.
module secondary_audio_renderer(
    input clk,rst,
    input [2:0] lesson,
    input lesson_valid,video_locked,
    input [3:0] heat_q,
    input [7:0] trace_q,
    input [6:0] shown_head,shown_count,
    input [79:0] shown_feature,
    input shown_right,
    input [7:0] peak_left,peak_right,average_left,average_right,
    output frame_tick,scene_clear,
    output [6:0] read_column,
    output [5:0] read_band,
    output axis_user,axis_valid,axis_last,
    output reg [23:0] axis_data
);
reg [9:0] col,line;
reg [2:0] shown_lesson;
reg shown_valid,shown_locked;
reg [6:0] cell_x;
reg [2:0] cell_sub;
reg [5:0] frequency_band;
reg [1:0] frequency_sub;
wire active=col>=160 && line>=45;
wire [9:0] x=col-10'd160,y=line-10'd45;
assign frame_tick=col==0 && line==0;
assign scene_clear=frame_tick && (lesson!=shown_lesson || lesson_valid!=shown_valid);
assign read_column=shown_head-7'd96+cell_x;
assign read_band=frequency_band;
reg [9:0] px,py;
reg [6:0] time_cell;
reg [2:0] sub_x;
reg [1:0] sub_y;
reg cell_valid;
reg [1:0] user_pipe,valid_pipe,last_pipe;
assign axis_user=user_pipe[1];assign axis_valid=valid_pipe[1];assign axis_last=last_pipe[1];
reg [7:0] previous_trace;
reg [23:0] composed,ink;
reg [9:0] tx,ty,current_trace_y,prior_trace_y;
reg [7:0] character;
wire [34:0] glyph;
reg [1:0] font_scale;
reg text_on;
reg [4:0] char_index;
secondary_font5x7 font(.character(character),.bits(glyph));
always @(posedge clk or posedge rst) begin
    if(rst) begin
        col<=0;line<=0;shown_lesson<=0;shown_valid<=0;shown_locked<=0;
        cell_x<=0;cell_sub<=0;frequency_band<=63;frequency_sub<=0;
        px<=0;py<=0;time_cell<=0;sub_x<=0;sub_y<=0;cell_valid<=0;
        user_pipe<=0;valid_pipe<=0;last_pipe<=0;axis_data<=0;previous_trace<=0;
    end else begin
        if(col==799) begin
            col<=0;if(line==524) line<=0;else line<=line+10'd1;
            if(line>=205 && line<=396) begin
                if(frequency_sub==2) begin frequency_sub<=0;frequency_band<=frequency_band-6'd1;end
                else frequency_sub<=frequency_sub+2'd1;
            end else begin frequency_sub<=0;frequency_band<=63;end
        end else col<=col+10'd1;
        if(col<224 || col>=704) begin cell_x<=0;cell_sub<=0;end
        else if(cell_sub==4) begin cell_sub<=0;cell_x<=cell_x+7'd1;end
        else cell_sub<=cell_sub+3'd1;
        if(frame_tick) begin shown_lesson<=lesson;shown_valid<=lesson_valid;shown_locked<=video_locked;end
        px<=x;py<=y;time_cell<=cell_x;sub_x<=cell_sub;sub_y<=frequency_sub;
        cell_valid<=cell_x>=7'd96-shown_count;
        user_pipe<={user_pipe[0],col==160 && line==45};
        valid_pipe<={valid_pipe[0],active};last_pipe<={last_pipe[0],active && col==799};
        axis_data<=valid_pipe[0] ? composed : 24'd0;
        if(px==64) previous_trace<=0;
        if(px>=64 && px<544 && sub_x==4) previous_trace<=cell_valid ? trace_q : 8'd0;
    end
end
function [23:0] palette;
    input [3:0] level;
    begin
        case(level)
            0:palette=24'h0D2637;1:palette=24'h10364B;2:palette=24'h12485E;3:palette=24'h145A70;
            4:palette=24'h176F84;5:palette=24'h1B8594;6:palette=24'h219BA4;7:palette=24'h2AB1B0;
            8:palette=24'h39C5B9;9:palette=24'h55D8C4;10:palette=24'h78E3CE;11:palette=24'hA2E6CE;
            12:palette=24'hCADFB2;13:palette=24'hE5D493;14:palette=24'hF0C676;15:palette=24'hFFE1A0;
        endcase
    end
endfunction
function [7:0] word_char;
    input [175:0] word;
    input [4:0] index;
    begin word_char=index<22 ? word[175-index*8-:8] : " ";end
endfunction
function [7:0] note_letter;
    input [3:0] key;
    begin
        case(key)
            0,1:note_letter="C";2,3:note_letter="D";4:note_letter="E";5,6:note_letter="F";
            7,8:note_letter="G";9,10:note_letter="A";default:note_letter="B";
        endcase
    end
endfunction
function is_sharp;
    input [3:0] key;
    begin is_sharp=key==1 || key==3 || key==6 || key==8 || key==10;end
endfunction
function [7:0] page_char;
    input [2:0] page;
    input [4:0] index;
    begin
        case(page)
            0:page_char=word_char("PITCH                 ",index);
            1:page_char=word_char("LEVEL                 ",index);
            2:page_char=word_char("TIMBRE                ",index);
            3:page_char=word_char("STEREO                ",index);
            4:page_char=word_char("MUSIC                 ",index);
            default:page_char=" ";
        endcase
    end
endfunction
wire levels_page=shown_lesson==1 || shown_lesson==3;
wire pitch_valid=shown_valid && shown_feature[79];
always @* begin
    composed=24'h071622;ink=24'hD7E5EF;tx=0;ty=0;character=" ";font_scale=0;text_on=0;char_index=0;
    current_trace_y=10'd455-{4'd0,trace_q[5:0]};prior_trace_y=10'd455-{4'd0,previous_trace[5:0]};
    if(py==58 && px>=24 && px<616) composed=24'h294858;
    if(px>=24 && px<616 && py>=136 && py<376 && ((px>=32 && px<608) || (py>=144 && py<368))) composed=24'h102A3B;
    if(px>=24 && px<616 && py>=392 && py<464 && ((px>=32 && px<608) || (py>=400 && py<456))) composed=24'h102A3B;
    if(px>=64 && px<544 && py>=160 && py<352) begin
        composed=24'h0A2030;
        if(cell_valid && sub_x<4 && sub_y<2) composed=palette(heat_q);
    end
    if(px>=568 && px<576 && py>=160 && py<352) composed=palette(frequency_band[5:2]);
    if(!levels_page && px>=64 && px<544 && py>=408 && py<=455) begin
        if(py==408 || py==424 || py==440 || py==455 || (time_cell[4:0]==0 && sub_x==0)) composed=24'h244455;
        if(cell_valid && trace_q[7]) begin
            if(py==current_trace_y || (sub_x==0 && time_cell!=0 && previous_trace[7] &&
                ((py>=current_trace_y && py<=prior_trace_y) || (py>=prior_trace_y && py<=current_trace_y))))
                composed=trace_q[6] ? 24'hE9C477 : 24'h5BDAC6;
        end
    end
    if(levels_page) begin
        if(py>=412 && py<424) begin
            if(px>=80 && px<304) composed=px-80<peak_left ? 24'h5BDAC6 : 24'h244455;
            if(px>=352 && px<576) composed=px-352<peak_right ? 24'h5BDAC6 : 24'h244455;
        end
        if(py>=440 && py<448) begin
            if(px>=80 && px<304) composed=px-80<average_left ? 24'hE9C477 : 24'h244455;
            if(px>=352 && px<576) composed=px-352<average_right ? 24'hE9C477 : 24'h244455;
        end
    end
    if(px>=600 && px<608 && py>=28 && py<36) composed=shown_locked ? 24'h5BDAC6 : 24'hE9C477;
    if(px>=24 && px<312 && py>=24 && py<38) begin
        tx=px-24;ty=py-24;font_scale=1;text_on=1;character=word_char("SOUND LAB             ",tx[8:4]);
    end else if(px>=448 && px<592 && py>=28 && py<35) begin
        tx=px-448;ty=py-28;text_on=1;char_index=tx[7:3];
        if(!shown_valid) character=word_char("WAIT                  ",char_index);
        else if(char_index==0) character="0";
        else if(char_index==1) character="1"+{5'd0,shown_lesson};
        else if(char_index==3) character="/";
        else if(char_index>=5) character=page_char(shown_lesson,char_index-5);
    end else if(px>=40 && px<136 && py>=80 && py<108) begin
        tx=px-40;ty=py-80;font_scale=2;text_on=1;char_index={3'd0,tx[6:5]};ink=24'h5BDAC6;
        if(!pitch_valid || !shown_feature[36]) character="-";
        else case(char_index)
            0:character=note_letter(shown_feature[43:40]);
            1:character=is_sharp(shown_feature[43:40]) ? "#" : " ";
            2:character="0"+{5'd0,shown_feature[39:37]};
        endcase
    end else if(px>=192 && px<224 && py>=74 && py<81) begin
        tx=px-192;ty=py-74;text_on=1;character=word_char("F0~                   ",tx[7:3]);ink=24'h91ADBD;
    end else if(px>=192 && px<272 && py>=88 && py<102) begin
        tx=px-192;ty=py-88;font_scale=1;text_on=1;char_index={2'd0,tx[6:4]};
        character=pitch_valid ? "0"+shown_feature[63-char_index*4-:4] : "-";
        if(pitch_valid && ((char_index==0 && shown_feature[63:60]==0) || (char_index==1 && shown_feature[63:56]==0) ||
            (char_index==2 && shown_feature[63:52]==0) || (char_index==3 && shown_feature[63:48]==0))) character=" ";
    end else if(px>=288 && px<320 && py>=88 && py<102) begin
        tx=px-288;ty=py-88;font_scale=1;text_on=1;character=word_char("HZ                    ",tx[7:4]);
    end else if(px>=464 && px<592 && py>=80 && py<87) begin
        tx=px-464;ty=py-80;text_on=1;character=word_char(pitch_valid ? "FFT / L               " : "NO SIGNAL             ",tx[7:3]);
        if(pitch_valid && tx[7:3]==6) character=shown_right ? "R" : "L";
        ink=24'h91ADBD;
    end else if(px>=464 && px<592 && py>=100 && py<107) begin
        tx=px-464;ty=py-100;text_on=1;character=word_char("48K / 1024            ",tx[7:3]);ink=24'h91ADBD;
    end else if(px>=40 && px<232 && py>=144 && py<151) begin
        tx=px-40;ty=py-144;text_on=1;character=word_char("SPECTRAL HISTORY      ",tx[7:3]);ink=24'h91ADBD;
    end else if(px>=464 && px<576 && py>=144 && py<151) begin
        tx=px-464;ty=py-144;text_on=1;character=word_char("0-4.5K                ",tx[7:3]);ink=24'h91ADBD;
    end else if(px>=24 && px<56 && py>=160 && py<167) begin
        tx=px-24;ty=py-160;text_on=1;character=word_char("4.5K                  ",tx[7:3]);ink=24'h91ADBD;
    end else if(px>=24 && px<56 && py>=253 && py<260) begin
        tx=px-24;ty=py-253;text_on=1;character=word_char("1.5K                  ",tx[7:3]);ink=24'h91ADBD;
    end else if(px>=48 && px<56 && py>=344 && py<351) begin
        tx=px-48;ty=py-344;text_on=1;character="0";ink=24'h91ADBD;
    end else if(px>=64 && px<88 && py>=360 && py<367) begin
        tx=px-64;ty=py-360;text_on=1;character=word_char("OLD                   ",tx[7:3]);ink=24'h91ADBD;
    end else if(px>=520 && px<544 && py>=360 && py<367) begin
        tx=px-520;ty=py-360;text_on=1;character=word_char("NOW                   ",tx[7:3]);ink=24'h91ADBD;
    end else if(px>=40 && px<232 && py>=384 && py<391) begin
        tx=px-40;ty=py-384;text_on=1;
        character=word_char(levels_page ? (shown_lesson==3 ? "STEREO LEVEL          " : "AUDIO LEVEL           ") : "PITCH TRACE           ",tx[7:3]);ink=24'h91ADBD;
    end else if(!levels_page && px>=32 && px<56 && py>=408 && py<415) begin
        tx=px-32;ty=py-408;text_on=1;character=word_char("1K                    ",tx[7:3]);ink=24'h91ADBD;
    end else if(!levels_page && px>=32 && px<56 && py>=448 && py<455) begin
        tx=px-32;ty=py-448;text_on=1;character=word_char("100                   ",tx[7:3]);ink=24'h91ADBD;
    end else if(levels_page && py>=400 && py<407 && ((px>=80 && px<88) || (px>=352 && px<360))) begin
        tx=px>=352 ? px-352 : px-80;ty=py-400;text_on=1;character=px>=352 ? "R" : "L";ink=24'h91ADBD;
    end else if(levels_page && px>=32 && px<56 && py>=414 && py<421) begin
        tx=px-32;ty=py-414;text_on=1;character=word_char("PK                    ",tx[7:3]);ink=24'h91ADBD;
    end else if(levels_page && px>=32 && px<56 && py>=440 && py<447) begin
        tx=px-32;ty=py-440;text_on=1;character=word_char("AVG                   ",tx[7:3]);ink=24'h91ADBD;
    end
    if(text_on) case(font_scale)
        0:if(tx[2:0]<5 && ty<7 && glyph[34-(ty*5+tx[2:0])]) composed=ink;
        1:if(tx[3:1]<5 && ty[3:1]<7 && glyph[34-(ty[3:1]*5+tx[3:1])]) composed=ink;
        2:if(tx[4:2]<5 && ty[4:2]<7 && glyph[34-(ty[4:2]*5+tx[4:2])]) composed=ink;
    endcase
end
endmodule
