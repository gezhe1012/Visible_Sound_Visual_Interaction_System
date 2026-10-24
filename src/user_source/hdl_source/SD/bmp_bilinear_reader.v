// Load-time bilinear scaler. Fixed 640x480 output, bottom row first.
// BMP files must occupy contiguous sectors, as in the original example.
module bmp_bilinear_reader #(
    parameter MAX_SOURCE_WIDTH=2048, MAX_SOURCE_HEIGHT=2048
)(
    input clk, rst, output ready,
    input scan_start, input [31:0] scan_start_sector, scan_max_sector,
    input [2:0] scan_target_count,
    output reg scan_done, scan_found_valid,
    output reg [31:0] scan_found_sector, output reg [2:0] scan_found_total,
    input load_start, input [31:0] load_sector,
    input sd_init_done, output reg [3:0] state_code,
    input [15:0] bmp_width, bmp_height,
    output reg write_req, input write_req_ack, write_ready,
    output reg load_error,
    output reg sd_sec_read, output reg [31:0] sd_sec_read_addr,
    input [7:0] sd_sec_read_data, input sd_sec_read_data_valid, sd_sec_read_end,
    output reg bmp_data_wr_en, output reg [23:0] bmp_data
);
localparam IDLE=0, SCAN=1, HEADER=2, VALIDATE=3, WAIT_WRITE=4,
    CHECK_ROW=5, ROW_ADDRESS=6, READ_ROW=7, AFTER_SECTOR=8,
    GET_LEFT=9, GET_RIGHT=10, WEIGHT=11, HORIZONTAL=12,
    VERTICAL=13, EMIT=14, ADVANCE_X=15, ADVANCE_Y=16,
    Y_WEIGHT=17, SETUP=18, SCAN_GAP=19, ROW_MULTIPLY=20, ROW_OFFSET=21,
    MIX_DIFF=22, MIX_PRODUCT=23, MIX_ADD=24, H0_DONE=25, H1_DONE=26, V_DONE=27,
    PREPARE_X=28, ROW_TEST=29;
reg [4:0] state;
reg [9:0] header_byte;
reg [7:0] magic0, magic1;
reg [31:0] file_len, pixel_offset, dib_size, width, height, compression;
reg [15:0] planes, bit_count;
reg [31:0] scan_sector, file_sector, row_stride, row_start, read_position;
reg [12:0] row_bytes, row_received;
reg row_complete;
reg [1:0] byte_phase;
reg [15:0] bgr_partial;
reg [10:0] line_write_x;
reg load_line;
reg [11:0] cache_tag0, cache_tag1, requested_row;
reg cache_valid0, cache_valid1;
reg [11:0] src_x, src_y;
reg [9:0] dst_x, dst_y;
reg [11:0] x_remainder, y_remainder;
reg [7:0] fx, fy;
reg [10:0] fraction_remainder;
reg [3:0] fraction_bit;
reg [23:0] left0, left1, right0, right1, horizontal0, horizontal1;
reg [28:0] watchdog;
reg [31:0] absolute_height, parsed_stride, expected_file_end;
reg [24:0] required_bytes;
reg header_match;
reg [11:0] physical_row;
reg [24:0] row_product;
reg [10:0] source_last_x,source_last_y;
reg [10:0] read_left_address,read_right_address;
reg [23:0] mix_a,mix_b,mix_result,mix_base;
reg [7:0] mix_t;
reg [4:0] mix_return;
reg signed [8:0] diff_r,diff_g,diff_b;
reg signed [17:0] product_r,product_g,product_b;
wire signed [18:0] sum_r=$signed(product_r)+$signed({1'b0,mix_base[23:16],8'd0})+19'sd128;
wire signed [18:0] sum_g=$signed(product_g)+$signed({1'b0,mix_base[15:8],8'd0})+19'sd128;
wire signed [18:0] sum_b=$signed(product_b)+$signed({1'b0,mix_base[7:0],8'd0})+19'sd128;
reg [31:0] file_sectors,next_match;
// Continuous header pipeline. All header fields are stable by byte 34;
// over 470 bytes remain before the sector-end validation decision.
always @(posedge clk or posedge rst) begin
    if(rst) begin
        absolute_height<=0; parsed_stride<=0; required_bytes<=0;
        expected_file_end<=0; header_match<=0;
        file_sectors<=0; next_match<=0;
    end else begin
        absolute_height<=height[31] ? (~height+32'd1) : height;
        parsed_stride<=(({20'd0,width[11:0]}*32'd3)+32'd3)&32'hfffffffc;
        required_bytes<=parsed_stride[12:0]*absolute_height[11:0];
        expected_file_end<=pixel_offset+{7'd0,required_bytes};
        file_sectors<=(file_len+32'd511)>>9;
        next_match<=scan_sector+file_sectors;
        header_match<=magic0=="B" && magic1=="M" &&
            dib_size>=40 && dib_size<=124 && planes==1 && bit_count==24 && compression==0 &&
            width>=1 && width<=MAX_SOURCE_WIDTH &&
            absolute_height>=1 && absolute_height<=MAX_SOURCE_HEIGHT &&
            pixel_offset>=54 && pixel_offset<=1048576 && pixel_offset>=dib_size+14 &&
            file_len>=expected_file_end && file_len<=16777216 &&
            bmp_width==640 && bmp_height==480;
    end
end
reg [11:0] next_src_y;
// Row lookahead is settled during the eight Y_WEIGHT clocks, before CHECK_ROW.
// Register it to separate source-coordinate arithmetic from cache-tag control.
always @(posedge clk or posedge rst) begin
    if(rst) next_src_y<=0;
    else next_src_y<=(src_y<{1'b0,source_last_y}) ? src_y+12'd1 : src_y;
end
wire [10:0] x_right=(src_x<{1'b0,source_last_x}) ? src_x[10:0]+11'd1 : src_x[10:0];
assign ready=state==IDLE;

// Synchronous line RAMs: no array reset, so TD can infer embedded RAM.
reg [23:0] line0 [0:MAX_SOURCE_WIDTH-1];
reg [23:0] line1 [0:MAX_SOURCE_WIDTH-1];
reg [23:0] line_q0, line_q1;
wire [10:0] line_address=(state==GET_LEFT) ? read_left_address : read_right_address;
always @(posedge clk) begin
    line_q0<=line0[line_address]; line_q1<=line1[line_address];
    if(state==READ_ROW && sd_sec_read_data_valid &&
       read_position>=row_start && row_received<row_bytes && byte_phase==2) begin
        if(!load_line) line0[line_write_x]<={sd_sec_read_data,bgr_partial};
        else line1[line_write_x]<={sd_sec_read_data,bgr_partial};
    end
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        header_byte<=0; magic0<=0; magic1<=0; file_len<=0; pixel_offset<=0;
        dib_size<=0; width<=0; height<=0; planes<=0; bit_count<=0; compression<=0;
    end else if(state==SCAN || state==HEADER) begin
        if(sd_sec_read_data_valid) begin
            header_byte<=header_byte+10'd1;
            case(header_byte)
                0: magic0<=sd_sec_read_data;
                1: magic1<=sd_sec_read_data;
                2: file_len[7:0]<=sd_sec_read_data;
                3: file_len[15:8]<=sd_sec_read_data;
                4: file_len[23:16]<=sd_sec_read_data;
                5: file_len[31:24]<=sd_sec_read_data;
                10: pixel_offset[7:0]<=sd_sec_read_data;
                11: pixel_offset[15:8]<=sd_sec_read_data;
                12: pixel_offset[23:16]<=sd_sec_read_data;
                13: pixel_offset[31:24]<=sd_sec_read_data;
                14: dib_size[7:0]<=sd_sec_read_data;
                15: dib_size[15:8]<=sd_sec_read_data;
                16: dib_size[23:16]<=sd_sec_read_data;
                17: dib_size[31:24]<=sd_sec_read_data;
                18: width[7:0]<=sd_sec_read_data;
                19: width[15:8]<=sd_sec_read_data;
                20: width[23:16]<=sd_sec_read_data;
                21: width[31:24]<=sd_sec_read_data;
                22: height[7:0]<=sd_sec_read_data;
                23: height[15:8]<=sd_sec_read_data;
                24: height[23:16]<=sd_sec_read_data;
                25: height[31:24]<=sd_sec_read_data;
                26: planes[7:0]<=sd_sec_read_data;
                27: planes[15:8]<=sd_sec_read_data;
                28: bit_count[7:0]<=sd_sec_read_data;
                29: bit_count[15:8]<=sd_sec_read_data;
                30: compression[7:0]<=sd_sec_read_data;
                31: compression[15:8]<=sd_sec_read_data;
                32: compression[23:16]<=sd_sec_read_data;
                33: compression[31:24]<=sd_sec_read_data;
            endcase
        end
    end else header_byte<=0;
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE; state_code<=0; scan_done<=0; scan_found_valid<=0;
        scan_found_sector<=0; scan_found_total<=0; scan_sector<=0;
        file_sector<=0; write_req<=0; sd_sec_read<=0; sd_sec_read_addr<=0;
        bmp_data_wr_en<=0; bmp_data<=0; load_error<=0;
        row_stride<=0; row_bytes<=0; row_start<=0; read_position<=0;
        row_received<=0; byte_phase<=0; bgr_partial<=0; line_write_x<=0;
        row_complete<=0;
        load_line<=0; cache_tag0<=0; cache_tag1<=0;
        cache_valid0<=0; cache_valid1<=0; requested_row<=0;
        src_x<=0; src_y<=0; dst_x<=0; dst_y<=0;
        x_remainder<=0; y_remainder<=0; fx<=0; fy<=0;
        fraction_remainder<=0; fraction_bit<=0;
        left0<=0; left1<=0; right0<=0; right1<=0;
        horizontal0<=0; horizontal1<=0; watchdog<=0;
        physical_row<=0; row_product<=0;
        source_last_x<=0; source_last_y<=0;
        read_left_address<=0; read_right_address<=0;
        mix_a<=0; mix_b<=0; mix_result<=0; mix_base<=0; mix_t<=0; mix_return<=IDLE;
        diff_r<=0; diff_g<=0; diff_b<=0;
        product_r<=0; product_g<=0; product_b<=0;
    end else begin
        bmp_data_wr_en<=0; scan_found_valid<=0; load_error<=0;
        // Abort on 2.68 seconds without progress at 100 MHz.
        if(state==IDLE || sd_sec_read_data_valid || sd_sec_read_end || bmp_data_wr_en) watchdog<=0;
        else watchdog<=watchdog+29'd1;
        if(!sd_init_done) begin
            state<=IDLE; write_req<=0; sd_sec_read<=0; scan_done<=0;
            cache_valid0<=0; cache_valid1<=0; watchdog<=0;
        end else if(watchdog[28]) begin
            state<=IDLE; write_req<=0; sd_sec_read<=0; load_error<=1;
            watchdog<=0; state_code<=4'hE;
        end else case(state)
            IDLE: begin
                state_code<=1; sd_sec_read<=0; write_req<=0;
                if(scan_start) begin
                    scan_done<=0; scan_found_total<=0; scan_sector<=scan_start_sector;
                    sd_sec_read_addr<=scan_start_sector; state<=SCAN;
                end else if(load_start) begin
                    file_sector<=load_sector; sd_sec_read_addr<=load_sector; state<=HEADER;
                end
            end
            SCAN: begin
                state_code<=2; sd_sec_read<=1;
                if(sd_sec_read_end) begin
                    sd_sec_read<=0; state<=SCAN_GAP;
                    if(header_match) begin
                        scan_found_valid<=1; scan_found_sector<=scan_sector;
                        scan_found_total<=scan_found_total+3'd1;
                        scan_sector<=next_match; sd_sec_read_addr<=next_match;
                        if(scan_found_total+3'd1>=scan_target_count || next_match>scan_max_sector) begin
                            scan_done<=1; state<=IDLE;
                        end
                    end else if(scan_sector>=scan_max_sector) begin scan_done<=1; state<=IDLE; end
                    else begin
                        scan_sector<=scan_sector+32'd1; sd_sec_read_addr<=scan_sector+32'd1;
                    end
                end
            end
            SCAN_GAP: state<=SCAN;
            HEADER: begin
                state_code<=2; sd_sec_read<=1;
                if(sd_sec_read_end) begin sd_sec_read<=0; state<=VALIDATE; end
            end
            VALIDATE: begin
                if(header_match) begin
                    row_stride<=parsed_stride;
                    row_bytes<={width[11:0],1'b0}+width[12:0];
                    source_last_x<=width[10:0]-11'd1;
                    source_last_y<=absolute_height[10:0]-11'd1;
                    cache_valid0<=0; cache_valid1<=0;
                    src_x<=0; src_y<=0; dst_x<=0; dst_y<=0;
                    x_remainder<=0; y_remainder<=0; fx<=0; fy<=0;
                    write_req<=1; state<=WAIT_WRITE;
                end else begin load_error<=1; state<=IDLE; end
            end
            WAIT_WRITE: begin
                state_code<=3;
                if(write_req_ack) begin write_req<=0; state<=SETUP; end
            end
            SETUP: if(!write_req_ack) state<=CHECK_ROW;
            CHECK_ROW: begin
                state_code<=4;
                if(!cache_valid0 || cache_tag0!=src_y) begin
                    requested_row<=src_y; load_line<=0; state<=ROW_ADDRESS;
                end else if(!cache_valid1 || cache_tag1!=next_src_y) begin
                    requested_row<=next_src_y; load_line<=1; state<=ROW_ADDRESS;
                end else begin src_x<=0; x_remainder<=0; dst_x<=0; state<=PREPARE_X; end
            end
            ROW_ADDRESS: begin
                // Stream is bottom-up; top-down BMP reverses source row address.
                if(height[31]) physical_row<={1'b0,source_last_y}-requested_row;
                else physical_row<=requested_row;
                row_received<=0; line_write_x<=0; byte_phase<=0; state<=ROW_MULTIPLY;
            end
            ROW_MULTIPLY: begin row_product<=physical_row*row_stride[12:0]; state<=ROW_OFFSET; end
            ROW_OFFSET: begin row_start<=pixel_offset+{7'd0,row_product}; state<=ROW_TEST; end
            ROW_TEST: begin row_complete<=(row_received==row_bytes); state<=AFTER_SECTOR; end
            AFTER_SECTOR: begin
                sd_sec_read<=0;
                if(row_complete) begin
                    if(!load_line) begin cache_tag0<=requested_row; cache_valid0<=1; end
                    else begin cache_tag1<=requested_row; cache_valid1<=1; end
                    state<=CHECK_ROW;
                end else begin
                    if(row_received==0) begin
                        sd_sec_read_addr<=file_sector+(row_start>>9);
                        read_position<={row_start[31:9],9'd0};
                    end else sd_sec_read_addr<=sd_sec_read_addr+32'd1;
                    state<=READ_ROW;
                end
            end
            READ_ROW: begin
                sd_sec_read<=1;
                if(sd_sec_read_data_valid) begin
                    read_position<=read_position+32'd1;
                    if(read_position>=row_start && row_received<row_bytes) begin
                        row_received<=row_received+13'd1;
                        case(byte_phase)
                            0: begin bgr_partial[7:0]<=sd_sec_read_data; byte_phase<=1; end
                            1: begin bgr_partial[15:8]<=sd_sec_read_data; byte_phase<=2; end
                            2: begin byte_phase<=0; line_write_x<=line_write_x+11'd1; end
                        endcase
                    end
                end
                if(sd_sec_read_end) begin sd_sec_read<=0; state<=ROW_TEST; end
            end
            PREPARE_X: begin
                read_left_address<=src_x[10:0]; read_right_address<=x_right; state<=GET_LEFT;
            end
            GET_LEFT: state<=GET_RIGHT;
            GET_RIGHT: begin
                left0<=line_q0; left1<=line_q1;
                fraction_remainder<=x_remainder[10:0]; fraction_bit<=0; fx<=0; state<=WEIGHT;
            end
            WEIGHT: begin
                right0<=line_q0; right1<=line_q1;
                // Sequential 8-bit restoring division: floor(rem*256/639).
                if((fraction_remainder<<1)>=11'd639) begin
                    fraction_remainder<=(fraction_remainder<<1)-11'd639; fx<={fx[6:0],1'b1};
                end else begin fraction_remainder<=fraction_remainder<<1; fx<={fx[6:0],1'b0}; end
                fraction_bit<=fraction_bit+4'd1;
                if(fraction_bit==7) state<=HORIZONTAL;
            end
            HORIZONTAL: begin
                mix_a<=left0; mix_b<=right0; mix_t<=fx;
                mix_return<=H0_DONE; state<=MIX_DIFF;
            end
            H0_DONE: begin
                horizontal0<=mix_result;
                mix_a<=left1; mix_b<=right1; mix_t<=fx;
                mix_return<=H1_DONE; state<=MIX_DIFF;
            end
            H1_DONE: begin horizontal1<=mix_result; state<=VERTICAL; end
            VERTICAL: begin
                mix_a<=horizontal0; mix_b<=horizontal1; mix_t<=fy;
                mix_return<=V_DONE; state<=MIX_DIFF;
            end
            V_DONE: begin bmp_data<=mix_result; state<=EMIT; end
            // Shared three-channel Q0.8 lerp engine, one multiplier per color.
            // Subtraction, multiply and rounded addition have separate clocks.
            MIX_DIFF: begin
                diff_r<=$signed({1'b0,mix_b[23:16]})-$signed({1'b0,mix_a[23:16]});
                diff_g<=$signed({1'b0,mix_b[15:8]})-$signed({1'b0,mix_a[15:8]});
                diff_b<=$signed({1'b0,mix_b[7:0]})-$signed({1'b0,mix_a[7:0]});
                mix_base<=mix_a; state<=MIX_PRODUCT;
            end
            MIX_PRODUCT: begin
                product_r<=diff_r*$signed({1'b0,mix_t});
                product_g<=diff_g*$signed({1'b0,mix_t});
                product_b<=diff_b*$signed({1'b0,mix_t});
                state<=MIX_ADD;
            end
            MIX_ADD: begin
                mix_result<={sum_r[15:8],sum_g[15:8],sum_b[15:8]};
                state<=mix_return;
            end
            EMIT: if(write_ready) begin
                bmp_data_wr_en<=1;
                if(dst_x==639) begin
                    if(dst_y==479) state<=IDLE;
                    else begin
                        dst_y<=dst_y+10'd1; y_remainder<=y_remainder+{1'b0,source_last_y};
                        state<=ADVANCE_Y;
                    end
                end else begin
                    dst_x<=dst_x+10'd1; x_remainder<=x_remainder+{1'b0,source_last_x}; state<=ADVANCE_X;
                end
            end
            ADVANCE_X: begin
                if(x_remainder>=639) begin x_remainder<=x_remainder-12'd639; src_x<=src_x+12'd1; end
                else state<=PREPARE_X;
            end
            ADVANCE_Y: begin
                if(y_remainder>=479) begin y_remainder<=y_remainder-12'd479; src_y<=src_y+12'd1; end
                else begin
                    fraction_remainder<=y_remainder[10:0]; fraction_bit<=0; fy<=0; state<=Y_WEIGHT;
                end
            end
            Y_WEIGHT: begin
                if((fraction_remainder<<1)>=11'd479) begin
                    fraction_remainder<=(fraction_remainder<<1)-11'd479; fy<={fy[6:0],1'b1};
                end else begin fraction_remainder<=fraction_remainder<<1; fy<={fy[6:0],1'b0}; end
                fraction_bit<=fraction_bit+4'd1;
                if(fraction_bit==7) state<=CHECK_ROW;
            end
            default: begin state<=IDLE; sd_sec_read<=0; write_req<=0; load_error<=1; end
        endcase
    end
end
endmodule
