`timescale 1ns/1ps
module tb_nature_wav;
reg sd_clk=0,video_clk=0,rst=1,enabled=1,exit_async=0,request_async=0;
always #5 sd_clk=~sd_clk;
always #20 video_clk=~video_clk;
reg [1:0] photo_async=0;
wire ack_toggle,idle,sector_request;
wire [31:0] sector_address;
reg [7:0] sector_data=0;
reg byte_valid=0,sector_end=0,sample_tick=0;
wire [23:0] pcm;
wire underrun;
nature_wav_player dut(.*,.wav0(32'd100),.wav1(32'd200),.wav2(32'd300),.wav3(32'd400),
    .count0(32'd2048),.count1(32'd2048),.count2(32'd2048),.count3(32'd2048));
integer age=-1,byte_count=0,sector=0,divider=0,check_count=0,expected_index=0,clip=0;
reg checking=0,bad_header=0;
function automatic [7:0] header(input integer index);
    begin
        header=0;
        case(index)
            0:header="R";1:header="I";2,3:header="F";
            8:header="W";9:header="A";10:header="V";11:header="E";
            20,22:header=1;24:header=8'h80;25:header=8'hbb;34:header=16;
            504:header="d";505:header="a";506:header="t";507:header="a";
        endcase
        if(bad_header && index==24) header=0;
    end
endfunction
function automatic [15:0] value(input integer c,n);value=16'h8000+c*4096+n;endfunction
always @(negedge sd_clk) begin
    byte_valid=0;sector_end=0;
    if(!rst) begin
        if(age<0 && sector_request) begin age=0;byte_count=0;sector=sector_address;end
        else if(age>=0) begin
            age=age+1;
            if(age>=12 && age<12+512*4 && (age-12)%4==0) begin
                byte_valid=1;
                if(sector%100==0) sector_data=header(byte_count);
                else if(byte_count%2==0) sector_data=value(sector/100-1,(sector%100-1)*256+byte_count/2)&255;
                else sector_data=value(sector/100-1,(sector%100-1)*256+byte_count/2)>>8;
                byte_count=byte_count+1;
            end
            if(age==12+512*4+10) begin sector_end=1;age=-1;end
        end
    end
end
always @(negedge video_clk) begin
    sample_tick=0;
    if(!rst) begin
        divider=divider+1;
        if(divider==521) begin sample_tick=1;divider=0;end // ~48 kHz
    end
end
always @(posedge video_clk) begin
    if(!rst && sample_tick && checking) begin
        #1;
        if(pcm!=={value(clip,expected_index),8'd0})
            $fatal(1,"PCM mismatch clip%0d n%0d got%h expected%h",clip,expected_index,pcm,{value(clip,expected_index),8'd0});
        expected_index=expected_index+1;check_count=check_count+1;
    end
end
integer c;
initial begin
    repeat(8) @(negedge sd_clk);rst=0;
    for(c=0;c<4;c=c+1) begin
        photo_async=c;clip=c;expected_index=0;checking=0;
        @(negedge video_clk);request_async=~request_async;
        wait(ack_toggle==request_async);wait(dut.ready_sync[1]);checking=1;
        wait(expected_index>=600);checking=0;
    end
    if(underrun) $fatal(1,"FIFO underrun during normal real-time playback");
    // Exit while a read is in flight; ownership may release only after SD end.
    wait(sector_request);exit_async=1;wait(idle);
    repeat(16) @(negedge video_clk);
    if(dut.play_ready || sector_request) $fatal(1,"WAV player did not quiesce");
    // Unsupported format must acknowledge as muted rather than hang the page.
    exit_async=0;bad_header=1;photo_async=0;
    repeat(8) @(negedge video_clk);request_async=~request_async;
    wait(ack_toggle==request_async);repeat(16) @(negedge video_clk);
    if(dut.play_ready || pcm!==0) $fatal(1,"Bad WAV rate did not mute safely");
    $display("ALL NATURE WAV TESTS PASSED: four real PCM streams, %0d signed samples, 100/25MHz FIFO, clean exit, bad header muted/acknowledged",check_count);
    $finish;
end
initial begin #80000000;$fatal(1,"WAV timeout");end
endmodule
