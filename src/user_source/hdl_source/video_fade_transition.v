// Frame-boundary fade controller for the double-buffered BMP player.
//
// A new image is written completely into the inactive SDRAM buffer before
// request_toggle changes.  This module then fades the current frame to black,
// changes the read buffer while the screen is black, waits for the read FIFO
// to refill, and fades the new frame in.  The handshake crosses between the
// SD-card clock domain and the video clock domain with toggle synchronizers.
module video_fade_transition #(
    parameter integer FADE_FRAMES       = 16,
    parameter integer BLACK_HOLD_FRAMES = 2
)(
    input             clk,
    input             rst,
    input             vs,

    input             request_toggle_async,
    input      [1:0]  request_buf_idx_async,
    input      [2:0]  request_lesson_idx_async,

    output reg [1:0]  display_buf_idx,
    output reg [2:0]  display_lesson_idx,
    output reg        display_valid,
    output reg [4:0]  fade_level,       // 0 = black, 16 = full brightness
    output reg        done_toggle
);

localparam [2:0] ST_IDLE       = 3'd0;
localparam [2:0] ST_FADE_OUT   = 3'd1;
localparam [2:0] ST_BLACK_HOLD = 3'd2;
localparam [2:0] ST_FADE_IN    = 3'd3;

reg [2:0] state;
reg [1:0] target_buf_idx;
reg [2:0] target_lesson_idx;
reg [2:0] request_lesson_sync0,request_lesson_sync1;
reg [3:0] black_hold_count;

reg       vs_d;
wire      frame_tick;

reg [2:0] request_toggle_sync;
reg [1:0] request_buf_sync0;
reg [1:0] request_buf_sync1;
reg       request_toggle_seen;
wire      request_pulse;

assign frame_tick   = vs & ~vs_d;  // end of the active-low VS pulse
assign request_pulse = request_toggle_sync[2] ^ request_toggle_seen;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        vs_d                <= 1'b0;
        request_toggle_sync <= 3'b000;
        request_buf_sync0   <= 2'b00;
        request_buf_sync1   <= 2'b00;
        request_lesson_sync0<=0; request_lesson_sync1<=0;
    end else begin
        vs_d                <= vs;
        request_toggle_sync <= {request_toggle_sync[1:0], request_toggle_async};
        request_buf_sync0   <= request_buf_idx_async;
        request_buf_sync1   <= request_buf_sync0;
        request_lesson_sync0<=request_lesson_idx_async;
        request_lesson_sync1<=request_lesson_sync0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state               <= ST_IDLE;
        target_buf_idx      <= 2'd0;
        target_lesson_idx<=0; display_lesson_idx<=0;
        display_buf_idx     <= 2'd0;
        display_valid       <= 1'b0;
        fade_level          <= 5'd0;
        black_hold_count    <= 4'd0;
        done_toggle         <= 1'b0;
        request_toggle_seen <= 1'b0;
    end else begin
        if (request_pulse) begin
            request_toggle_seen <= request_toggle_sync[2];
            target_buf_idx      <= request_buf_sync1;
            target_lesson_idx<=request_lesson_sync1;

            if (!display_valid) begin
                // First image: select it while black, then perform a fade-in.
                display_buf_idx  <= request_buf_sync1;
                display_lesson_idx<=request_lesson_sync1;
                display_valid    <= 1'b1;
                fade_level       <= 5'd0;
                black_hold_count <= 4'd0;
                state            <= ST_BLACK_HOLD;
            end else if (state == ST_IDLE) begin
                state <= ST_FADE_OUT;
            end
        end

        if (frame_tick) begin
            case (state)
                ST_IDLE: begin
                    if (display_valid)
                        fade_level <= 5'd16;
                end

                ST_FADE_OUT: begin
                    if (fade_level > 5'd1) begin
                        fade_level <= fade_level - 5'd1;
                    end else begin
                        fade_level       <= 5'd0;
                        display_buf_idx  <= target_buf_idx;
                        display_lesson_idx<=target_lesson_idx;
                        black_hold_count <= 4'd0;
                        state            <= ST_BLACK_HOLD;
                    end
                end

                ST_BLACK_HOLD: begin
                    fade_level <= 5'd0;
                    if (black_hold_count >= BLACK_HOLD_FRAMES - 1) begin
                        black_hold_count <= 4'd0;
                        state            <= ST_FADE_IN;
                    end else begin
                        black_hold_count <= black_hold_count + 4'd1;
                    end
                end

                ST_FADE_IN: begin
                    if (fade_level < FADE_FRAMES - 1) begin
                        fade_level <= fade_level + 5'd1;
                    end else begin
                        fade_level  <= 5'd16;
                        state       <= ST_IDLE;
                        done_toggle <= ~done_toggle;
                    end
                end

                default: begin
                    state      <= ST_IDLE;
                    fade_level <= 5'd0;
                end
            endcase
        end
    end
end

endmodule
