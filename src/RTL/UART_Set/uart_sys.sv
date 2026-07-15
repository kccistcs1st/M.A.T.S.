`timescale 1ns / 1ps

module UART_Set #(
    parameter int WIDTH      = 320,
    parameter int HEIGHT     = 240,
    parameter int WAIT_FRAME = 10,
    parameter int CLK_FREQ   = 100_000_000, // 메인 시스템 클럭: 100MHz
    parameter int BAUDRATE   = 115200         // UART 통신 속도
) (
    input  logic clk,     // 100MHz Main System Clock
    input  logic rst,     // Asynchronous Active-High Reset
    output logic uart_tx,

    // 25MHz Input Reference Clock
    input  logic clk_25m, // 25MHz 외부 입력 클럭

    // 25MHz Clock Domain Inputs (Synchronous to clk_25m)
    input  logic target_valid,
    input  logic target_type,  // 0: enemy, 1: friend
    input  logic [$clog2(WIDTH)-1:0] center_x,
    input  logic [$clog2(HEIGHT)-1:0] center_y,
    input  logic [$clog2(WIDTH)-1:0] target_width,
    input  logic [$clog2(HEIGHT)-1:0] target_height,
    input  logic frame_end
);

    localparam int BITWIDTH_WIDTH  = $clog2(WIDTH);
    localparam int BITWIDTH_HEIGHT = $clog2(HEIGHT);

    //---------------------------------------------------------------------
    // 1. 25MHz Domain Registering (입력 신호 안정화)
    //---------------------------------------------------------------------
    logic                        target_valid_25m;
    logic                        target_type_25m;
    logic [BITWIDTH_WIDTH-1:0]   center_x_25m;
    logic [BITWIDTH_HEIGHT-1:0]  center_y_25m;
    logic [BITWIDTH_WIDTH-1:0]   target_width_25m;
    logic [BITWIDTH_HEIGHT-1:0]  target_height_25m;
    logic                        frame_end_25m;

    always_ff @(posedge clk_25m or posedge rst) begin
        if (rst) begin
            target_valid_25m  <= 1'b0;
            target_type_25m   <= 1'b0;
            center_x_25m      <= 0;
            center_y_25m      <= 0;
            target_width_25m  <= 0;
            target_height_25m <= 0;
            frame_end_25m     <= 1'b0;
        end else begin
            target_valid_25m  <= target_valid;
            target_type_25m   <= target_type;
            center_x_25m      <= center_x;
            center_y_25m      <= center_y;
            target_width_25m  <= target_width;
            target_height_25m <= target_height;
            frame_end_25m     <= frame_end;
        end
    end

    //---------------------------------------------------------------------
    // 2. clk_25m Clock Edge Detection in 100MHz Domain (CDC Bridge)
    //---------------------------------------------------------------------
    logic clk_25m_sync0, clk_25m_sync1, clk_25m_sync2;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_25m_sync0 <= 1'b0;
            clk_25m_sync1 <= 1'b0;
            clk_25m_sync2 <= 1'b0;
        end else begin
            clk_25m_sync0 <= clk_25m;
            clk_25m_sync1 <= clk_25m_sync0;
            clk_25m_sync2 <= clk_25m_sync1;
        end
    end

    // 100MHz 도메인 기준, 25MHz 클럭의 상승 엣지 때 딱 1클럭만 High가 되는 펄스 생성
    wire clk_25m_edge = clk_25m_sync1 && !clk_25m_sync2;

    //---------------------------------------------------------------------
    // 3. Safe 100MHz Domain Data Capture & 1-Cycle Pulse conversion
    //---------------------------------------------------------------------
    logic                        target_valid_100m;
    logic                        target_type_100m;
    logic [BITWIDTH_WIDTH-1:0]   center_x_100m;
    logic [BITWIDTH_HEIGHT-1:0]  center_y_100m;
    logic [BITWIDTH_WIDTH-1:0]   target_width_100m;
    logic [BITWIDTH_HEIGHT-1:0]  target_height_100m;
    logic                        frame_end_100m;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            target_valid_100m  <= 1'b0;
            frame_end_100m     <= 1'b0;
            target_type_100m   <= 1'b0;
            center_x_100m      <= 0;
            center_y_100m      <= 0;
            target_width_100m  <= 0;
            target_height_100m <= 0;
        end else begin
            if (clk_25m_edge) begin
                // 25MHz 클럭의 상승 엣지 시점에 안전하게 샘플링
                target_valid_100m  <= target_valid_25m;
                frame_end_100m     <= frame_end_25m;
                
                target_type_100m   <= target_type_25m;
                center_x_100m      <= center_x_25m;
                center_y_100m      <= center_y_25m;
                target_width_100m  <= target_width_25m;
                target_height_100m <= target_height_25m;
            end else begin
                // 제어 신호들은 1클럭 뒤 자동으로 0으로 떨어뜨려 100MHz의 1-cycle pulse로 가공
                target_valid_100m  <= 1'b0;
                frame_end_100m     <= 1'b0;
                
                // 데이터 버스 신호들은 다음 샘플링 주기까지 값을 계속 유지(Hold)
            end
        end
    end

    //---------------------------------------------------------------------
    // 4. Internal Data Path & Sub-sampling Control (100MHz Domain)
    //---------------------------------------------------------------------
    wire w_b_tick_16sam;
    wire w_tx_done, w_tx_busy;
    wire w_fifo_empty, w_fifo_full;
    wire [7:0] w_tx_data;

    localparam int BITWIDTH_DATA = 8 + BITWIDTH_HEIGHT + BITWIDTH_WIDTH 
                                     + BITWIDTH_HEIGHT + BITWIDTH_WIDTH 
                                     + 1 + 1 + 4;
                                     
    wire [BITWIDTH_DATA-1:0] in_data, fifo_pop_data;
    
    // 100MHz 도메인의 신호들로 패킷 구성
    assign in_data = { 8'hFF, target_height_100m, target_width_100m, center_y_100m, center_x_100m, target_type_100m, frame_end_100m, 4'b1111 };

    wire data_spliter_done;

    // Sub-sampling Frame Counter
    localparam int BITWIDTH_WAIT_FRAME = $clog2(WAIT_FRAME);
    reg [BITWIDTH_WAIT_FRAME-1:0] frame_counter;
    reg                           insert_active;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_counter <= 0;
            insert_active <= 1'b0;
        end
        else begin
            if (frame_end_100m) begin
                if (frame_counter == (WAIT_FRAME-1)) begin
                    frame_counter <= 0;
                    insert_active <= 1'b1;
                end
                else begin
                    frame_counter <= frame_counter + 1;
                    insert_active <= 1'b0;
                end
            end
        end
    end

    //---------------------------------------------------------------------
    // 5. Module Instantiations (모두 100MHz clk 기준으로 동작)
    //---------------------------------------------------------------------
    
    // Data Spliter
    data_spliter #(
        .IN_DATA_WIDTH  (BITWIDTH_DATA),
        .OUT_DATA_WIDTH (8)
    ) U_DS (
        .clk      (clk),
        .reset    (rst),
        .i_start  (~w_fifo_empty),
        .i_updata (w_tx_done),
        .i_data   (fifo_pop_data),
        .o_data   (w_tx_data),
        .o_done   (data_spliter_done)
    );

    // Synchronous FIFO Buffer
    fifo #(
        .DEPTH     (32),
        .BIT_WIDTH (BITWIDTH_DATA)
    ) U_INFO_FIFO (
        .clk       (clk),
        .rst       (rst),
        // target_valid_100m과 frame_end_100m은 이미 100MHz 기준 1-cycle Pulse이므로 중복 push 걱정 없음
        .push      ( insert_active & target_valid_100m ), 
        .pop       (data_spliter_done),
        .push_data (in_data),
        .pop_data  (fifo_pop_data),
        .full      (w_fifo_full),
        .empty     (w_fifo_empty)
    );

    // UART Transmitter
    uart_tx U_UART_TX (
        .clk(clk),
        .rst(rst),
        .tx_start( ~w_fifo_empty & ~w_tx_done & ~data_spliter_done ),
        .b_tick(w_b_tick_16sam),
        .tx_data(w_tx_data),
        .uart_tx(uart_tx),
        .tx_busy(w_tx_busy),
        .tx_done(w_tx_done)
    );

    // Baud Rate Generator (반올림 로직 적용)
    baud_tick_sampling_divide #(
        .CLK_FREQ(CLK_FREQ),
        .BAUDRATE(BAUDRATE),
        .SAMPLING(16)
    ) U_BAUD_TICK (
        .clk(clk),
        .rst(rst),
        .b_tick(w_b_tick_16sam)
    );

endmodule


//=====================================================================
// 하위 모듈들 (기존과 동일하게 유지 - 100MHz clk 사용)
//=====================================================================

module data_spliter #(
    parameter int IN_DATA_WIDTH  = 40,
    parameter int OUT_DATA_WIDTH = 8
) (
    input  logic                      clk,
    input  logic                      reset,
    input  logic                      i_start,
    input  logic                      i_updata,
    input  logic [IN_DATA_WIDTH-1:0]  i_data,
    output logic [OUT_DATA_WIDTH-1:0] o_data,
    output logic                      o_done
);
    localparam int SEQ_CYCLE          = IN_DATA_WIDTH / OUT_DATA_WIDTH;
    localparam int MAX_SEQ_CYCLE      = SEQ_CYCLE-1;
    localparam int BITWIDTH_SEQ_CYCLE = $clog2(SEQ_CYCLE);

    reg [BITWIDTH_SEQ_CYCLE-1:0] seq_reg, seq_next;
    reg [1:0]                    state, state_next;

    localparam int IDLE   = 2'd0;
    localparam int ACTIVE = 2'd1;
    localparam int FINAL  = 2'd2;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            seq_reg <= 0;
            state   <= IDLE;
        end
        else begin
            seq_reg <= seq_next;
            state   <= state_next;
        end
    end

    logic [BITWIDTH_SEQ_CYCLE-1:0] current_seq;
    
    always_comb begin
        if (state == ACTIVE && i_updata) begin
            current_seq = (seq_reg == MAX_SEQ_CYCLE) ? 0 : seq_reg + 1;
        end else begin
            current_seq = seq_reg;
        end

        o_data = i_data[(OUT_DATA_WIDTH*current_seq) +: OUT_DATA_WIDTH];

        seq_next   = seq_reg;
        state_next = state;
        o_done     = 1'b0;

        case(state)
            IDLE: begin
                seq_next   = 0;
                state_next = (i_start) ? ACTIVE : IDLE;
                o_done     = 1'b0;
            end
            ACTIVE: begin
                if (i_updata) begin
                    seq_next   = (seq_reg == MAX_SEQ_CYCLE) ? 0 : seq_reg + 1;
                    state_next = (seq_reg == MAX_SEQ_CYCLE) ? FINAL : ACTIVE;
                end
                o_done     = 1'b0;
            end
            FINAL: begin
                seq_next   = 0;
                state_next = IDLE;
                o_done     = 1'b1;
            end
            default: begin
                seq_next   = 0;
                state_next = IDLE;
                o_done     = 1'b0;
            end
        endcase
    end
endmodule


module uart_tx (
    input  logic       clk,
    input  logic       rst,
    input  logic       tx_start,
    input  logic       b_tick,
    input  logic [7:0] tx_data,
    output logic       tx_busy,
    output logic       tx_done,
    output logic       uart_tx
);
    localparam logic [1:0] IDLE  = 2'd0;
    localparam logic [1:0] START = 2'd1;
    localparam logic [1:0] DATA  = 2'd2;
    localparam logic [1:0] STOP  = 2'd3;

    reg [1:0] c_state, n_state;
    reg       tx_reg, tx_next;
    reg [3:0] b_tick_cnt_reg, next_b_tick_cnt;
    reg [2:0] bit_cnt_reg, next_bit_cnt;
    reg       busy_reg, busy_next;
    reg       done_reg, done_next;
    reg [7:0] data_in_buf_reg, data_in_buf_next;

    assign uart_tx = tx_reg;
    assign tx_busy = busy_reg;
    assign tx_done = done_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            c_state         <= IDLE;
            tx_reg          <= 1'b1;
            b_tick_cnt_reg  <= 4'b0000;
            bit_cnt_reg     <= 3'b000;
            busy_reg        <= 1'b0;
            done_reg        <= 1'b0;
            data_in_buf_reg <= 8'h00;
        end else begin
            c_state         <= n_state;
            tx_reg          <= tx_next;
            b_tick_cnt_reg  <= next_b_tick_cnt;
            bit_cnt_reg     <= next_bit_cnt;
            busy_reg        <= busy_next;
            done_reg        <= done_next;
            data_in_buf_reg <= data_in_buf_next;
        end
    end

    always_comb begin
        n_state          = c_state;
        tx_next          = tx_reg;
        next_b_tick_cnt  = b_tick_cnt_reg;
        next_bit_cnt     = bit_cnt_reg;
        busy_next        = busy_reg;
        done_next        = done_reg;
        data_in_buf_next = data_in_buf_reg;

        case (c_state)
            IDLE: begin
                tx_next         = 1'b1;
                next_bit_cnt    = 0;
                next_b_tick_cnt = 0;
                busy_next       = 1'b0;
                done_next       = 1'b0;
                if (tx_start) begin
                    n_state          = START;
                    busy_next        = 1'b1;
                    data_in_buf_next = tx_data;
                end
            end
            START: begin
                tx_next = 1'b0;
                if (b_tick) begin
                    next_b_tick_cnt = b_tick_cnt_reg + 1;
                    if (b_tick_cnt_reg == 4'd15) begin
                        n_state         = DATA;
                        next_b_tick_cnt = 4'h0;
                    end
                end
            end
            DATA: begin
                tx_next = data_in_buf_reg[0];
                if (b_tick) begin
                    next_b_tick_cnt = b_tick_cnt_reg + 1;
                    if (b_tick_cnt_reg == 15) begin
                        data_in_buf_next = {1'b0, data_in_buf_reg[7:1]};
                        next_bit_cnt     = bit_cnt_reg + 1;
                        next_b_tick_cnt  = 4'h0;

                        if (bit_cnt_reg == 7) begin
                            n_state = STOP;
                        end
                    end
                end
            end
            STOP: begin
                tx_next = 1'b1;
                if (b_tick) begin
                    next_b_tick_cnt = b_tick_cnt_reg + 1;
                    if (b_tick_cnt_reg == 15) begin
                        n_state   = IDLE;
                        busy_next = 1'b0;
                        done_next = 1'b1;
                    end
                end
            end
        endcase
    end
endmodule


module baud_tick_sampling_divide #(
    parameter int CLK_FREQ = 100_000_000,
    parameter int BAUDRATE = 9600,
    parameter int SAMPLING = 16
) (
    input  logic clk,
    input  logic rst,
    output logic b_tick
);
    localparam int F_COUNT = (CLK_FREQ + (BAUDRATE * SAMPLING)/2) / (BAUDRATE * SAMPLING);
    
    reg [$clog2(F_COUNT)-1:0] counter_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
            b_tick      <= 1'b0; 
        end else begin
            if (counter_reg == (F_COUNT - 1)) begin
                b_tick      <= 1'b1;
                counter_reg <= 0;
            end else begin
                b_tick      <= 1'b0;
                counter_reg <= counter_reg + 1;
            end
        end
    end
endmodule


module fifo #(
    parameter int DEPTH = 32,
    parameter int BIT_WIDTH = 8
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 push,
    input  logic                 pop,
    input  logic [BIT_WIDTH-1:0] push_data,
    output logic [BIT_WIDTH-1:0] pop_data,
    output logic                 full,
    output logic                 empty
);
    wire [$clog2(DEPTH)-1:0] wptr;
    wire [$clog2(DEPTH)-1:0] rptr;
    wire                     we;
    
    assign we = (~full) & push;

    register_file #(
        .DEPTH(DEPTH),
        .BIT_WIDTH(BIT_WIDTH)
    ) U_REG_FI (
        .clk(clk),
        .r_addr(rptr),
        .w_addr(wptr),
        .we(we),
        .push_data(push_data),
        .pop_data(pop_data)
    );

    control_unit #(
        .DEPTH(DEPTH)
    ) U_CTRL_UNIT (
        .clk(clk),
        .rst(rst),
        .push(push),
        .pop(pop),
        .wptr(wptr),
        .rptr(rptr),
        .full(full),
        .empty(empty)
    );
endmodule


module register_file #(
    parameter int DEPTH = 32,
    parameter int BIT_WIDTH = 8
) (
    input  logic                     clk,
    input  logic [$clog2(DEPTH)-1:0] r_addr,
    input  logic [$clog2(DEPTH)-1:0] w_addr,
    input  logic                     we,
    input  logic [BIT_WIDTH-1:0]     push_data,
    output logic [BIT_WIDTH-1:0]     pop_data
);
    reg [BIT_WIDTH-1:0] register_file [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we) begin
            register_file[w_addr] <= push_data;
        end
    end

    assign pop_data = register_file[r_addr];
endmodule


module control_unit #(
    parameter int DEPTH = 32
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     push,
    input  logic                     pop,
    output logic [$clog2(DEPTH)-1:0] wptr,
    output logic [$clog2(DEPTH)-1:0] rptr,
    output logic                     full,
    output logic                     empty
);
    reg [1:0] c_state, n_state;

    reg [$clog2(DEPTH)-1:0] wptr_reg, wptr_next;
    reg [$clog2(DEPTH)-1:0] rptr_reg, rptr_next;
    reg full_reg, full_next;
    reg empty_reg, empty_next;

    assign wptr  = wptr_reg;
    assign rptr  = rptr_reg;
    assign full  = full_reg;
    assign empty = empty_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            c_state   <= 2'b00;
            wptr_reg  <= 0;
            rptr_reg  <= 0;
            full_reg  <= 1'b0;
            empty_reg <= 1'b1;
        end
        else begin
            c_state   <= n_state;
            wptr_reg  <= wptr_next;
            rptr_reg  <= rptr_next;
            full_reg  <= full_next;
            empty_reg <= empty_next;
        end
    end

    always_comb begin
        n_state    = c_state;
        wptr_next  = wptr_reg;
        rptr_next  = rptr_reg;
        full_next  = full_reg;
        empty_next = empty_reg;

        case ({push, pop})
            2'b10: begin // push only
                if (!full_reg) begin
                    wptr_next = wptr_reg + 1;
                    empty_next = 1'b0;
                    if (wptr_next == rptr_reg) begin
                        full_next = 1'b1;
                    end
                end
            end
            2'b01: begin // pop only
                if (!empty_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                    if (wptr_reg == rptr_next) begin
                        empty_next = 1'b1;
                    end
                end
            end
            2'b11: begin // push & pop (simultaneous)
                if (full_reg == 1'b1) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                end
                else if (empty_reg == 1'b1) begin
                    wptr_next = wptr_reg + 1;
                    empty_next = 1'b0;
                end
                else begin
                    wptr_next = wptr_reg + 1;
                    rptr_next = rptr_reg + 1;
                end
            end
            default: begin
                // No Operation
            end
        endcase
    end
endmodule