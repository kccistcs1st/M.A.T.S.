`timescale 1ns / 1ps

module text_status_pixel (
    input  logic [9:0] x_pixel,
    input  logic [9:0] y_pixel,
    input  logic       upscale_mode,
    input  logic       friend_detect,
    input  logic       enemy_detect,
    output logic       pixel_on
);

    logic [9:0] text_x;
    logic [9:0] text_y;
    logic [9:0] rel_x;
    logic [9:0] rel_y;

    logic [3:0] scale;
    logic [4:0] char_idx;
    logic [2:0] font_col;
    logic [2:0] font_row;
    logic [7:0] char_code;
    logic [4:0] font_bits;

    logic       in_text_area;
    logic [9:0] char_w;
    logic [9:0] char_h;
    logic [9:0] text_len;

    font_rom_5x7 U_font_rom_5x7 (
        .char_code(char_code),
        .row      (font_row),
        .bits     (font_bits)
    );

    always_comb begin
        if (upscale_mode) begin
            scale  = 4'd2;
            text_x = enemy_detect ? 10'd226 : 10'd268;
            text_y = 10'd452;
        end else begin
            scale  = 4'd1;
            text_x = enemy_detect ? 10'd113 : 10'd134;
            text_y = 10'd226;
        end
    end

    assign char_w = 6 * scale; // 5 pixel font + 1 spacing
    assign char_h = 7 * scale;

    always_comb begin
        if (enemy_detect) begin
            text_len = 10'd15;  // ENEMY DETECT !!
        end else if (friend_detect) begin
            text_len = 10'd9;  // SAFE ZONE
        end else begin
            text_len = 10'd0;
        end
    end

    assign in_text_area =
        (x_pixel >= text_x) &&
        (x_pixel <  text_x + text_len * char_w) &&
        (y_pixel >= text_y) &&
        (y_pixel <  text_y + char_h);

    assign rel_x = x_pixel - text_x;
    assign rel_y = y_pixel - text_y;

    assign char_idx = rel_x / char_w;
    assign font_col = (rel_x % char_w) / scale;
    assign font_row = rel_y / scale;

    always_comb begin
        char_code = " ";

        if (enemy_detect) begin
            case (char_idx)
                5'd0: char_code = "E";
                5'd1: char_code = "N";
                5'd2: char_code = "E";
                5'd3: char_code = "M";
                5'd4: char_code = "Y";
                5'd5: char_code = " ";
                5'd6: char_code = "D";
                5'd7: char_code = "E";
                5'd8: char_code = "T";
                5'd9: char_code = "E";
                5'd10: char_code = "C";
                5'd11: char_code = "T";
                5'd12: char_code = " ";
                5'd13: char_code = "!";
                5'd14: char_code = "!";
                default: char_code = " ";
            endcase
        end else if (friend_detect) begin
            case (char_idx)
                5'd0: char_code = "S";
                5'd1: char_code = "A";
                5'd2: char_code = "F";
                5'd3: char_code = "E";
                5'd4: char_code = " ";
                5'd5: char_code = "Z";
                5'd6: char_code = "O";
                5'd7: char_code = "N";
                5'd8: char_code = "E";
                default: char_code = " ";
            endcase
        end
    end

  always_comb begin
    pixel_on = 1'b0;

    if (in_text_area) begin
        case (font_col)
            3'd0: pixel_on = font_bits[4];
            3'd1: pixel_on = font_bits[3];
            3'd2: pixel_on = font_bits[2];
            3'd3: pixel_on = font_bits[1];
            3'd4: pixel_on = font_bits[0];
            default: pixel_on = 1'b0;
        endcase
    end
end

endmodule