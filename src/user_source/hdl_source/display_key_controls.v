// Reuse the two constrained board keys; all logic runs in video_clk.
// Short release: next / autoplay. Long hold: brightness / contrast.
// Holding both keys restores neutral parameters and suppresses short actions.
module display_key_controls #(
    parameter integer CLK_HZ=25_000_000,
    parameter integer DEBOUNCE_MS=20,
    parameter integer HOLD_MS=800,
    parameter integer REPEAT_MS=400,
    parameter integer INDICATOR_MS=2000
)(
    input clk,rst,vs,key1,key2,
    output reg next_toggle,auto_toggle,
    output reg signed [8:0] brightness,
    output reg [2:0] contrast_q2, // 2..6 = 50%,75%,100%,125%,150%
    output reg [1:0] active_control // 0 idle, 1 BRI, 2 CON, 3 reset
);
localparam integer MS_CYCLES=CLK_HZ/1000;
reg [15:0] ms_div;
wire ms_tick=(ms_div==MS_CYCLES-1);
reg [1:0] key1_sync,key2_sync;
reg key1_stable,key2_stable,key1_previous,key2_previous;
reg [7:0] debounce1,debounce2;
reg [15:0] hold1,hold2,repeat1,repeat2,chord_count,indicator_count;
reg used1,used2,chord_seen,chord_done;
reg signed [8:0] requested_brightness;
reg [2:0] requested_contrast;
reg [1:0] last_control;
reg vs_d;

always @(posedge clk or posedge rst) begin
    if(rst) begin ms_div<=0; key1_sync<=3; key2_sync<=3; vs_d<=0; end
    else begin
        if(ms_tick) ms_div<=0; else ms_div<=ms_div+16'd1;
        key1_sync<={key1_sync[0],key1};
        key2_sync<={key2_sync[0],key2};
        vs_d<=vs;
    end
end
// A single snapshot supplies BOTH the pixel processor and OSD for each frame.
always @(posedge clk or posedge rst) begin
    if(rst) begin brightness<=0; contrast_q2<=4; active_control<=0; end
    else if(vs && !vs_d) begin
        brightness<=requested_brightness;
        contrast_q2<=requested_contrast;
        active_control<=(indicator_count!=0) ? last_control : 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        key1_stable<=1; key2_stable<=1; key1_previous<=1; key2_previous<=1;
        debounce1<=0; debounce2<=0; hold1<=0; hold2<=0;
        repeat1<=0; repeat2<=0; chord_count<=0; indicator_count<=0;
        used1<=0; used2<=0; chord_seen<=0; chord_done<=0;
        requested_brightness<=0; requested_contrast<=4; last_control<=0;
        next_toggle<=0; auto_toggle<=0;
    end else if(ms_tick) begin
        key1_previous<=key1_stable; key2_previous<=key2_stable;
        if(key1_sync[1]==key1_stable) debounce1<=0;
        else if(debounce1>=DEBOUNCE_MS-1) begin
            key1_stable<=key1_sync[1]; debounce1<=0;
        end else debounce1<=debounce1+8'd1;
        if(key2_sync[1]==key2_stable) debounce2<=0;
        else if(debounce2>=DEBOUNCE_MS-1) begin
            key2_stable<=key2_sync[1]; debounce2<=0;
        end else debounce2<=debounce2+8'd1;
        if(indicator_count!=0) indicator_count<=indicator_count-16'd1;

        if(!key1_stable && !key2_stable) begin
            chord_seen<=1; used1<=1; used2<=1;
            hold1<=0; hold2<=0; repeat1<=0; repeat2<=0;
            if(!chord_done) begin
                if(chord_count>=HOLD_MS-1) begin
                    requested_brightness<=0; requested_contrast<=4;
                    last_control<=3; indicator_count<=INDICATOR_MS;
                    chord_done<=1;
                end else chord_count<=chord_count+16'd1;
            end
        end else if(chord_seen) begin
            // Suppress all single-key actions until BOTH keys are released.
            if(key1_stable && key2_stable) begin
                chord_seen<=0; chord_done<=0; chord_count<=0;
                used1<=0; used2<=0;
            end
        end else begin
            chord_count<=0; chord_done<=0;
            if(!key1_stable) begin
                if(hold1<HOLD_MS) hold1<=hold1+16'd1;
                if((!used1 && hold1>=HOLD_MS-1) || (used1 && repeat1>=REPEAT_MS-1)) begin
                    requested_brightness<=(requested_brightness>=9'sd64) ? -9'sd64 : requested_brightness+9'sd16;
                    used1<=1; repeat1<=0; last_control<=1; indicator_count<=INDICATOR_MS;
                end else if(used1) repeat1<=repeat1+16'd1;
            end else begin
                if(!key1_previous && !used1) next_toggle<=~next_toggle;
                hold1<=0; repeat1<=0; used1<=0;
            end
            if(!key2_stable) begin
                if(hold2<HOLD_MS) hold2<=hold2+16'd1;
                if((!used2 && hold2>=HOLD_MS-1) || (used2 && repeat2>=REPEAT_MS-1)) begin
                    requested_contrast<=(requested_contrast>=6) ? 3'd2 : requested_contrast+3'd1;
                    used2<=1; repeat2<=0; last_control<=2; indicator_count<=INDICATOR_MS;
                end else if(used2) repeat2<=repeat2+16'd1;
            end else begin
                if(!key2_previous && !used2) auto_toggle<=~auto_toggle;
                hold2<=0; repeat2<=0; used2<=0;
            end
        end
    end
end
endmodule
