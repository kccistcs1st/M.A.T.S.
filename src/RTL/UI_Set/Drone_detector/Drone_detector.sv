module drone_detector #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int DIVIDE_X = 16,
    parameter int DIVIDE_Y = 12
) (
    input logic clk,
    input logic reset,

    input logic we, 
    input logic [$clog2(WIDTH*HEIGHT)-1:0] wAddr,
    input logic [15:0] wData,

    // Final outputs
    output logic [$clog2(WIDTH)-1:0] center_x,
    output logic [$clog2(HEIGHT)-1:0] center_y,
    output logic [$clog2(WIDTH)-1:0] target_width,
    output logic [$clog2(HEIGHT)-1:0] target_height,
    output logic target_type,  // 0: enemy, 1: friend
    output logic target_valid,

    output logic frame_done
);

    logic                                   pixel_ally;
    logic                                   pixel_enemy;

    logic                                   pxc_type; // 1: 아군, 0: 적군
    logic [$clog2(DIVIDE_X * DIVIDE_Y)-1:0] pxc_area_addr;
    logic                                   pxc_valid;
    logic                                   pxc_frame_done;

    assign frame_done = pxc_frame_done;

    Drone_Classification_Color U_DCC (
        .we          (we),
        .wData       (wData),
        .pixel_ally  (pixel_ally),
        .pixel_enemy (pixel_enemy)
    );

    Drone_pixel_counter U_DPC (
        .clk    (clk),
        .reset  (reset),
        .we     (we), 
        .wAddr  (wAddr),

        .drone_ally  (pixel_ally),
        .drone_enemy (pixel_enemy),

        .out_type       (pxc_type),
        .out_area_addr  (pxc_area_addr),
        .out_valid      (pxc_valid),
        .frame_done     (pxc_frame_done) 
    );

    drone_posit_size U_DPS (
        .clk            (clk),
        .reset          (reset),
        .in_valid       (pxc_valid),
        .in_type        (pxc_type),
        .in_area_addr   (pxc_area_addr),
        .in_frame_done  (pxc_frame_done),
        .center_x       (center_x),
        .center_y       (center_y),
        .target_width   (target_width),
        .target_height  (target_height),
        .target_type    (target_type),
        .target_valid   (target_valid)
    );

endmodule
