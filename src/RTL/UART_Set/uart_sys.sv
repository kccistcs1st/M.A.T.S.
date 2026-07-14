`timescale 1ns / 1ps

module UART_Set #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int WAIT_FRAME = 20
) (
    input  logic clk,
    input  logic rst,
    output logic uart_tx,

    input  logic target_valid,
    input  logic target_type,  // 0: enemy, 1: friend
    input  logic [$clog2(WIDTH)-1:0] center_x,
    input  logic [$clog2(HEIGHT)-1:0] center_y,
    input  logic [$clog2(WIDTH)-1:0] target_width,
    input  logic [$clog2(HEIGHT)-1:0] target_height,

    input  logic frame_end
);
    wire w_b_tick_115200_16sam;
    wire w_tx_done, w_tx_busy;
    wire w_fifo_empty, w_fifo_full;
    wire [7:0] w_tx_data;

    localparam int BITWIDTH_WIDTH    = $clog2(WIDTH);
    localparam int BITWIDTH_HEIGHT   = $clog2(HEIGHT);

    localparam int BITWIDTH_DATA = 8+BITWIDTH_WIDTH+BITWIDTH_HEIGHT 
                                    +BITWIDTH_WIDTH+BITWIDTH_HEIGHT
                                    +1+1+4;

    wire [BITWIDTH_DATA-1:0] in_data, fifo_pop_data;
    assign in_data = { 8'hFF, target_height, target_width, center_y, center_x, target_type, frame_end, 4'b1111 };

    wire data_spliter_done;
    
    // 20 frame counter
    localparam int BITWIDTH_WAIT_FRAME = $clog2(WAIT_FRAME);
    reg [BITWIDTH_WAIT_FRAME-1:0] frame_counter;
    reg                           insert_active;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_counter <= 0;
            insert_active <= 1'b0;
        end
        else begin
            if (frame_end) begin
                if (frame_counter == (WAIT_FRAME-1)) begin
                    frame_counter <= 0;
                    insert_active <= 1'b1;
                end
                else begin
                    frame_counter <= frame_counter+1;
                    insert_active <= 1'b0;
                end
            end
        end
    end

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

    // frame_end의 rising edge만 추출 (만약을 대비해)
    reg frame_end_d;
    always @(posedge clk or posedge rst) begin
        if (rst) frame_end_d <= 1'b0;
        else     frame_end_d <= frame_end;
    end

    reg target_valid_d;
    always @(posedge clk or posedge rst) begin
        if (rst) target_valid_d <= 1'b0;
        else     target_valid_d <= target_valid;
    end
    
    wire valid_pulse = target_valid & ~target_valid_d;

    // FIFO 연결 부분 수정 (push 조건 변경)
    fifo #(
        .DEPTH     (32),
        .BIT_WIDTH (BITWIDTH_DATA)
    ) U_INFO_FIFO (
        .clk       (clk),
        .rst       (rst),
        // 변경된 push: valid가 뜨는 순간 딱 1번 OR 프레임 끝날 때 딱 1번
        .push      ( insert_active & (valid_pulse | frame_end_d) ), 
        .pop       (data_spliter_done),
        .push_data (in_data),
        .pop_data  (fifo_pop_data),
        .full      (w_fifo_full),
        .empty     (w_fifo_empty)
    );

    uart_tx U_UART_TX (
        .clk(clk),
        .rst(rst),
        .tx_start( ~w_fifo_empty & ~w_tx_done & ~data_spliter_done ),
        .b_tick(w_b_tick_115200_16sam),
        .tx_data(w_tx_data),
        .uart_tx(uart_tx),
        .tx_busy(w_tx_busy),
        .tx_done(w_tx_done)
    );

    baud_tick_sampling_divide U_BAUD_TICK (
        .clk(clk),
        .rst(rst),
        .b_tick(w_b_tick_115200_16sam)
    );

endmodule

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
        // i_updata가 들어오는 순간, 다음 cycle의 seq 값을 미리 계산하여 데이터 출력에 반영
        if (state == ACTIVE && i_updata) begin
            current_seq = (seq_reg == MAX_SEQ_CYCLE) ? 0 : seq_reg + 1;
        end else begin
            current_seq = seq_reg;
        end

        o_data = i_data[(OUT_DATA_WIDTH*current_seq) +: OUT_DATA_WIDTH];

        case(state)
            // ... (기존 case 문과 동일하게 유지) ...
            IDLE  : begin
                seq_next   = 0;
                state_next = (i_start)? ACTIVE : IDLE;
                o_done     = 1'b0;
            end
            ACTIVE: begin
                if (i_updata) begin
                    seq_next   = (seq_reg == MAX_SEQ_CYCLE)? 0 : seq_reg+1;
                    state_next = (seq_reg == MAX_SEQ_CYCLE)? FINAL : ACTIVE;
                end
                else begin
                    seq_next   = seq_reg;
                    state_next = ACTIVE;
                end
                o_done     = 1'b0;
            end
            FINAL : begin
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

// USE PISO (PARALLEL INPUT SERIAL OUTPUT)
module uart_tx (
    input clk,
    input rst,
    input tx_start,
    input b_tick,  // *16
    input [7:0] tx_data,
    output tx_busy,
    output tx_done,
    output uart_tx
);

    // State
    localparam IDLE = 2'd0, START = 2'd1;
    localparam DATA = 2'd2, STOP = 2'd3;

    // state, counter reg
    reg [1:0] c_state, n_state;
    reg tx_reg, tx_next;
    reg [3:0] b_tick_cnt_reg, next_b_tick_cnt;
    reg [2:0] bit_cnt_reg, next_bit_cnt;
    // busy, done
    reg busy_reg, busy_next, done_reg, done_next;
    // data_in_buf
    reg [7:0] data_in_buf_reg, data_in_buf_next;

    assign uart_tx = tx_reg;
    assign tx_busy = busy_reg;
    assign tx_done = done_reg;

    // SL
    always @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state <= IDLE;
            tx_reg <= 1'b1;
            b_tick_cnt_reg <= 4'b0000;
            bit_cnt_reg <= 1'b0;
            busy_reg <= 1'b0;
            done_reg <= 1'b0;
            data_in_buf_reg <= 8'h00;
        end else begin
            c_state <= n_state;
            tx_reg <= tx_next;
            b_tick_cnt_reg <= next_b_tick_cnt;
            bit_cnt_reg <= next_bit_cnt;
            busy_reg <= busy_next;
            done_reg <= done_next;
            data_in_buf_reg <= data_in_buf_next;
        end
    end

    // next CL
    always @(*) begin
        n_state = c_state;

        tx_next = tx_reg;

        next_b_tick_cnt = b_tick_cnt_reg;
        next_bit_cnt = bit_cnt_reg;

        busy_next = busy_reg;
        done_next = done_reg;

        data_in_buf_next = data_in_buf_reg;
        case (c_state)
            IDLE: begin
                tx_next = 1'b1;

                next_bit_cnt = 0;
                next_b_tick_cnt = 0;

                busy_next = 1'b0;
                done_next = 1'b0;
                if (tx_start) begin
                    n_state = START;
                    busy_next = 1'b1;
                    data_in_buf_next = tx_data;
                end
            end
            START: begin
                // TO START UART FRAME OF START BIT
                tx_next = 1'b0;

                if (b_tick) begin
                    next_b_tick_cnt = b_tick_cnt_reg + 1;
                    if (b_tick_cnt_reg == 4'd15) begin
                        n_state = DATA;
                    end
                end
            end
            DATA: begin
                tx_next = data_in_buf_reg[0];

                if (b_tick) begin
                    next_b_tick_cnt = b_tick_cnt_reg + 1;

                    if (b_tick_cnt_reg == 15) begin
                        data_in_buf_next = {1'b0, data_in_buf_reg[7:1]};
                        next_bit_cnt = bit_cnt_reg + 1;
                        next_b_tick_cnt = 4'h0;

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

module baud_tick_sampling_divide (
    input clk,
    input rst,
    output reg b_tick
);
    parameter BAUDRATE = 115200;
    parameter SAMPLING = 16;
    parameter F_COUNT = 100_000_000 / (BAUDRATE * SAMPLING);

    // reg for counter
    reg [$clog2(F_COUNT)-1:0] counter_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == (F_COUNT - 1)) begin
                b_tick <= 1'b1;
                counter_reg <= 0;
            end else begin
                b_tick <= 1'b0;
            end
        end
    end
endmodule

`timescale 1ns / 1ps
module fifo #(
    parameter DEPTH = 8,
    parameter BIT_WIDTH = 8
) (
    input                           clk,
    input                           rst,
    input                           push,
    input                           pop,
    input      [BIT_WIDTH-1:0]      push_data,
    output     [BIT_WIDTH-1:0]      pop_data,
    output                          full,
    output                          empty
);
    
    wire [$clog2(DEPTH)-1:0] wptr;
    wire [$clog2(DEPTH)-1:0] rptr;
    wire                     we;
    
    assign we = (~full) & push;

    register_file #(.DEPTH(DEPTH), .BIT_WIDTH(BIT_WIDTH))
        U_REG_FI (
                    .clk(clk),
                    .r_addr(rptr),
                    .w_addr(wptr),
                    .we(we),
                    .push_data(push_data),
                    .pop_data(pop_data)
    );

    control_unit #(.DEPTH(DEPTH)) 
        U_CTRL_UNIT(
            .clk    (clk),
            .rst    (rst),
            .push   (push),
            .pop    (pop),
            .wptr   (wptr),
            .rptr   (rptr),
            .full   (full),
            .empty  (empty)
    );

endmodule

module register_file #(
    parameter DEPTH = 4,
    parameter BIT_WIDTH = 8
) (
    input                           clk,
    input      [$clog2(DEPTH)-1:0]  r_addr,
    input      [$clog2(DEPTH)-1:0]  w_addr,
    input                           we,
    input      [BIT_WIDTH-1:0]      push_data,
    output     [BIT_WIDTH-1:0]      pop_data
);
    reg [BIT_WIDTH-1:0] register_file [0:DEPTH-1];

    // push (write) => Register file
    always @(posedge clk) begin
        if (we) register_file[w_addr] <= push_data; // push
        //else pop_data <= register_file[r_addr];
    end

    // read
    assign pop_data = register_file[r_addr];

endmodule

module control_unit #(
    parameter DEPTH = 4
) (
    input                           clk,
    input                           rst,
    input                           push,
    input                           pop,
    output     [$clog2(DEPTH)-1:0]  wptr,
    output     [$clog2(DEPTH)-1:0]  rptr,
    output                          full,
    output                          empty
);  
    reg [1:0] c_state, n_state;

    // pointer registers
    reg [$clog2(DEPTH)-1:0] wptr_reg, wptr_next;
    reg [$clog2(DEPTH)-1:0] rptr_reg, rptr_next;
    reg full_reg, full_next;
    reg empty_reg, empty_next;
    assign wptr = wptr_reg;
    assign rptr = rptr_reg;
    assign full = full_reg;
    assign empty = empty_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state <= 2'b00;
            
            wptr_reg <= 0;
            rptr_reg <= 0;
            full_reg <= 0;
            empty_reg <= 1;
        end
        else begin
            c_state <= n_state;

            wptr_reg <= wptr_next;
            rptr_reg <= rptr_next;
            full_reg <= full_next;
            empty_reg <= empty_next;
        end
    end

    // next st, output
    always @(*) begin
        n_state = c_state;
        
        wptr_next = wptr_reg;
        rptr_next = rptr_reg;
        full_next = full_reg;
        empty_next = empty_reg;
        
        case ({push, pop})
            2'b10: begin
                // push only
                if (!full_reg) begin
                    wptr_next = wptr_reg + 1;
                    empty_next = 1'b0;
                    if (wptr_next == rptr_reg) begin
                        full_next = 1'b1;
                    end
                end
            end
            2'b01: begin
                // pop only
                if (!empty_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                    if (wptr_reg == rptr_next) begin
                        empty_next = 1'b1;
                    end
                end
            end
            2'b11: begin
                // push pop at same time
                if (full_reg == 1) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                end
                else if (empty_reg == 1) begin
                    wptr_next = wptr_reg + 1;
                    empty_next = 1'b0;
                end
                else begin
                    wptr_next = wptr_reg + 1;
                    rptr_next = rptr_reg + 1;
                end
            end
        endcase
    end

endmodule

