`timescale 1ns/1ps
// Actual lesson WAV PCM -> actual FPGA FFT -> independent expected features.
// Capture/VS stimuli are accelerated for regression, NOT a wall-clock demo.
module tb_secondary_audio_preview;
reg clk=0,rst=1,lesson_valid=1,audio_valid=0;
always #20 clk=~clk;
reg [2:0] lesson=0;
reg [23:0] audio_left=0,audio_right=0;
wire capture_start,bin_valid,bin_channel,spectrum_write,result_done;
wire [8:0] bin_number;
wire [16:0] bin_magnitude;
wire [7:0] spectrum_address;
wire [6:0] spectrum_height;
reg result_ack=0;
always @(posedge clk) result_ack<=!rst && result_done; // never driven by the secondary
audio_fft1024 fft(.*);
wire render_tick,render_clear,shown_right;
reg fill_mode=1,manual_tick=0;
wire frame_tick=fill_mode ? manual_tick : render_tick;
wire scene_clear=fill_mode ? 1'b0 : render_clear;
wire [6:0] read_column,shown_head,shown_count;
wire [5:0] read_band;
wire [3:0] heat_q;
wire [7:0] trace_q,peak_left,peak_right,average_left,average_right;
wire [79:0] shown_feature;
secondary_feature_store features(.*);
wire axis_user,axis_valid,axis_last;
wire [23:0] axis_data;
secondary_audio_renderer renderer(.video_locked(1'b1),.frame_tick(render_tick),.scene_clear(render_clear),.*);
reg [47:0] pcm[0:491519];
reg [3:0] expected_heat[0:30719];
reg [79:0] expected_feature[0:479];
reg [31:0] expected_level[0:479];
integer page,column,i,band,fp,pixels,lines,starts,stream_x;
integer heat_checks=0,feature_checks=0;
reg recording=0,saw_start=0;
always @(posedge clk) begin
    #1;
    if(recording && axis_valid && (saw_start || axis_user)) begin
        saw_start=1;
        if(axis_user) starts=starts+1;
        if(axis_last!==(stream_x==639)) $fatal(1,"Secondary preview TLAST alignment wrong");
        if(axis_last) begin lines=lines+1;stream_x=0;end else stream_x=stream_x+1;
        $fwrite(fp,"%c%c%c",axis_data[23:16],axis_data[15:8],axis_data[7:0]);pixels=pixels+1;
        if(pixels==307200) recording=0;
    end
end
initial begin
    $readmemh("secondary_audio_pcm.hex",pcm);$readmemh("secondary_audio_heat.hex",expected_heat);
    $readmemh("secondary_audio_feature.hex",expected_feature);$readmemh("secondary_audio_level.hex",expected_level);
    for(page=0;page<5;page=page+1) begin
        rst=1;lesson=3'(page);fill_mode=1;manual_tick=0;
        repeat(5) @(negedge clk);rst=0;repeat(5) @(negedge clk);
        for(column=0;column<96;column=column+1) begin
            for(i=0;i<1024;i=i+1) begin
                @(negedge clk);audio_valid=1;{audio_left,audio_right}=pcm[(page*96+column)*1024+i];
                @(negedge clk);audio_valid=0;repeat(2) @(negedge clk);
            end
            wait(features.pending);@(negedge clk);manual_tick=1;@(negedge clk);manual_tick=0;repeat(2) @(negedge clk);
            if(shown_feature!==expected_feature[page*96+column]) $fatal(1,"Real FFT feature mismatch page%0d col%0d got%h expected%h",page,column,shown_feature,expected_feature[page*96+column]);
            if({peak_left,peak_right,average_left,average_right}!==expected_level[page*96+column]) $fatal(1,"Real PCM peak/mean mismatch");
            if(shown_count!==7'(column+1)) $fatal(1,"History count mismatch");
            for(band=0;band<64;band=band+1) begin
                if(features.heat_ram[column*64+band]!==expected_heat[(page*96+column)*64+band]) $fatal(1,"Real FFT waterfall mismatch page%0d col%0d band%0d",page,column,band);
                heat_checks=heat_checks+1;
            end
            feature_checks=feature_checks+1;
        end
        @(negedge clk);fill_mode=0;
        wait(render_tick);@(negedge clk);
        fp=$fopen($sformatf("secondary_audio_page_%0d.ppm",page),"wb");$fwrite(fp,"P6\n640 480\n255\n");
        pixels=0;lines=0;starts=0;stream_x=0;saw_start=0;recording=1;
        wait(!recording);$fclose(fp);
        if(lines!=480 || starts!=1) $fatal(1,"Incomplete secondary raster");
        $display("PASS secondary audio page%0d: 96 real FFT columns, 307200 actual RGB pixels",page);
    end
    $display("ALL SECONDARY AUDIO PREVIEW TESTS PASSED: %0d real lesson FFT cells, %0d 80-bit features, PCM levels, 1536000 RGB pixels, 2400 TLAST, 5 SOF",heat_checks,feature_checks);
    $finish;
end
initial begin #4000000000;$fatal(1,"Secondary FFT preview timeout");end
endmodule
