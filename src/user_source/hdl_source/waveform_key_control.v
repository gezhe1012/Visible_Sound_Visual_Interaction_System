// Board KEY3 only. Active low, two-flop synchronization, 20ms debounce.
// Each stable press toggles once; holding/release never retrigger.
// The overlay snapshots requested_visible at VS, so no mid-frame gating.
module waveform_key_control #(
    parameter integer CLK_HZ=25_000_000,
    parameter integer DEBOUNCE_MS=20
)(
    input clk,rst,key3,
    output reg requested_visible
);
localparam integer DEBOUNCE_CYCLES=(CLK_HZ/1000)*DEBOUNCE_MS;
reg [1:0] key_sync;
reg key_stable;
reg [31:0] debounce_count;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        key_sync<=2'b11; key_stable<=1;
        debounce_count<=0; requested_visible<=0;
    end else begin
        key_sync<={key_sync[0],key3};
        if(key_sync[1]==key_stable) debounce_count<=0;
        else if(debounce_count>=DEBOUNCE_CYCLES-1) begin
            key_stable<=key_sync[1]; debounce_count<=0;
            if(key_stable && !key_sync[1]) requested_visible<=~requested_visible;
        end else debounce_count<=debounce_count+32'd1;
    end
end
endmodule
