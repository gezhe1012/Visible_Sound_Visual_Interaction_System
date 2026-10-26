`timescale 1ns/1ps
module tb_science_fade;
reg clk=0,rst=1,vs=0,request_toggle_async=0;
always #5 clk=~clk;
reg [1:0] request_buf_idx_async=0;
reg [2:0] request_lesson_idx_async=0;
wire [1:0] display_buf_idx;
wire [2:0] display_lesson_idx;
wire display_valid,done_toggle;
wire [4:0] fade_level;
integer page,guard;
reg old_done;
video_fade_transition dut(.*);
task frame;
    @(negedge clk); vs=0; repeat(3) @(negedge clk); vs=1; repeat(3) @(negedge clk);
endtask
initial begin
    repeat(4) @(negedge clk); rst=0;
    for(page=0;page<5;page=page+1) begin
        old_done=done_toggle;
        request_buf_idx_async=2'(page%2); request_lesson_idx_async=3'(page);
        @(negedge clk); request_toggle_async=~request_toggle_async;
        repeat(8) @(negedge clk); guard=0;
        while(done_toggle==old_done && guard<50) begin
            if(page>0 && display_lesson_idx!=page && display_lesson_idx!=page-1)
                $fatal(1,"Invalid lesson during transition");
            if(page>0 && display_lesson_idx==page && fade_level==0 && display_buf_idx!=page%2)
                $fatal(1,"Picture and lesson not committed together");
            frame(); guard=guard+1;
        end
        if(guard>=50 || display_lesson_idx!=page || display_buf_idx!=page%2 || fade_level!=16)
            $fatal(1,"Page transition did not complete");
    end
    $display("ALL SCIENCE FADE TESTS PASSED: five lessons atomically follow black-frame buffer swaps");
    $finish;
end
reg [2:0] previous_lesson=0;
always @(posedge clk) begin
    #1;
    if(!rst && display_lesson_idx!=previous_lesson && fade_level!=0)
        $fatal(1,"Lesson changed outside black frame");
    previous_lesson=display_lesson_idx;
end
endmodule
