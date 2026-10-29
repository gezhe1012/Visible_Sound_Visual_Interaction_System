// Standard I2S master/capture in the EXISTING 25MHz video domain.
// 6.144M edge enables/s -> 3.072MHz SCK average, exactly 64 SCK/WS frame.
// SCK half periods 160/200ns; full periods 320/360ns (INMP441 min 312ns).
// No generated fabric clock, new PLL, RAM, or audio/video CDC.
module inmp441_i2s_rx #(
    parameter integer CLOCK_HZ=25000000,
    parameter integer SAMPLE_HZ=48000,
    parameter integer STARTUP_FRAMES=4096
)(
    input clk,rst,mic_sd,
    output reg mic_sck,mic_ws,
    output reg signed [23:0] mic_pcm,
    output reg mic_valid,
    output ready
);
reg [24:0] phase;
wire [25:0] phase_sum={1'b0,phase}+SAMPLE_HZ*128;
wire edge_enable=phase_sum>=CLOCK_HZ;
reg [5:0] slot;
reg [23:0] shift;
reg [12:0] startup;
// External SD only enters this two-register sampling chain. The first D pin
// has a targeted asynchronous-input exception; both stages remain timed.
reg sd_meta,sd_sync;
assign ready=startup==0;
always @(posedge clk or posedge rst) begin
    if(rst) begin sd_meta<=0;sd_sync<=0;end
    else begin sd_meta<=mic_sd;sd_sync<=sd_meta;end
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        phase<=0;slot<=0;shift<=0;startup<=STARTUP_FRAMES;
        mic_sck<=0;mic_ws<=0;mic_pcm<=0;mic_valid<=0;
    end else begin
        phase<=edge_enable ? phase_sum-CLOCK_HZ : phase_sum[24:0];
        mic_valid<=0;
        if(edge_enable) begin
            mic_sck<=~mic_sck;
            if(!mic_sck) begin
                // Slot zero is the mandatory one-SCK I2S delay after WS.
                if(slot>=1 && slot<=24) begin
                    shift<={shift[22:0],sd_sync};
                    if(slot==24 && ready) begin mic_pcm<={shift[22:0],sd_sync};mic_valid<=1;end
                end
                if(slot==63 && startup!=0) startup<=startup-13'd1;
            end else begin
                slot<=slot+6'd1;
                if(slot==31) mic_ws<=1;
                if(slot==63) mic_ws<=0;
            end
        end
    end
end
endmodule
