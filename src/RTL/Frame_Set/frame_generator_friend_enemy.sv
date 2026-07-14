`timescale 1ns / 1ps

module frame_generator_friend_enemy (
    input  logic [9:0]  x_pixel,
    input  logic [9:0]  y_pixel,
    input  logic        de,
    input  logic        upscale_mode,

    input  logic [11:0] i_rgb,

    input  logic        friend_detect,
    input  logic        enemy_detect,

    output logic [11:0] o_rgb
);
    
    localparam logic [11:0] GREEN = 12'h0F0;
    localparam logic [11:0] RED   = 12'hF00;
    localparam logic [11:0] WHITE = 12'hFFF;

    logic [9:0] box_x;
    logic [9:0] box_y;
    logic [9:0] box_w;
    logic [9:0] box_h;
    logic [9:0] border;
    logic [9:0] bar_h;

    logic in_left_border;
    logic in_right_border;
    logic in_top_border;
    logic in_bottom_border;
    logic in_status_bar;
    logic in_frame;
    logic text_on;

    
    always_comb begin
        if (upscale_mode) begin
            box_x  = 10'd0;
            box_y  = 10'd0;
            box_w  = 10'd640;
            box_h  = 10'd480;
            border = 10'd10;
            bar_h  = 10'd40;
        end else begin
            box_x  = 10'd0;
            box_y  = 10'd0;
            box_w  = 10'd320;
            box_h  = 10'd240;
            border = 10'd6;
            bar_h  = 10'd24;
        end
    end

    assign in_left_border =
        (x_pixel >= box_x) &&
        (x_pixel <  box_x + border) &&
        (y_pixel >= box_y) &&
        (y_pixel <  box_y + box_h);

    assign in_right_border =
        (x_pixel >= box_x + box_w - border) &&
        (x_pixel <  box_x + box_w) &&
        (y_pixel >= box_y) &&
        (y_pixel <  box_y + box_h);

    assign in_top_border =
        (x_pixel >= box_x) &&
        (x_pixel <  box_x + box_w) &&
        (y_pixel >= box_y) &&
        (y_pixel <  box_y + border);

    assign in_bottom_border =
        (x_pixel >= box_x) &&
        (x_pixel <  box_x + box_w) &&
        (y_pixel >= box_y + box_h - border) &&
        (y_pixel <  box_y + box_h);

    assign in_status_bar =
        (x_pixel >= box_x) &&
        (x_pixel <  box_x + box_w) &&
        (y_pixel >= box_y + box_h - bar_h) &&
        (y_pixel <  box_y + box_h);

    assign in_frame =
        in_left_border   ||
        in_right_border  ||
        in_top_border    ||
        in_bottom_border ||
        in_status_bar;

    text_status_pixel U_text_status_pixel (
        .x_pixel      (x_pixel),
        .y_pixel      (y_pixel),
        .upscale_mode (upscale_mode),
        .friend_detect(friend_detect),
        .enemy_detect (enemy_detect),
        .pixel_on     (text_on)
    );

    always_comb begin
        if (!de) begin
            o_rgb = 12'h000;
        end else if ((friend_detect || enemy_detect) && text_on) begin
            o_rgb = WHITE;
        end else if (enemy_detect && in_frame) begin
            o_rgb = RED;
        end else if (friend_detect && !enemy_detect && in_frame) begin
            o_rgb = GREEN;
        end else begin
            o_rgb = i_rgb;
        end
    end

endmodule