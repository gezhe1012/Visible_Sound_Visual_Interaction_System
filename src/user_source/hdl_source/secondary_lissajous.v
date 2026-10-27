// 64x64 one-bit XY planes, two banks: 8192 bits total, no full framebuffer.
// Same-time L/R PCM pair only; signed gain 4, symmetric clipping, R positive up.
// 512 samples/plane; completed planes swap ONLY at frame_tick. Never stalls PCM.
module secondary_lissajous(
    input clk,rst,frame_tick,scene_clear,audio_stale,
    input [2:0] lesson,
    input lesson_valid,audio_valid,
    input [23:0] audio_left,audio_right,
    input [11:0] xy_read_address,
    output reg xy_q,
    output reg xy_visible
);
localparam CLEAR=0,CAPTURE=1,READY=2;
reg [1:0] state;
reg plane[0:8191];
reg front_bank,write_bank;
reg [11:0] clear_address;
reg [8:0] sample_count;
wire active=lesson_valid && lesson==3;
wire signed [7:0] left_value=audio_left[23:16],right_value=audio_right[23:16];
wire [5:0] point_x=left_value>31 ? 6'd63 : left_value< -31 ? 6'd1 : 6'd32+left_value[5:0];
wire [5:0] point_y=right_value>31 ? 6'd1 : right_value< -31 ? 6'd63 : 6'd32-right_value[5:0];
always @(posedge clk) begin
    xy_q<=plane[{front_bank,xy_read_address}];
    if(!rst && active && !scene_clear) begin
        if(state==CLEAR) plane[{write_bank,clear_address}]<=0;
        else if(state==CAPTURE && audio_valid) plane[{write_bank,point_y,point_x}]<=1;
    end
end
always @(posedge clk or posedge rst) begin
    if(rst) begin state<=CLEAR;front_bank<=0;write_bank<=1;clear_address<=0;sample_count<=0;xy_visible<=0;end
    else begin
        case(state)
            CLEAR: if(active) begin
                if(clear_address==4095) begin clear_address<=0;sample_count<=0;state<=CAPTURE;end
                else clear_address<=clear_address+12'd1;
            end
            CAPTURE: if(audio_valid && active) begin
                if(sample_count==511) state<=READY;
                else sample_count<=sample_count+9'd1;
            end
            READY: if(frame_tick) begin
                front_bank<=write_bank;write_bank<=!write_bank;xy_visible<=1;state<=CLEAR;clear_address<=0;
            end
        endcase
        if(!active) begin state<=CLEAR;write_bank<=!front_bank;clear_address<=0;sample_count<=0;end
        if(scene_clear || (frame_tick && (!active || audio_stale))) begin
            state<=CLEAR;front_bank<=0;write_bank<=1;clear_address<=0;sample_count<=0;xy_visible<=0;
        end
    end
end
endmodule
