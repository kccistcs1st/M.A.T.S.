`timescale 1ns / 1ps

module instruction_generator (
    input  logic clk,
    input  logic reset,

    // from box_coord_calc
    input  logic       box_valid,
    output logic       box_ready,

    input  logic [8:0] box_x0,     // left
    input  logic [7:0] box_y0,     // top
    input  logic [8:0] box_x1,     // right
    input  logic [7:0] box_y1,     // bottom
    input  logic       box_type,   // 0: enemy, 1: friend

    // to instruction FIFO
    output logic       instr_valid,
    input  logic       instr_ready,

    output logic [1:0] instr_op, //  operation: 가로, 세로, 글자
    output logic [8:0] instr_x_start,
    output logic [7:0] instr_y_start,
    output logic [8:0] instr_length,
    output logic [3:0] instr_dash_on,
    output logic [3:0] instr_dash_off,
    output logic       instr_type    // 0: enemy, 1: friend
);

    // Instruction op code
    localparam logic [1:0] OP_HLINE        = 2'd0;
    localparam logic [1:0] OP_VLINE        = 2'd1;
    localparam logic [1:0] OP_TEXT_ENEMY   = 2'd2;
    localparam logic [1:0] OP_TEXT_WARNING = 2'd3;

    // Dash pattern
    localparam logic [3:0] DASH_ON  = 4'd8;
    localparam logic [3:0] DASH_OFF = 4'd8;

    // Text position
    // 5x7 font + 1 pixel spacing
    // 한 글자 폭 = 6 pixel
    localparam logic [7:0] TEXT_UP_OFFSET   = 8'd12;
    localparam logic [7:0] TEXT_DOWN_OFFSET = 8'd4;

    localparam int CHAR_PITCH         = 6;
    localparam int ENEMY_CHAR_COUNT   = 5;
    localparam int WARNING_CHAR_COUNT = 7;

    localparam int ENEMY_TEXT_WIDTH =
        ENEMY_CHAR_COUNT * CHAR_PITCH;       // 30 pixel

    localparam int WARNING_TEXT_WIDTH =
        WARNING_CHAR_COUNT * CHAR_PITCH;     // 42 pixel

    localparam int ENEMY_HALF_WIDTH =
        ENEMY_TEXT_WIDTH / 2;                // 15 pixel

    localparam int WARNING_HALF_WIDTH =
        WARNING_TEXT_WIDTH / 2;              // 21 pixel


    // FSM state
    typedef enum logic [2:0] {
        S_IDLE,
        S_TOP,
        S_BOTTOM,
        S_LEFT,
        S_RIGHT,
        S_TEXT_ENEMY,
        S_TEXT_WARNING
    } state_t;

    state_t state;


    // Saved box information
    logic [8:0] x0_reg;
    logic [7:0] y0_reg;
    logic [8:0] x1_reg;
    logic [7:0] y1_reg;
    logic       type_reg;

    logic [8:0] box_width;
    logic [8:0] box_height;
    logic [9:0] box_center_sum;
    logic [8:0] box_center_x;

    // width = x1 - x0 + 1
    assign box_width =
        (x1_reg >= x0_reg)
        ? (x1_reg - x0_reg + 9'd1)
        : 9'd1;

    // height = y1 - y0 + 1
    assign box_height =
        (y1_reg >= y0_reg)
        ? ({1'b0, y1_reg} - {1'b0, y0_reg} + 9'd1)
        : 9'd1;

    // x0 + x1은 최대 638이므로 10bit로 계산
    assign box_center_sum =
        {1'b0, x0_reg} + {1'b0, x1_reg};

    assign box_center_x =
        box_center_sum[9:1];

    // IDLE일 때만 새로운 box 입력 가능
    assign box_ready = (state == S_IDLE);

    // IDLE이 아니면 instruction 출력 중
    assign instr_valid = (state != S_IDLE);


    // Output instruction logic
    always_comb begin
        // default
        instr_op        = OP_HLINE;
        instr_x_start   = 9'd0;
        instr_y_start   = 8'd0;
        instr_length    = 9'd1;
        instr_dash_on   = DASH_ON;
        instr_dash_off  = DASH_OFF;
        instr_type      = type_reg;

        case (state)

            // 위쪽 점선 테두리
            S_TOP: begin
                instr_op       = OP_HLINE;
                instr_x_start  = x0_reg;
                instr_y_start  = y0_reg;
                instr_length   = box_width;
                instr_dash_on  = DASH_ON;
                instr_dash_off = DASH_OFF;
                instr_type     = type_reg;
            end

            // 아래쪽 점선 테두리
            S_BOTTOM: begin
                instr_op       = OP_HLINE;
                instr_x_start  = x0_reg;
                instr_y_start  = y1_reg;
                instr_length   = box_width;
                instr_dash_on  = DASH_ON;
                instr_dash_off = DASH_OFF;
                instr_type     = type_reg;
            end

            // 왼쪽 점선 테두리
            S_LEFT: begin
                instr_op       = OP_VLINE;
                instr_x_start  = x0_reg;
                instr_y_start  = y0_reg;
                instr_length   = box_height;
                instr_dash_on  = DASH_ON;
                instr_dash_off = DASH_OFF;
                instr_type     = type_reg;
            end

            // 오른쪽 점선 테두리
            S_RIGHT: begin
                instr_op       = OP_VLINE;
                instr_x_start  = x1_reg;
                instr_y_start  = y0_reg;
                instr_length   = box_height;
                instr_dash_on  = DASH_ON;
                instr_dash_off = DASH_OFF;
                instr_type     = type_reg;
            end

            // enemy일 때만 생성되는 ENEMY text instruction
            S_TEXT_ENEMY: begin
                instr_op = OP_TEXT_ENEMY;

                // 박스 중심 기준 ENEMY 가운데 정렬
                if (box_center_x >= ENEMY_HALF_WIDTH)
                    instr_x_start =
                        box_center_x - ENEMY_HALF_WIDTH;
                else
                    instr_x_start = 9'd0;

                // 박스 위에 공간이 있으면 위쪽에 표시
                if (y0_reg > TEXT_UP_OFFSET)
                    instr_y_start =
                        y0_reg - TEXT_UP_OFFSET;
                else
                    instr_y_start = y0_reg;

                // ENEMY = 5글자
                instr_length = 9'd5;

                // text에서는 dash 정보 사용 안 함
                instr_dash_on  = 4'd0;
                instr_dash_off = 4'd0;

                // enemy text는 빨간색
                instr_type = 1'b0;
            end

            // enemy일 때만 생성되는 WARNING text instruction
            S_TEXT_WARNING: begin
                instr_op = OP_TEXT_WARNING;

                // 박스 중심 기준 WARNING 가운데 정렬
                if (box_center_x >= WARNING_HALF_WIDTH)
                    instr_x_start =
                        box_center_x - WARNING_HALF_WIDTH;
                else
                    instr_x_start = 9'd0;

                // 박스 아래에 공간이 있으면 아래쪽에 표시
                if (y1_reg < 8'd230)
                    instr_y_start =
                        y1_reg + TEXT_DOWN_OFFSET;
                else
                    instr_y_start = y1_reg;

                // WARNING = 7글자
                instr_length = 9'd7;

                // text에서는 dash 정보 사용 안 함
                instr_dash_on  = 4'd0;
                instr_dash_off = 4'd0;

                // warning text는 빨간색
                instr_type = 1'b0;
            end

            default: begin
                instr_op       = OP_HLINE;
                instr_x_start  = 9'd0;
                instr_y_start  = 8'd0;
                instr_length   = 9'd1;
                instr_dash_on  = DASH_ON;
                instr_dash_off = DASH_OFF;
                instr_type     = type_reg;
            end
        endcase
    end


    // FSM sequential logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state    <= S_IDLE;
            x0_reg   <= 9'd0;
            y0_reg   <= 8'd0;
            x1_reg   <= 9'd0;
            y1_reg   <= 8'd0;
            type_reg <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (box_valid && box_ready) begin
                        x0_reg   <= box_x0;
                        y0_reg   <= box_y0;
                        x1_reg   <= box_x1;
                        y1_reg   <= box_y1;
                        type_reg <= box_type;
                        state <= S_TOP;
                    end
                end

                S_TOP: begin
                    if (instr_valid && instr_ready)
                        state <= S_BOTTOM;
                end

                S_BOTTOM: begin
                    if (instr_valid && instr_ready)
                        state <= S_LEFT;
                end

                S_LEFT: begin
                    if (instr_valid && instr_ready)
                        state <= S_RIGHT;
                end

                S_RIGHT: begin
                    if (instr_valid && instr_ready) begin
                        if (type_reg == 1'b0)
                            state <= S_TEXT_ENEMY;
                        else
                            state <= S_IDLE;
                    end
                end

                S_TEXT_ENEMY: begin
                    if (instr_valid && instr_ready)
                        state <= S_TEXT_WARNING;
                end

                S_TEXT_WARNING: begin
                    if (instr_valid && instr_ready)
                        state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule