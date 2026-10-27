// 1024-point stereo fixed-point radix-2 DIT FFT, time shared at 25MHz.
// PCM is tapped, NEVER backpressured. Capture 1024 consecutive stereo pairs,
// then process the frozen block L/R in turn. Frames between blocks are skipped.
// 24->16 MSBs; periodic Hann Q0.15; complex Q1.15, /2 at EACH of 10 stages.
// Four signed 16x16 multipliers, registered products/rotation/sums. Saturation
// prevents wrap. Magnitude is |Re|+|Im|, not calibrated RMS/power or exact dBFS.
module audio_fft1024(
    input clk,rst,audio_valid,
    input [23:0] audio_left,audio_right,
    input result_ack,
    output reg spectrum_write,
    output reg [7:0] spectrum_address,
    output reg [6:0] spectrum_height,
    output reg result_done,
    // Passive observation only: never participates in result_ack or state.
    output reg capture_start,bin_valid,bin_channel,
    output reg [8:0] bin_number,
    output reg [16:0] bin_magnitude
);
localparam CAP=0, LOAD_R=1,LOAD_W=2,LOAD_M=3,LOAD_S=4,LOAD_NEXT=5,
    RA=6,WA=7,RB=8,WB=9,MUL=10,ROT=11,SUM=12,WRITE_A=13,WRITE_B=14,
    NEXT=15,MAG_R=16,MAG_W=17,MAG_L=18,WAIT_ACK=19;
reg [4:0] state;
reg [9:0] capture_index,load_index;
reg channel;
reg [31:0] capture_ram [0:1023];
reg [31:0] capture_q;
reg [31:0] fft_ram [0:1023];
reg [31:0] fft_q;
reg [9:0] read_address,write_address;
reg [31:0] write_data;
reg write_enable;
reg [9:0] half_size,j,base;
reg [3:0] stage,twiddle_shift;
wire [9:0] address_a=base+j;
wire [9:0] address_b=address_a+half_size;
wire [8:0] twiddle_address=j<<twiddle_shift;
wire [31:0] twiddle_q;
wire [15:0] window_q;
fft1024_tables tables(.clk(clk),.twiddle_address(twiddle_address),
    .window_address(load_index),.twiddle_q(twiddle_q),.window_q(window_q));
reg signed [15:0] ar,ai,br,bi;
reg signed [31:0] p0,p1,p2,p3,window_product;
reg signed [16:0] tr,ti;
reg [31:0] sum_a,sum_b;
reg [8:0] bin_index;
reg [6:0] band_index;
reg [3:0] remaining;
reg [16:0] band_max;
wire [15:0] abs_re=fft_q[31] ? (~fft_q[31:16]+16'd1) : fft_q[31:16];
wire [15:0] abs_im=fft_q[15] ? (~fft_q[15:0]+16'd1) : fft_q[15:0];
wire [16:0] magnitude={1'b0,abs_re}+{1'b0,abs_im};
wire [16:0] peak=magnitude>band_max ? magnitude : band_max;
wire signed [32:0] real_product=$signed({p0[31],p0})-$signed({p1[31],p1});
wire signed [32:0] imag_product=$signed({p2[31],p2})+$signed({p3[31],p3});
wire signed [17:0] ar_ext={{2{ar[15]}},ar};
wire signed [17:0] ai_ext={{2{ai[15]}},ai};
wire signed [17:0] tr_ext={tr[16],tr};
wire signed [17:0] ti_ext={ti[16],ti};
function [15:0] sat16;
    input signed [17:0] value;
    begin
        if(value>32767) sat16=16'h7fff;
        else if(value< -32768) sat16=16'h8000;
        else sat16=value[15:0];
    end
endfunction
function [9:0] reverse10;
    input [9:0] n;
    integer k;
    begin for(k=0;k<10;k=k+1) reverse10[k]=n[9-k]; end
endfunction
// Approx logarithmic height: 6 pixels/octave (~6dB), floor 4 FFT LSBs.
// Piecewise-linear interpolation inside each octave; zero stays zero.
function [6:0] log_height;
    input [16:0] value;
    integer k,exponent,level;
    reg [19:0] fraction;
    begin
        exponent=0;
        for(k=0;k<17;k=k+1) if(value[k]) exponent=k;
        fraction=({3'b0,value}<<3)>>exponent;
        level=(exponent-2)*6+((fraction-8)*6>>3);
        if(value<4 || level<0) log_height=0;
        else if(level>66) log_height=66;
        else log_height=level;
    end
endfunction
always @* begin
    read_address=address_b;
    if(state==RA || state==WA) read_address=address_a;
    if(state==MAG_R || state==MAG_W || state==MAG_L) read_address={1'b0,bin_index};
    write_enable=0; write_address=0; write_data=0;
    if(state==LOAD_S) begin
        write_enable=1; write_address=reverse10(load_index);
        write_data={window_product[30:15],16'd0};
    end else if(state==WRITE_A) begin
        write_enable=1; write_address=address_a; write_data=sum_a;
    end else if(state==WRITE_B) begin
        write_enable=1; write_address=address_b; write_data=sum_b;
    end
end
// Synchronous SDP memories, deliberately no array reset.
always @(posedge clk) begin
    capture_q<=capture_ram[load_index];
    if(!rst && state==CAP && audio_valid)
        capture_ram[capture_index]<={audio_left[23:8],audio_right[23:8]};
    fft_q<=fft_ram[read_address];
    if(!rst && write_enable) fft_ram[write_address]<=write_data;
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=CAP; capture_index<=0; load_index<=0; channel<=0;
        half_size<=1; j<=0; base<=0; stage<=0; twiddle_shift<=9;
        ar<=0; ai<=0; br<=0; bi<=0; p0<=0; p1<=0; p2<=0; p3<=0;
        window_product<=0; tr<=0; ti<=0; sum_a<=0; sum_b<=0;
        bin_index<=0; band_index<=0; remaining<=1; band_max<=0;
        spectrum_write<=0; spectrum_address<=0; spectrum_height<=0; result_done<=0;
        capture_start<=0;bin_valid<=0;bin_channel<=0;bin_number<=0;bin_magnitude<=0;
    end else begin
        spectrum_write<=0; result_done<=0;
        capture_start<=state==CAP && capture_index==0 && audio_valid;
        bin_valid<=0;
        case(state)
            CAP: if(audio_valid) begin
                if(capture_index==1023) begin
                    capture_index<=0; load_index<=0; channel<=0; state<=LOAD_R;
                end else capture_index<=capture_index+10'd1;
            end
            LOAD_R: state<=LOAD_W;
            LOAD_W: state<=LOAD_M;
            LOAD_M: begin
                window_product<=$signed(channel ? capture_q[15:0] : capture_q[31:16])*$signed(window_q);
                state<=LOAD_S;
            end
            LOAD_S: state<=LOAD_NEXT;
            LOAD_NEXT: if(load_index==1023) begin
                half_size<=1; j<=0; base<=0; stage<=0; twiddle_shift<=9; state<=RA;
            end else begin load_index<=load_index+10'd1; state<=LOAD_R; end
            RA: state<=WA;
            WA: begin ar<=fft_q[31:16]; ai<=fft_q[15:0]; state<=RB; end
            RB: state<=WB;
            WB: begin br<=fft_q[31:16]; bi<=fft_q[15:0]; state<=MUL; end
            MUL: begin
                p0<=br*$signed(twiddle_q[31:16]); p1<=bi*$signed(twiddle_q[15:0]);
                p2<=br*$signed(twiddle_q[15:0]); p3<=bi*$signed(twiddle_q[31:16]);
                state<=ROT;
            end
            ROT: begin tr<=real_product>>>15; ti<=imag_product>>>15; state<=SUM; end
            SUM: begin
                sum_a<={sat16((ar_ext+tr_ext)>>>1),sat16((ai_ext+ti_ext)>>>1)};
                sum_b<={sat16((ar_ext-tr_ext)>>>1),sat16((ai_ext-ti_ext)>>>1)};
                state<=WRITE_A;
            end
            WRITE_A: state<=WRITE_B;
            WRITE_B: state<=NEXT;
            NEXT: begin
                if(j==half_size-1) begin
                    j<=0;
                    if({1'b0,base}+({1'b0,half_size}<<1)>=1024) begin
                        base<=0;
                        if(stage==9) begin
                            bin_index<=0; band_index<=0; remaining<=1; band_max<=0; state<=MAG_R;
                        end else begin
                            stage<=stage+4'd1; half_size<=half_size<<1;
                            twiddle_shift<=twiddle_shift-4'd1; state<=RA;
                        end
                    end else begin base<=base+(half_size<<1); state<=RA; end
                end else begin j<=j+10'd1; state<=RA; end
            end
            MAG_R: state<=MAG_W;
            MAG_W: state<=MAG_L;
            MAG_L: begin
                bin_valid<=1;bin_channel<=channel;bin_number<=bin_index;bin_magnitude<=magnitude;
                if(remaining==1) begin
                    spectrum_write<=1; spectrum_address<={channel,band_index}; spectrum_height<=log_height(peak);
                    band_max<=0; band_index<=band_index+7'd1;
                    if(band_index<31) remaining<=1;
                    else if(band_index<63) remaining<=2;
                    else if(band_index<95) remaining<=4;
                    else remaining<=9;
                end else begin remaining<=remaining-4'd1; band_max<=peak; end
                if(bin_index==511) begin
                    if(!channel) begin channel<=1; load_index<=0; state<=LOAD_R; end
                    else begin result_done<=1; state<=WAIT_ACK; end
                end else begin bin_index<=bin_index+9'd1; state<=MAG_R; end
            end
            WAIT_ACK: if(result_ack) state<=CAP;
            default: state<=CAP;
        endcase
    end
end
endmodule
