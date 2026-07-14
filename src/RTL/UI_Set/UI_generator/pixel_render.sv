`timescale 1ns / 1ps

module pixel_render #(
    parameter int IMG_W = 320,
    parameter int IMG_H = 240,
    parameter int FIFO_DEPTH = 32
) (
    input  logic clk,
    input  logic reset,

    // from instruction_generator
    input  logic       instr_valid,
    output logic       instr_ready,

    input  logic [1:0] instr_op,
    input  logic [8:0] instr_x_start,
    input  logic [7:0] instr_y_start,
    input  logic [8:0] instr_length,
    input  logic [3:0] instr_dash_on,
    input  logic [3:0] instr_dash_off,
    input  logic       instr_type,      // 0: enemy, 1: friend

    // to ui_framebuffer
    output logic       pix_valid,
    input  logic       pix_ready,

    output logic [8:0] pix_x,
    output logic [7:0] pix_y,
    output logic       pix_type         // 0: enemy, 1: friend
);

    // ================================
    // Instruction op code
    // ================================
    localparam logic [1:0] OP_HLINE        = 2'd0;
    localparam logic [1:0] OP_VLINE        = 2'd1;
    localparam logic [1:0] OP_TEXT_ENEMY   = 2'd2;
    localparam logic [1:0] OP_TEXT_WARNING = 2'd3;

    localparam int INSTR_W = 37;

    // ================================
    // Instruction FIFO
    // ================================
    logic [INSTR_W-1:0] instr_fifo_wdata;
    logic [INSTR_W-1:0] instr_fifo_rdata;

    logic instr_fifo_wr_en;
    logic instr_fifo_rd_en;
    logic instr_fifo_full;
    logic instr_fifo_empty;

    assign instr_fifo_wdata = {
        instr_op,          // 2bit
        instr_x_start,     // 9bit
        instr_y_start,     // 8bit
        instr_length,      // 9bit
        instr_dash_on,     // 4bit
        instr_dash_off,    // 4bit
        instr_type         // 1bit
    };

    assign instr_ready = !instr_fifo_full;
    assign instr_fifo_wr_en = instr_valid && instr_ready;

    sync_fifo #(
        .DATA_WIDTH(INSTR_W),
        .DEPTH     (FIFO_DEPTH)
    ) U_INSTR_FIFO (
        .clk    (clk),
        .reset  (reset),
        .wr_en  (instr_fifo_wr_en),
        .wr_data(instr_fifo_wdata),
        .rd_en  (instr_fifo_rd_en),
        .rd_data(instr_fifo_rdata),
        .full   (instr_fifo_full),
        .empty  (instr_fifo_empty)
    );

    // ================================
    // FIFO output unpacking
    // ================================
    logic [1:0] fifo_op;
    logic [8:0] fifo_x_start;
    logic [7:0] fifo_y_start;
    logic [8:0] fifo_length;
    logic [3:0] fifo_dash_on;
    logic [3:0] fifo_dash_off;
    logic       fifo_type;

    assign {
        fifo_op,
        fifo_x_start,
        fifo_y_start,
        fifo_length,
        fifo_dash_on,
        fifo_dash_off,
        fifo_type
    } = instr_fifo_rdata;

    // ================================
    // Current instruction registers
    // ================================
    logic [1:0] op_reg;
    logic [8:0] x_start_reg;
    logic [7:0] y_start_reg;
    logic [8:0] length_reg;
    logic [3:0] dash_on_reg;
    logic [3:0] dash_off_reg;
    logic       type_reg;

    // ================================
    // Renderer FSM
    // ================================
    typedef enum logic [1:0] {
        S_IDLE,
        S_LINE,
        S_TEXT
    } state_t;

    state_t state;

    // ================================
    // Line rendering counters
    // ================================
    logic [8:0] line_idx;
    logic [3:0] dash_count;
    logic       dash_draw;

    logic [9:0] line_x_calc;
    logic [8:0] line_y_calc;

    logic       line_in_bounds;
    logic       line_should_draw;
    logic       line_step;

    always_comb begin
        if (op_reg == OP_HLINE) begin
            line_x_calc = {1'b0, x_start_reg} + {1'b0, line_idx};
            line_y_calc = {1'b0, y_start_reg};
        end else begin
            line_x_calc = {1'b0, x_start_reg};
            line_y_calc = {1'b0, y_start_reg} + line_idx;
        end

        line_in_bounds =
            (line_x_calc < IMG_W) &&
            (line_y_calc < IMG_H);

        if (dash_off_reg == 4'd0) begin
            line_should_draw = 1'b1;
        end else begin
            line_should_draw = dash_draw;
        end

        line_step =
            (state == S_LINE) &&
            (
                !line_should_draw ||
                !line_in_bounds  ||
                (pix_valid && pix_ready)
            );
    end

    // ================================
    // Text rendering counters
    // ================================
    logic [2:0] text_row;       // 0~6
    logic [2:0] text_char_idx;  // character index
    logic [2:0] text_col;       // 0~5, 5는 글자 간격

    logic [3:0] text_char_count;
    logic [3:0] text_char_code;
    logic [4:0] font_bits;

    logic [9:0] text_x_calc;
    logic [8:0] text_y_calc;
    logic       text_pixel_on;
    logic       text_in_bounds;
    logic       text_step;

    localparam logic [3:0] CH_E = 4'd0;
    localparam logic [3:0] CH_N = 4'd1;
    localparam logic [3:0] CH_M = 4'd2;
    localparam logic [3:0] CH_Y = 4'd3;
    localparam logic [3:0] CH_W = 4'd4;
    localparam logic [3:0] CH_A = 4'd5;
    localparam logic [3:0] CH_R = 4'd6;
    localparam logic [3:0] CH_I = 4'd7;
    localparam logic [3:0] CH_G = 4'd8;

    // ----------------
    // text character 선택
    // ENEMY   = E N E M Y
    // WARNING = W A R N I N G
    // ----------------
    function automatic logic [3:0] get_text_char (
        input logic [1:0] op,
        input logic [2:0] idx
    );
        begin
            get_text_char = CH_E;

            if (op == OP_TEXT_ENEMY) begin
                case (idx)
                    3'd0: get_text_char = CH_E;
                    3'd1: get_text_char = CH_N;
                    3'd2: get_text_char = CH_E;
                    3'd3: get_text_char = CH_M;
                    3'd4: get_text_char = CH_Y;
                    default: get_text_char = CH_E;
                endcase
            end else begin
                case (idx)
                    3'd0: get_text_char = CH_W;
                    3'd1: get_text_char = CH_A;
                    3'd2: get_text_char = CH_R;
                    3'd3: get_text_char = CH_N;
                    3'd4: get_text_char = CH_I;
                    3'd5: get_text_char = CH_N;
                    3'd6: get_text_char = CH_G;
                    default: get_text_char = CH_W;
                endcase
            end
        end
    endfunction

    // ----------------
    // 5x7 font ROM
    // bit[4]가 왼쪽 픽셀, bit[0]이 오른쪽 픽셀
    // ----------------
    function automatic logic [4:0] font_5x7 (
        input logic [3:0] ch,
        input logic [2:0] row
    );
        begin
            font_5x7 = 5'b00000;

            case (ch)
                CH_E: begin
                    case (row)
                        3'd0: font_5x7 = 5'b11111;
                        3'd1: font_5x7 = 5'b10000;
                        3'd2: font_5x7 = 5'b10000;
                        3'd3: font_5x7 = 5'b11110;
                        3'd4: font_5x7 = 5'b10000;
                        3'd5: font_5x7 = 5'b10000;
                        3'd6: font_5x7 = 5'b11111;
                        default: font_5x7 = 5'b00000;
                    endcase
                end

                CH_N: begin
                    case (row)
                        3'd0: font_5x7 = 5'b10001;
                        3'd1: font_5x7 = 5'b11001;
                        3'd2: font_5x7 = 5'b10101;
                        3'd3: font_5x7 = 5'b10011;
                        3'd4: font_5x7 = 5'b10001;
                        3'd5: font_5x7 = 5'b10001;
                        3'd6: font_5x7 = 5'b10001;
                        default: font_5x7 = 5'b00000;
                    endcase
                end

                CH_M: begin
                    case (row)
                        3'd0: font_5x7 = 5'b10001;
                        3'd1: font_5x7 = 5'b11011;
                        3'd2: font_5x7 = 5'b10101;
                        3'd3: font_5x7 = 5'b10101;
                        3'd4: font_5x7 = 5'b10001;
                        3'd5: font_5x7 = 5'b10001;
                        3'd6: font_5x7 = 5'b10001;
                        default: font_5x7 = 5'b00000;
                    endcase
                end

                CH_Y: begin
                    case (row)
                        3'd0: font_5x7 = 5'b10001;
                        3'd1: font_5x7 = 5'b01010;
                        3'd2: font_5x7 = 5'b00100;
                        3'd3: font_5x7 = 5'b00100;
                        3'd4: font_5x7 = 5'b00100;
                        3'd5: font_5x7 = 5'b00100;
                        3'd6: font_5x7 = 5'b00100;
                        default: font_5x7 = 5'b00000;
                    endcase
                end

                CH_W: begin
                    case (row)
                        3'd0: font_5x7 = 5'b10001;
                        3'd1: font_5x7 = 5'b10001;
                        3'd2: font_5x7 = 5'b10001;
                        3'd3: font_5x7 = 5'b10101;
                        3'd4: font_5x7 = 5'b10101;
                        3'd5: font_5x7 = 5'b10101;
                        3'd6: font_5x7 = 5'b01010;
                        default: font_5x7 = 5'b00000;
                    endcase
                end

                CH_A: begin
                    case (row)
                        3'd0: font_5x7 = 5'b01110;
                        3'd1: font_5x7 = 5'b10001;
                        3'd2: font_5x7 = 5'b10001;
                        3'd3: font_5x7 = 5'b11111;
                        3'd4: font_5x7 = 5'b10001;
                        3'd5: font_5x7 = 5'b10001;
                        3'd6: font_5x7 = 5'b10001;
                        default: font_5x7 = 5'b00000;
                    endcase
                end

                CH_R: begin
                    case (row)
                        3'd0: font_5x7 = 5'b11110;
                        3'd1: font_5x7 = 5'b10001;
                        3'd2: font_5x7 = 5'b10001;
                        3'd3: font_5x7 = 5'b11110;
                        3'd4: font_5x7 = 5'b10100;
                        3'd5: font_5x7 = 5'b10010;
                        3'd6: font_5x7 = 5'b10001;
                        default: font_5x7 = 5'b00000;
                    endcase
                end

                CH_I: begin
                    case (row)
                        3'd0: font_5x7 = 5'b11111;
                        3'd1: font_5x7 = 5'b00100;
                        3'd2: font_5x7 = 5'b00100;
                        3'd3: font_5x7 = 5'b00100;
                        3'd4: font_5x7 = 5'b00100;
                        3'd5: font_5x7 = 5'b00100;
                        3'd6: font_5x7 = 5'b11111;
                        default: font_5x7 = 5'b00000;
                    endcase
                end

                CH_G: begin
                    case (row)
                        3'd0: font_5x7 = 5'b01111;
                        3'd1: font_5x7 = 5'b10000;
                        3'd2: font_5x7 = 5'b10000;
                        3'd3: font_5x7 = 5'b10011;
                        3'd4: font_5x7 = 5'b10001;
                        3'd5: font_5x7 = 5'b10001;
                        3'd6: font_5x7 = 5'b01110;
                        default: font_5x7 = 5'b00000;
                    endcase
                end

                default: begin
                    font_5x7 = 5'b00000;
                end
            endcase
        end
    endfunction

    // 현재 text 위치 계산
    always_comb begin
        text_char_count = (op_reg == OP_TEXT_ENEMY) ? 4'd5 : 4'd7;
        text_char_code  = get_text_char(op_reg, text_char_idx);
        font_bits       = font_5x7(text_char_code, text_row);

        // x offset = char_idx * 6 + text_col
        text_x_calc =
            {1'b0, x_start_reg}
            + ({4'd0, text_char_idx} << 2)
            + ({4'd0, text_char_idx} << 1)
            + {7'd0, text_col};

        text_y_calc = {1'b0, y_start_reg} + {6'd0, text_row};

        case (text_col)
            3'd0: text_pixel_on = font_bits[4];
            3'd1: text_pixel_on = font_bits[3];
            3'd2: text_pixel_on = font_bits[2];
            3'd3: text_pixel_on = font_bits[1];
            3'd4: text_pixel_on = font_bits[0];
            default: text_pixel_on = 1'b0;   // 글자 간격
        endcase

        text_in_bounds =
            (text_x_calc < IMG_W) &&
            (text_y_calc < IMG_H);

        text_step =
            (state == S_TEXT) &&
            (
                !text_pixel_on ||
                !text_in_bounds ||
                (pix_valid && pix_ready)
            );
    end

    // ================================
    // Pixel output mux
    // ================================
    always_comb begin
        pix_valid = 1'b0;
        pix_x     = 9'd0;
        pix_y     = 8'd0;
        pix_type  = type_reg;

        case (state)
            S_LINE: begin
                pix_valid = line_should_draw && line_in_bounds;
                pix_x     = line_x_calc[8:0];
                pix_y     = line_y_calc[7:0];
                pix_type  = type_reg;
            end

            S_TEXT: begin
                pix_valid = text_pixel_on && text_in_bounds;
                pix_x     = text_x_calc[8:0];
                pix_y     = text_y_calc[7:0];

                // ENEMY/WARNING 글자는 enemy 색상으로 출력
                pix_type  = 1'b0;
            end

            default: begin
                pix_valid = 1'b0;
                pix_x     = 9'd0;
                pix_y     = 8'd0;
                pix_type  = type_reg;
            end
        endcase
    end

    // ================================
    // FIFO read control
    // ================================
    assign instr_fifo_rd_en = (state == S_IDLE) && !instr_fifo_empty;

    // ================================
    // Sequential logic
    // ================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;

            op_reg        <= OP_HLINE;
            x_start_reg   <= 9'd0;
            y_start_reg   <= 8'd0;
            length_reg    <= 9'd1;
            dash_on_reg   <= 4'd8;
            dash_off_reg  <= 4'd8;
            type_reg      <= 1'b0;

            line_idx      <= 9'd0;
            dash_count    <= 4'd0;
            dash_draw     <= 1'b1;

            text_row      <= 3'd0;
            text_char_idx <= 3'd0;
            text_col      <= 3'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    line_idx      <= 9'd0;
                    dash_count    <= 4'd0;
                    dash_draw     <= 1'b1;

                    text_row      <= 3'd0;
                    text_char_idx <= 3'd0;
                    text_col      <= 3'd0;

                    if (!instr_fifo_empty) begin
                        op_reg        <= fifo_op;
                        x_start_reg   <= fifo_x_start;
                        y_start_reg   <= fifo_y_start;
                        length_reg    <= (fifo_length == 9'd0) ? 9'd1 : fifo_length;
                        dash_on_reg   <= fifo_dash_on;
                        dash_off_reg  <= fifo_dash_off;
                        type_reg      <= fifo_type;

                        if ((fifo_op == OP_HLINE) || (fifo_op == OP_VLINE)) begin
                            state <= S_LINE;
                        end else begin
                            state <= S_TEXT;
                        end
                    end
                end

                S_LINE: begin
                    if (line_step) begin
                        if (line_idx == length_reg - 9'd1) begin
                            state <= S_IDLE;
                        end else begin
                            line_idx <= line_idx + 9'd1;

                            if (dash_off_reg == 4'd0) begin
                                dash_draw  <= 1'b1;
                                dash_count <= 4'd0;
                            end else begin
                                if (dash_draw) begin
                                    if (dash_count == dash_on_reg - 4'd1) begin
                                        dash_count <= 4'd0;
                                        dash_draw  <= 1'b0;
                                    end else begin
                                        dash_count <= dash_count + 4'd1;
                                    end
                                end else begin
                                    if (dash_count == dash_off_reg - 4'd1) begin
                                        dash_count <= 4'd0;
                                        dash_draw  <= 1'b1;
                                    end else begin
                                        dash_count <= dash_count + 4'd1;
                                    end
                                end
                            end
                        end
                    end
                end

                S_TEXT: begin
                    if (text_step) begin
                        if (text_col == 3'd5) begin
                            text_col <= 3'd0;

                            if (text_char_idx == text_char_count[2:0] - 3'd1) begin
                                text_char_idx <= 3'd0;

                                if (text_row == 3'd6) begin
                                    state <= S_IDLE;
                                end else begin
                                    text_row <= text_row + 3'd1;
                                end
                            end else begin
                                text_char_idx <= text_char_idx + 3'd1;
                            end
                        end else begin
                            text_col <= text_col + 3'd1;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule