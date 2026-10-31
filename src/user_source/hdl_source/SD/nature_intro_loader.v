// Own the existing BMP reader and SD port only during startup. Preload all four
// SDRAM banks before playback, then leave the bus exclusively to WAV streaming.
// The original five-file scanner runs unmodified after a clean bus handoff.
module nature_intro_loader #(
    parameter ENABLE=0
)(
    input clk,rst,initialized,reader_ready,load_error,
    input scan_done,found_valid,
    input [31:0] found_sector,wav_offset,samples,
    input [1:0] found_photo,
    input write_finish_toggle,exit_async,autoplay_async,
    input wav_idle,
    output reg owner,assets_ready,
    output reg scan_start,load_start,
    output reg [31:0] load_sector,
    output reg [1:0] write_bank,
    output reg [31:0] wav0,wav1,wav2,wav3,
    output reg [31:0] count0,count1,count2,count3,
    output reg initial_auto
);
reg [2:0] state;
reg [3:0] found;
reg [31:0] sector0,sector1,sector2,sector3;
reg [2:0] wr_sync,exit_sync,auto_sync;
reg source_started,source_done,memory_done;
wire wr_done=wr_sync[2]^wr_sync[1];
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=0;found<=0;owner<=ENABLE!=0;assets_ready<=0;scan_start<=0;load_start<=0;load_sector<=0;write_bank<=0;
        sector0<=0;sector1<=0;sector2<=0;sector3<=0;wav0<=0;wav1<=0;wav2<=0;wav3<=0;
        count0<=0;count1<=0;count2<=0;count3<=0;wr_sync<=0;exit_sync<=0;auto_sync<=0;
        source_started<=0;source_done<=0;memory_done<=0;initial_auto<=0;
    end else begin
        wr_sync<={wr_sync[1:0],write_finish_toggle};exit_sync<={exit_sync[1:0],exit_async};
        auto_sync<={auto_sync[1:0],autoplay_async};scan_start<=0;load_start<=0;
        if(owner) case(state)
            0:if(initialized && reader_ready) begin scan_start<=1;state<=1;end
            1:begin
                // Version-1 package: fixed canvas + one padded header + 8s PCM.
                // Reject corrupted offsets instead of seeking arbitrary sectors.
                if(found_valid && wav_offset==1801 && samples==384000) begin
                    found[found_photo]<=1;
                    case(found_photo)
                        0:begin sector0<=found_sector;wav0<=found_sector+wav_offset;count0<=samples;end
                        1:begin sector1<=found_sector;wav1<=found_sector+wav_offset;count1<=samples;end
                        2:begin sector2<=found_sector;wav2<=found_sector+wav_offset;count2<=samples;end
                        3:begin sector3<=found_sector;wav3<=found_sector+wav_offset;count3<=samples;end
                    endcase
                end
                if(scan_done && reader_ready && !found_valid) begin
                    if(found==15) begin write_bank<=0;state<=2;end
                    else begin owner<=0;state<=7;end // old TF cards still boot normally
                end
                if(load_error) begin owner<=0;state<=7;end
            end
            2:if(reader_ready) begin
                case(write_bank)
                    0:load_sector<=sector0;1:load_sector<=sector1;2:load_sector<=sector2;3:load_sector<=sector3;
                endcase
                load_start<=1;source_started<=0;source_done<=0;memory_done<=0;state<=3;
            end
            3:begin
                if(!reader_ready) source_started<=1;
                if(source_started && reader_ready) source_done<=1;
                if(wr_done) memory_done<=1;
                if(source_done && memory_done) begin
                    if(write_bank==3) begin assets_ready<=1;state<=4;end
                    else begin write_bank<=write_bank+1'b1;state<=2;end
                end
                if(load_error) begin owner<=0;state<=7;end
            end
            4:if(exit_sync[2] && wav_idle) begin
                owner<=0;assets_ready<=0;initial_auto<=auto_sync[2];state<=7;
            end
            default:;
        endcase
    end
end
endmodule
