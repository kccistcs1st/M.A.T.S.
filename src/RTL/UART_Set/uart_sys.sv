`timescale 1ns / 1ps

module UART_Set #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240
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

    localparam int BITWIDTH_DATA = BITWIDTH_WIDTH+BITWIDTH_HEIGHT 
                                  +BITWIDTH_WIDTH+BITWIDTH_HEIGHT
                                  +1+1+4;

    wire [BITWIDTH_DATA-1:0] in_data, fifo_pop_data;
    assign in_data = { target_height, target_width, center_y, center_x, target_type, frame_end, 4'b1111 };

    wire data_spliter_done;

    data_spliter #(
        .IN_DATA_WIDTH  (BITWIDTH_DATA),
        .OUT_DATA_WIDTH (8)
    ) U_DS (
        .clk      (clk),
        .reset    (rst),
        .i_updata (w_tx_done),
        .i_data   (fifo_pop_data),
        .o_data   (w_tx_data),
        .o_done   (data_spliter_done)
    );

    fifo #(
        .DEPTH     (16),
        .BIT_WIDTH (BITWIDTH_DATA)
    ) U_INFO_FIFO (
        .clk       (clk),
        .rst       (rst),
        .push      (target_valid | frame_end),
        .pop       (data_spliter_done),
        .push_data (in_data),
        .pop_data  (fifo_pop_data),
        .full      (w_fifo_full),
        .empty     (w_fifo_empty)
    );

    uart_tx U_UART_TX (
        .clk(clk),
        .rst(rst),
        .tx_start(~w_fifo_empty),
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

    input  logic                      i_updata,

    input  logic [IN_DATA_WIDTH-1:0]  i_data,
    output logic [OUT_DATA_WIDTH-1:0] o_data,
    output logic                      o_done
);

    localparam int SEQ_CYCLE          = IN_DATA_WIDTH / OUT_DATA_WIDTH;
    localparam int MAX_SEQ_CYCLE      = SEQ_CYCLE-1;
    localparam int BITWIDTH_SEQ_CYCLE = $clog2(SEQ_CYCLE);

    reg [BITWIDTH_SEQ_CYCLE-1:0] seq_reg, seq_next;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            seq_reg <= 0;
        end
        else begin
            seq_reg <= seq_next;
        end
    end

    always_comb begin
        o_data = i_data[(OUT_DATA_WIDTH*seq_reg) +: OUT_DATA_WIDTH];
        if (i_updata) begin
            if (seq_reg == MAX_SEQ_CYCLE) begin
               seq_next = 0;
               o_done   = 1'b1;
            end
            else begin
               seq_next = seq_reg+1;
               o_done   = 1'b0;
            end
        end
        else begin
            seq_next = seq_reg;
            o_done   = 1'b0;
        end
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
