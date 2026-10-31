// Real TF-resident RIFF/PCM playback, 48 kHz mono signed 16-bit -> stereo 24-bit.
// The exporter places the RIFF header in one sector and PCM on the next sector.
// Only this optional scene uses the FIFO; original I2S/ACR timing remains intact.
module nature_wav_player(
    input sd_clk,video_clk,rst,enabled,exit_async,
    input request_async,input [1:0] photo_async,
    input [31:0] wav0,wav1,wav2,wav3,count0,count1,count2,count3,
    output reg ack_toggle,
    output idle,
    output reg sector_request,output reg [31:0] sector_address,
    input [7:0] sector_data,input byte_valid,sector_end,
    input sample_tick,
    output reg [23:0] pcm,
    output reg underrun
);
reg [2:0] req_sync,exit_sync;
reg [1:0] photo0,photo1;
reg [2:0] state;
reg current_request;
reg [31:0] remaining;
reg [9:0] byte_index;
reg [7:0] low_byte;
reg fifo_clear,write_enable,play_ready;
reg [15:0] write_data;
wire [15:0] fifo_data;
wire full,empty;
wire [8:0] used;
reg [1:0] ready_sync;
reg [31:0] riff_magic,wave_magic,rate,data_magic;
reg [15:0] format,channels,bits;
reg [31:0] watchdog;
reg [1:0] payload_wait;
wire pending=req_sync[2]!=current_request;
wire stop=exit_sync[2] || !enabled;
wire pop=sample_tick && ready_sync[1] && !empty;
assign idle=state==0 && !sector_request;
wfifo_32_32_512 #(.DATA_WIDTH_W(16),.DATA_WIDTH_R(16)) pcm_fifo(
    .rst(rst|fifo_clear),.clkw(sd_clk),.clkr(video_clk),.we(write_enable),.di(write_data),
    .re(pop),.dout(fifo_data),.full_flag(full),.empty_flag(empty),.wrusedw(used),.rdusedw()
);
always @(posedge video_clk or posedge rst) begin
    if(rst) begin ready_sync<=0;pcm<=0;underrun<=0;end
    else begin
        ready_sync<={ready_sync[0],play_ready};
        if(sample_tick) begin
            pcm<=pop ? {fifo_data,8'd0} : 24'd0;
            if(ready_sync[1] && empty) underrun<=1;
        end
    end
end
always @(posedge sd_clk or posedge rst) begin
    if(rst) begin
        req_sync<=0;exit_sync<=0;photo0<=0;photo1<=0;state<=0;current_request<=0;
        ack_toggle<=0;sector_request<=0;sector_address<=0;remaining<=0;byte_index<=0;low_byte<=0;
        fifo_clear<=1;write_enable<=0;write_data<=0;play_ready<=0;
        riff_magic<=0;wave_magic<=0;rate<=0;data_magic<=0;format<=0;channels<=0;bits<=0;watchdog<=0;payload_wait<=0;
    end else begin
        req_sync<={req_sync[1:0],request_async};exit_sync<={exit_sync[1:0],exit_async};
        photo0<=photo_async;photo1<=photo0;write_enable<=0;
        if(state==0 || byte_valid || sector_end) watchdog<=0;
        else watchdog<=watchdog+1'b1;
        case(state)
            0:begin
                sector_request<=0;
                if(enabled && !stop && pending) begin
                    current_request<=req_sync[2];play_ready<=0;fifo_clear<=1;byte_index<=0;
                    riff_magic<=0;wave_magic<=0;rate<=0;data_magic<=0;format<=0;channels<=0;bits<=0;
                    payload_wait<=0;state<=6;
                end
                if(stop) begin play_ready<=0;fifo_clear<=1;end
            end
            1:begin sector_request<=1;state<=2;end
            2:begin
                if(byte_valid) begin
                    byte_index<=byte_index+1'b1;
                    if(byte_index<4) riff_magic[byte_index*8+:8]<=sector_data;
                    if(byte_index>=8 && byte_index<12) wave_magic[(byte_index-8)*8+:8]<=sector_data;
                    if(byte_index>=20 && byte_index<22) format[(byte_index-20)*8+:8]<=sector_data;
                    if(byte_index>=22 && byte_index<24) channels[(byte_index-22)*8+:8]<=sector_data;
                    if(byte_index>=24 && byte_index<28) rate[(byte_index-24)*8+:8]<=sector_data;
                    if(byte_index>=34 && byte_index<36) bits[(byte_index-34)*8+:8]<=sector_data;
                    if(byte_index>=504 && byte_index<508) data_magic[(byte_index-504)*8+:8]<=sector_data;
                end
                if(sector_end) begin sector_request<=0;state<=3;end
            end
            3:begin
                if(stop || pending) state<=0;
                else if(riff_magic==32'h46464952 && wave_magic==32'h45564157 &&
                        format==1 && channels==1 && rate==48000 && bits==16 && data_magic==32'h61746164) begin
                    fifo_clear<=0;sector_address<=sector_address+1'b1;byte_index<=0;state<=4;
                end else begin
                    // Invalid/missing audio mutes, but never blocks photo playback.
                    ack_toggle<=current_request;state<=0;
                end
            end
            4:begin
                if(stop || pending) begin play_ready<=0;state<=0;end
                else if(remaining!=0 && used<=240 && !full) begin sector_request<=1;byte_index<=0;state<=5;end
                if(!play_ready && used>=256) begin play_ready<=1;ack_toggle<=current_request;end
            end
            5:begin
                if(byte_valid) begin
                    byte_index<=byte_index+1'b1;
                    if(!byte_index[0]) low_byte<=sector_data;
                    else if(remaining!=0) begin
                        write_data<={sector_data,low_byte};write_enable<=!full;remaining<=remaining-1'b1;
                    end
                end
                if(sector_end) begin sector_request<=0;sector_address<=sector_address+1'b1;state<=4;end
            end
            6:begin
                // Bundled two-bit photo ID is held until ack. Allow three
                // additional SD clocks after the synchronized request so every
                // bit has settled even with the bounded first-stage CDC delay.
                if(stop) state<=0;
                else if(payload_wait==2) begin
                    case(photo1)
                        0:begin sector_address<=wav0;remaining<=count0;end
                        1:begin sector_address<=wav1;remaining<=count1;end
                        2:begin sector_address<=wav2;remaining<=count2;end
                        3:begin sector_address<=wav3;remaining<=count3;end
                    endcase
                    state<=1;
                end else payload_wait<=payload_wait+1'b1;
            end
            default:state<=0;
        endcase
        if(watchdog[28]) begin sector_request<=0;play_ready<=0;ack_toggle<=current_request;state<=0;end
    end
end
endmodule
