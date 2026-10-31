// Startup-only scene. Original teaching-page indices and controls are untouched.
// All visible state changes occur at VS; KEY3 held across handoff is quarantined
// until a debounced release, so the last photo press cannot open the FFT panel.
module nature_intro_controls #(
    parameter CLK_HZ=25000000, DEBOUNCE_MS=20, PHOTO_FRAMES=480
)(
    input clk,rst,vs,key3,next_toggle,auto_toggle,
    input assets_ready_async,owner_async,audio_ack_async,teaching_valid,
    output reg active,visible,exit_request,
    output reg [1:0] photo,
    output reg [5:0] slide,
    output reg audio_request,
    output reg [1:0] audio_photo,
    output reg autoplay,
    output reg teaching_next,teaching_auto,
    output teaching_key3
);
localparam DB=(CLK_HZ/1000)*DEBOUNCE_MS;
reg [1:0] key_sync,ready_sync,owner_sync,ack_sync;
reg key_stable,vs_d,next_d,auto_d,armed,waiting,started,next_pending;
reg [31:0] debounce_count;
reg [15:0] dwell;
wire frame_tick=vs && !vs_d;
wire press=key_sync[1]!=key_stable && debounce_count>=DB-1 && !key_sync[1];
assign teaching_key3=(!active && armed) ? key_sync[1] : 1'b1;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        key_sync<=3;ready_sync<=0;owner_sync<=3;ack_sync<=0;
        key_stable<=1;debounce_count<=0;vs_d<=0;next_d<=0;auto_d<=0;
        active<=1;visible<=0;exit_request<=0;photo<=0;slide<=32;
        audio_request<=0;audio_photo<=0;autoplay<=0;teaching_next<=0;teaching_auto<=0;
        armed<=0;waiting<=0;started<=0;next_pending<=0;dwell<=0;
    end else begin
        key_sync<={key_sync[0],key3};ready_sync<={ready_sync[0],assets_ready_async};
        owner_sync<={owner_sync[0],owner_async};ack_sync<={ack_sync[0],audio_ack_async};
        vs_d<=vs;next_d<=next_toggle;auto_d<=auto_toggle;
        if(key_sync[1]==key_stable) debounce_count<=0;
        else if(debounce_count>=DB-1) begin key_stable<=key_sync[1];debounce_count<=0;end
        else debounce_count<=debounce_count+1'b1;
        if(active) begin
            armed<=0;
            if(!exit_request && started && (press || next_toggle!=next_d)) next_pending<=1;
            if(!exit_request && auto_toggle!=auto_d) begin autoplay<=~autoplay;dwell<=0;end
            if(frame_tick) begin
                if(!owner_sync[1]) begin visible<=0;exit_request<=1;end
                if(!exit_request && ready_sync[1] && !started) begin
                    started<=1;waiting<=1;audio_photo<=0;audio_request<=~audio_request;
                end
                if(waiting && ack_sync[1]==audio_request) begin
                    waiting<=0;visible<=1;photo<=audio_photo;slide<=audio_photo==0 ? 32 : 0;dwell<=0;
                end
                if(visible && !waiting && slide<32) slide<=slide+1'b1;
                if(visible && !waiting && slide==32 && !exit_request) begin
                    if(!autoplay) dwell<=0;
                    else if(dwell<PHOTO_FRAMES-1) dwell<=dwell+1'b1;
                    if(next_pending || (autoplay && auto_toggle==auto_d && dwell>=PHOTO_FRAMES-1)) begin
                        next_pending<=0;dwell<=0;
                        if(photo==3) begin exit_request<=1;visible<=0;end
                        else begin audio_photo<=photo+1'b1;audio_request<=~audio_request;waiting<=1;end
                    end
                end
                if(exit_request && teaching_valid) begin active<=0;visible<=0;next_pending<=0;end
            end
        end else begin
            // Preserve original key-event timing, short/long/chord processing.
            if(next_toggle!=next_d) teaching_next<=~teaching_next;
            if(auto_toggle!=auto_d) teaching_auto<=~teaching_auto;
            if(key_stable && key_sync[1]) armed<=1;
        end
    end
end
endmodule
