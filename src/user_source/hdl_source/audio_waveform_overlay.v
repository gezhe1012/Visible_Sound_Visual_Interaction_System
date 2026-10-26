// Stereo oscilloscope tapped AFTER I2S_receiver, in the same video clock domain.
// 256 consecutive 24-bit PCM samples per trace; two pixels/sample (5.33 ms @48K).
// Capture/display ping-pong banks exchange ONLY at VS rising, never mid-frame.
// Two-clock RAM/render pipeline delays RGB, HS, VS and DE together.
module audio_waveform_overlay #(
    parameter integer NO_AUDIO_CYCLES=6250000 // 250ms at 25MHz
)(
    input clk,rst,hs,vs,de,
    input [23:0] rgb_in,
    input audio_valid,requested_visible,
    input [23:0] audio_left,audio_right,
    output hs_out,vs_out,de_out,
    output panel_visible,
    output reg [23:0] rgb_out
);
reg [9:0] x,y;
reg de_d,vs_d;
reg visible_frame;
assign panel_visible=visible_frame;
wire frame_tick=vs && !vs_d;
reg capture_bank,display_bank,display_valid,pending,capturing;
reg [7:0] capture_index,trigger_wait;
reg previous_negative;
reg [5:0] previous_left,previous_right;
reg [22:0] no_audio_count;
wire stale=(no_audio_count>=NO_AUDIO_CYCLES-1);

// Display gain: one vertical pixel = 65536 PCM LSBs; clip at +/-31 pixels.
// Arithmetic shift uses all 24 input bits, then saturates (no wraparound).
function [5:0] sample_level;
    input signed [23:0] sample;
    reg signed [8:0] scaled;
    begin
        scaled=sample>>>16;
        if(scaled>31) sample_level=0;
        else if(scaled< -31) sample_level=62;
        else sample_level=6'd31-scaled;
    end
endfunction
wire [5:0] left_level=sample_level($signed(audio_left));
wire [5:0] right_level=sample_level($signed(audio_right));
wire trigger=previous_negative && !audio_left[23];
wire capture_accept=audio_valid && !pending && (capturing || trigger || trigger_wait==255);
wire [23:0] capture_word={left_level,(capture_index==0 ? left_level : previous_left),
                                        right_level,(capture_index==0 ? right_level : previous_right)};

// No memory reset: two 256x24 banks infer embedded RAM. Each word stores both
// current and previous sample levels, so vertical segments need ONE read port.
reg [23:0] wave_ram [0:511];
reg [23:0] wave_q;
wire [9:0] graph_x=x-10'd64;
always @(posedge clk) begin
    wave_q<=wave_ram[{display_bank,graph_x[8:1]}];
    if(capture_accept && !rst) wave_ram[{capture_bank,capture_index}]<=capture_word;
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        x<=0; y<=0; de_d<=0; vs_d<=0; visible_frame<=0;
        capture_bank<=0; display_bank<=1; display_valid<=0;
        pending<=0; capturing<=0; capture_index<=0; trigger_wait<=0;
        previous_negative<=0; previous_left<=31; previous_right<=31;
        no_audio_count<=NO_AUDIO_CYCLES-1;
    end else begin
        de_d<=de; vs_d<=vs;
        if(frame_tick) visible_frame<=requested_visible;
        if(de) x<=x+10'd1; else x<=0;
        if(!vs) y<=0; else if(de_d && !de) y<=y+10'd1;
        if(audio_valid) no_audio_count<=0;
        else if(!stale) no_audio_count<=no_audio_count+23'd1;
        if(audio_valid) begin
            previous_negative<=audio_left[23];
            if(!pending && !capturing && !capture_accept) trigger_wait<=trigger_wait+8'd1;
        end
        if(capture_accept) begin
            previous_left<=left_level; previous_right<=right_level;
            trigger_wait<=0;
            if(capture_index==255) begin
                pending<=1; capturing<=0; capture_index<=0;
            end else begin capturing<=1; capture_index<=capture_index+8'd1; end
        end
        if(frame_tick) begin
            if(stale && !audio_valid) begin
                // Never display a frozen old trace as if the audio were live.
                display_valid<=0; pending<=0; capturing<=0;
                capture_index<=0; trigger_wait<=0;
            end else if(pending) begin
                display_bank<=capture_bank; capture_bank<=~capture_bank;
                display_valid<=1; pending<=0;
            end
        end
    end
end

reg [9:0] px,py;
reg [23:0] pixel_q;
reg valid_q,visible_q;
reg [1:0] hs_pipe,vs_pipe,de_pipe;
assign hs_out=hs_pipe[1];
assign vs_out=vs_pipe[1];
assign de_out=de_pipe[1];
always @(posedge clk or posedge rst) begin
    if(rst) begin
        px<=0; py<=0; pixel_q<=0; valid_q<=0; visible_q<=0;
        hs_pipe<=0; vs_pipe<=0; de_pipe<=0;
    end else begin
        px<=x; py<=y; pixel_q<=rgb_in; valid_q<=display_valid;
        visible_q<=visible_frame;
        hs_pipe<={hs_pipe[0],hs}; vs_pipe<={vs_pipe[0],vs}; de_pipe<={de_pipe[0],de};
    end
end
function between;
    input [9:0] position;
    input [5:0] a,b;
    begin between=(a<=b) ? (position>=a && position<=b) : (position>=b && position<=a); end
endfunction
function [4:0] channel_glyph;
    input right_channel;
    input [2:0] row;
    begin
        if(!right_channel) channel_glyph=(row==6) ? 5'b11111 : 5'b10000; // L
        else case(row) // R
            0,3: channel_glyph=5'b11110;
            1,2,6: channel_glyph=5'b10001;
            4: channel_glyph=5'b10100;
            default: channel_glyph=5'b10010;
        endcase
    end
endfunction
reg [23:0] composed;
reg [4:0] label_bits;
reg [9:0] label_x,label_y,left_y,right_y;
always @* begin
    composed=pixel_q;
    label_bits=0; label_x=px-10'd52;
    label_y=0; left_y=py-10'd255; right_y=py-10'd339;
    if(visible_q && px>=48 && px<592 && py>=238 && py<416) begin
        // Alpha=12/16 black background, independently of picture BRI/CON.
        composed={2'b0,pixel_q[23:18],2'b0,pixel_q[15:10],2'b0,pixel_q[7:2]};
        if(px==48 || px==591 || py==238 || py==415) composed=24'h60849A;
        if(px>=64 && px<576 && py>=255 && py<=401) begin
            if(px[5:0]==0 || py==255 || py==286 || py==317 || py==339 || py==370 || py==401)
                composed=24'h294052;
            if(valid_q && py>=255 && py<=317 && between(left_y,wave_q[23:18],wave_q[17:12]))
                composed=24'h52E3FF;
            if(valid_q && py>=339 && py<=401 && between(right_y,wave_q[11:6],wave_q[5:0]))
                composed=24'hFFE66D;
        end
        if(px>=52 && px<62) begin
            if(py>=279 && py<293) begin
                label_y=py-10'd279; label_bits=channel_glyph(0,label_y[3:1]);
                if(label_bits[4-label_x[3:1]]) composed=valid_q ? 24'h52E3FF : 24'hE07070;
            end else if(py>=363 && py<377) begin
                label_y=py-10'd363; label_bits=channel_glyph(1,label_y[3:1]);
                if(label_bits[4-label_x[3:1]]) composed=valid_q ? 24'hFFE66D : 24'hE07070;
            end
        end
    end
end
always @(posedge clk or posedge rst) begin
    if(rst) rgb_out<=0;
    else rgb_out<=de_pipe[0] ? composed : 24'd0;
end
endmodule
