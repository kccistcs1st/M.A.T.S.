`timescale 1ns / 1ps

module TOP_sys (
    input logic clk,
    input logic reset,

    // OV7670 side
    input  logic       pclk,
    output logic       xclk,
    input  logic       href,
    input  logic       vsync,
    input  logic [7:0] pdata,

    // VGA side
    output logic       h_sync,
    output logic       v_sync,
    output logic [3:0] port_red,
    output logic [3:0] port_green,
    output logic [3:0] port_blue,

    // SCCB
    output logic scl,
    inout  tri   sda,

    // UART Tx
    output logic uart_tx
);
    localparam int IMG_W = 320;
    localparam int IMG_H = 240;
    localparam int ADDR_W = $clog2(IMG_W * IMG_H);
    localparam int WIDTH_W = $clog2(IMG_W);
    localparam int WIDTH_H = $clog2(IMG_H);

    // Clock signals
    logic        clk_100M;
    logic        clk_25M;
    logic        rclk;

    // VGA timing signals
    logic        vga_h_sync;
    logic        vga_v_sync;
    logic [ 9:0] x_pixel;
    logic [ 9:0] y_pixel;
    logic        de;

    // Camera/UI/screen pixel signals
    logic [11:0] cam_rgb;
    logic [ 1:0] bitmap_pixel;
    logic [11:0] screen_rgb;

    // Raw camera stream used by the detector
    logic              cam_pclk;
    logic              cam_we;
    logic [ADDR_W-1:0] cam_wAddr;
    logic [      15:0] cam_wData;

    // UI control/status
    logic        ui_en;
    logic        friend_detect;
    logic        enemy_detect;

    // UART
    logic               uart_valid;
    logic               uart_type;
    logic [WIDTH_W-1:0] uart_cx;
    logic [WIDTH_H-1:0] uart_cy;
    logic [WIDTH_W-1:0] uart_w;
    logic [WIDTH_H-1:0] uart_h;
    logic               frame_done;

    // =========================================================
    // Camera
    // =========================================================

    CAM_Set #(
        .IMG_W (IMG_W),
        .IMG_H (IMG_H),
        .ADDR_W(ADDR_W)
    ) U_CAM_SET (
        .clk  (clk),
        .reset(reset),

        // OV7670
        .pclk (pclk),
        .href (href),
        .vsync(vsync),
        .pdata(pdata),
        .xclk (xclk),

        // SCCB
        .scl(scl),
        .sda(sda),

        // Generated clocks
        .clk_100M(clk_100M),
        .clk_25M (clk_25M),

        // VGA framebuffer read side
        .cam_fb_rclk(rclk),
        .x_pixel    (x_pixel),
        .y_pixel    (y_pixel),
        .de         (de),
        .cam_rgb    (cam_rgb),

        // Raw camera write stream for object detection
        .cam_pclk (cam_pclk),
        .cam_we   (cam_we),
        .cam_wAddr(cam_wAddr),
        .cam_wData(cam_wData)
    );

    // =========================================================
    // VGA timing generator
    // =========================================================

    VGA_Decoder U_VGA_DECODER (
        .clk  (clk_100M),
        .reset(reset),

        .rclk   (rclk),
        .h_sync (vga_h_sync),
        .v_sync (vga_v_sync),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel),
        .de     (de)
    );

    // =========================================================
    // Drone detection and UI bitmap generation
    // =========================================================

    UI_Set #(
        .IMG_W (IMG_W),
        .IMG_H (IMG_H),
        .ADDR_W(ADDR_W)
    ) U_UI_SET (
        .reset(reset),

        // Raw camera stream for detection
        .cam_pclk (cam_pclk),
        .cam_we   (cam_we),
        .cam_wAddr(cam_wAddr),
        .cam_wData(cam_wData),

        // VGA read/display domain
        .rclk   (rclk),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel),
        .de     (de),

        .ui_en        (ui_en),
        .friend_detect(friend_detect),
        .enemy_detect (enemy_detect),
        .bitmap_pixel (bitmap_pixel),

        .uart_out_type  (uart_type),
        .uart_out_valid (uart_valid),
        .uart_out_cx    (uart_cx),
        .uart_out_cy    (uart_cy),
        .uart_out_w     (uart_w),
        .uart_out_h     (uart_h),
        .frame_done     (frame_done)
    );

    // =========================================================
    // Final pixel-level screen mux
    //
    // bitmap_pixel:
    // 00: camera
    // 01: friend, green
    // 10: enemy, red
    // 11: enemy, red
    // =========================================================

    SCREEN_MUX U_SCREEN_MUX (
        .ui_enable     (ui_en),
        .i_camera_rgb  (cam_rgb),
        .i_bitmap_pixel(bitmap_pixel),
        .o_screen_rgb  (screen_rgb)
    );

    // =========================================================
    // VGA output/frame processing
    // =========================================================

    Frame_Set #(
        .IMG_W (IMG_W),
        .IMG_H (IMG_H),
        .ADDR_W(ADDR_W)
    ) U_FRAME_SET (
        .clk_100M(clk_100M),
        .reset   (reset),

        // VGA timing
        .h_sync_i(vga_h_sync),
        .v_sync_i(vga_v_sync),
        .x_pixel (x_pixel),
        .y_pixel (y_pixel),
        .de      (de),

        // Final screen pixel
        .screen_rgb(screen_rgb),

        // Detection status
        .friend_detect(friend_detect),
        .enemy_detect (enemy_detect),

        // Physical VGA outputs
        .h_sync    (h_sync),
        .v_sync    (v_sync),
        .port_red  (port_red),
        .port_green(port_green),
        .port_blue (port_blue)
    );

    
    // =========================================================
    // Output Information to UART Tx
    // =========================================================

    UART_Set #(
        .WIDTH  (IMG_W),
        .HEIGHT (IMG_H)
    ) U_UART_Set (
        .clk           (clk_100M),
        .rst           (reset),
        .uart_tx       (uart_tx),
        .target_valid  (uart_type),
        .target_type   (uart_valid), 
        .center_x      (uart_cx),
        .center_y      (uart_cy),
        .target_width  (uart_w),
        .target_height (uart_h),
        .frame_end     (frame_done)
    );

endmodule
