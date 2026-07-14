`timescale 1ns / 1ps

module UI_Set #(
    parameter int IMG_W   = 320,
    parameter int WIDTH_W = $clog2(IMG_W),
    parameter int IMG_H   = 240,
    parameter int WIDTH_H = $clog2(IMG_H),
    parameter int ADDR_W  = $clog2(IMG_W * IMG_H)
) (
    input logic reset,

    // Raw camera write stream from CAM_Set
    input logic              cam_pclk,
    input logic              cam_we,
    input logic [ADDR_W-1:0] cam_wAddr,
    input logic [      15:0] cam_wData,

    // VGA read/display domain from VGA_Decoder
    input logic       rclk,
    input logic [9:0] x_pixel,
    input logic [9:0] y_pixel,
    input logic       de,

    output logic       ui_en,
    output logic       friend_detect,
    output logic       enemy_detect,
    output logic [1:0] bitmap_pixel,

    // For UART_Set
    output logic               uart_out_valid,
    output logic               uart_out_type,
    output logic [WIDTH_W-1:0] uart_out_cx,
    output logic [WIDTH_H-1:0] uart_out_cy,
    output logic [WIDTH_W-1:0] uart_out_w,
    output logic [WIDTH_H-1:0] uart_out_h,
    output logic               frame_done
);

    // Detector output: 0 = enemy, 1 = friend
    logic       det_valid;
    logic       det_ready;
    logic [8:0] det_x;
    logic [7:0] det_y;
    logic [8:0] det_w;
    logic [7:0] det_h;
    logic       det_type;

    // Rendered UI pixel stream: 0 = enemy, 1 = friend
    logic       ui_pix_valid;
    logic       ui_pix_ready;
    logic [8:0] ui_pix_x;
    logic [7:0] ui_pix_y;
    logic       ui_pix_type;

    logic ui_done;

    // A zero bitmap pixel is transparent in SCREEN_MUX.
    assign ui_en = 1'b1;

    // UART Output
    assign uart_out_valid = det_valid;
    assign uart_out_type  = det_type;
    assign uart_out_cx    = det_x;
    assign uart_out_cy    = det_y;
    assign uart_out_w     = det_w;
    assign uart_out_h     = det_h;
    assign frame_done     = cam_we & ( cam_wAddr == ((IMG_W * IMG_H) - 1) );

    drone_detector #(
        .WIDTH   (IMG_W),
        .HEIGHT  (IMG_H),
        .DIVIDE_X(16),
        .DIVIDE_Y(12)
    ) U_DRONE_DETECTOR (
        .clk   (cam_pclk),
        .reset (reset),
        .we    (cam_we),
        .wAddr (cam_wAddr),
        .wData (cam_wData),

        .center_x     (det_x),
        .center_y     (det_y),
        .target_width (det_w),
        .target_height(det_h),
        .target_type  (det_type),
        .target_valid (det_valid)
    );

    // Hold detection status until the next camera frame begins.
    always_ff @(posedge cam_pclk or posedge reset) begin
        if (reset) begin
            friend_detect <= 1'b0;
            enemy_detect  <= 1'b0;
        end else begin
            if (cam_we && (cam_wAddr == '0)) begin
                friend_detect <= 1'b0;
                enemy_detect  <= 1'b0;
            end

            if (det_valid) begin
                if (det_type)
                    friend_detect <= 1'b1;
                else
                    enemy_detect <= 1'b1;
            end
        end
    end

    ui_generator #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H)
    ) U_UI_GENERATOR (
        .clk  (cam_pclk),
        .reset(reset),

        .det_valid(det_valid),
        .det_ready(det_ready),
        .det_x    (det_x),
        .det_y    (det_y),
        .det_w    (det_w),
        .det_h    (det_h),
        .det_type (det_type),

        .pix_valid(ui_pix_valid),
        .pix_ready(ui_pix_ready),
        .pix_x    (ui_pix_x),
        .pix_y    (ui_pix_y),
        .pix_type (ui_pix_type)
    );

    ui_framebuffer #(
        .WIDTH (IMG_W),
        .HEIGHT(IMG_H),
        .ADDR_W(ADDR_W)
    ) U_UI_FRAMEBUFFER (
        .write_clk(cam_pclk),
        .read_clk (rclk),
        .reset    (reset),

        .ready(ui_pix_ready),
        .done (ui_done),

        .valid      (ui_pix_valid),
        .target_type(ui_pix_type),
        .box_x      (ui_pix_x),
        .box_y      (ui_pix_y),

        .x_pixel(x_pixel),
        .y_pixel(y_pixel),
        .de     (de),

        .bitmap_pixel(bitmap_pixel)
    );

endmodule
