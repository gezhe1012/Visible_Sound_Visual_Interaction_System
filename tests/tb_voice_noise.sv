`timescale 1ns/1ps
// Valid-sample accelerated functional test; physical milliseconds below are
// sample counts / 48kHz, not the accelerated simulation clock duration.
module tb_voice_noise;
reg clk=0,rst=1,mic_valid=0,dds_valid=1;
always #20 clk=~clk;
reg [2:0] lesson=5;
reg signed [23:0] mic_pcm=0;
wire analysis_valid,source_clear,active,clipped;
wire [23:0] analysis_left,analysis_right;
wire [3:0] gain_shift;
voice_analysis_source dut(.lesson_valid(1'b1),.dds_left(24'h123456),.dds_right(24'hfedcba),.*);
wire baseline_valid,baseline_clear,baseline_active,baseline_clipped;
wire [23:0] baseline_left,baseline_right;
wire [3:0] baseline_gain;
voice_baseline_conditioner baseline(.clk(clk),.rst(rst),.lesson(lesson),.lesson_valid(1'b1),
    .dds_valid(dds_valid),.dds_left(24'h123456),.dds_right(24'hfedcba),.mic_valid(mic_valid),.mic_pcm(mic_pcm),
    .analysis_valid(baseline_valid),.analysis_left(baseline_left),.analysis_right(baseline_right),
    .source_clear(baseline_clear),.active(baseline_active),.clipped(baseline_clipped),.gain_shift(baseline_gain));
reg [31:0] rng=32'h39a72e51;
integer i,n=0,noise_word,baseline_leaks=0,new_leaks=0,first_voice=-1,voice_peak=0,tail_nonzero=0;
reg [11:0] frozen_floor;
function integer noise(input integer amplitude);
    begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        noise=($signed({1'b0,rng[15:0]})*amplitude/32768)-amplitude;
    end
endfunction
task sample(input integer value);
    @(negedge clk);mic_pcm=value;mic_valid=1;
    @(negedge clk);mic_valid=0;#1;
    if(!analysis_valid || analysis_left!==analysis_right) $fatal(1,"Valid cadence or mono changed");
    n=n+1;
endtask
task quiet(input integer count,input integer amplitude);
    integer q;
    begin
        for(q=0;q<count;q=q+1) begin
            noise_word=noise(amplitude);
            // Sparse bumps: the old peak gate opens, mean gate stays closed.
            if(q%2048==1024) noise_word=noise_word+30000;
            sample(noise_word);
            if(q>2048 && analysis_left!=0) new_leaks=new_leaks+1;
            if(q>2048 && baseline_left!=0) baseline_leaks=baseline_leaks+1;
            if(dut.gate_open || active || gain_shift!=4) $fatal(1,"Quiet gain pumping/gate false trigger at %0d",q);
        end
    end
endtask
initial begin
    repeat(8) @(negedge clk);rst=0;repeat(5) @(negedge clk);
    quiet(16384,512);
    // Change ambient level, but do not train the tracker on voice.
    quiet(16384,1024);
    if(new_leaks!=0 || baseline_leaks<20000) $fatal(1,"Noise A/B test not exercised: new%0d old%0d",new_leaks,baseline_leaks);
    if(dut.noise_floor<400 || dut.noise_floor>650) $fatal(1,"Background estimate not adapting: %0d",dut.noise_floor);
    // Weak periodic voice over the stronger background, no quiet calibration
    // pause at onset. Two 256-sample attack windows preserve responsiveness.
    for(i=0;i<8192;i=i+1) begin
        sample($rtoi(3000*$sin(6.283185307179586*220*i/48000.0))+noise(512));
        if(active && first_voice<0) first_voice=i;
        if($signed(analysis_left)>voice_peak) voice_peak=$signed(analysis_left);
    end
    if(first_voice<0 || first_voice>767 || !active || gain_shift<5 || voice_peak<100000)
        $fatal(1,"Weak voice lost or slow: attack%0d gain%0d peak%0d",first_voice,gain_shift,voice_peak);
    frozen_floor=dut.noise_floor;
    for(i=0;i<48000;i=i+1) sample($rtoi(9000*$sin(6.283185307179586*440*i/48000.0))+noise(512));
    if(!active || dut.noise_floor!=frozen_floor) $fatal(1,"Sustained voice learned as background");
    // 80ms below-close tail remains visible throughout the 96ms hang time.
    for(i=0;i<3840;i=i+1) begin
        sample($rtoi(600*$sin(6.283185307179586*220*i/48000.0))+noise(128));
        if(analysis_left!=0) tail_nonzero=tail_nonzero+1;
        if(!active) $fatal(1,"Word tail chopped at sample%0d",i);
    end
    if(tail_nonzero<3700) $fatal(1,"Tail was zeroed");
    for(i=0;i<8192;i=i+1) begin
        sample(noise(512));
        if(i>5632 && (analysis_left!=0 || active || gain_shift!=4)) $fatal(1,"Did not settle to quiet within bounded release");
    end
    quiet(48000,512);
    // Closed gate must still pass all valid zero samples to refresh FFT/history.
    for(i=0;i<5;i=i+1) begin
        @(negedge clk);lesson=i;repeat(4) @(negedge clk);
        if(!analysis_valid || analysis_left!==24'h123456 || analysis_right!==24'hfedcba)
            $fatal(1,"DDS page %0d not bit-exact",i);
        dds_valid=0;@(negedge clk);if(analysis_valid) $fatal(1,"DDS valid changed");dds_valid=1;
    end
    $display("ALL VOICE NOISE TESTS PASSED: old quiet nonzero=%0d, new=%0d; adaptive quiet floor=%0d; weak voice attack=%0d samples (%0.2fms); peak=%0d; 80ms tail=%0d nonzero; sustained voice, gain cap, valid cadence, five DDS pages",baseline_leaks,new_leaks,frozen_floor,first_voice,first_voice/48.0,voice_peak,tail_nonzero);
    $finish;
end
initial begin #30000000;$fatal(1,"Noise test timeout");end
endmodule
