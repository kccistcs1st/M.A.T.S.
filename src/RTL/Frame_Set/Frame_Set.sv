`timescale 1ns / 1ps

module Frame_Set #(
    parameter int IMG_W  = 320,
    parameter int IMG_H  = 240,
    parameter int ADDR_W = $clog2(IMG_W * IMG_H)
) (
    input  logic       clk_100M,
    input  logic       reset,

    // VGA timing from VGA_Decoder
    input  logic       h_sync_i,
    input  logic       v_sync_i,
    input  logic [9:0] x_pixel,
    input  logic [9:0] y_pixel,
    input  logic       de,

    // Result of CAM/UI screen mux
    input  logic [11:0] screen_rgb,
    input  logic        friend_detect,
    input  logic        enemy_detect,

    // Final VGA side
    output logic       h_sync,
    output logic       v_sync,
    output logic [3:0] port_red,
    output logic [3:0] port_green,
    output logic [3:0] port_blue
);

    logic [11:0] final_rgb;

    frame_generator_friend_enemy U_FRAME_GENERATOR (
        .x_pixel      (x_pixel),
        .y_pixel      (y_pixel),
        .de           (de),
        .upscale_mode (1'b1),
        .i_rgb        (screen_rgb),
        .friend_detect(friend_detect),
        .enemy_detect (enemy_detect),
        .o_rgb        (final_rgb)
    );

    assign h_sync = h_sync_i;
    assign v_sync = v_sync_i;
    assign {port_red, port_green, port_blue} = final_rgb;

endmodule
