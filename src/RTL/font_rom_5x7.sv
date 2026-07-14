`timescale 1ns / 1ps

module font_rom_5x7 (
    input  logic [7:0] char_code,
    input  logic [2:0] row,
    output logic [4:0] bits
);

    always_comb begin
        bits = 5'b00000;

        case (char_code)
            "A": begin
                case (row)
                    3'd0: bits = 5'b01110;
                    3'd1: bits = 5'b10001;
                    3'd2: bits = 5'b10001;
                    3'd3: bits = 5'b11111;
                    3'd4: bits = 5'b10001;
                    3'd5: bits = 5'b10001;
                    3'd6: bits = 5'b10001;
                    default: bits = 5'b00000;
                endcase
            end

            "C": begin
                case (row)
                    3'd0: bits = 5'b01111;
                    3'd1: bits = 5'b10000;
                    3'd2: bits = 5'b10000;
                    3'd3: bits = 5'b10000;
                    3'd4: bits = 5'b10000;
                    3'd5: bits = 5'b10000;
                    3'd6: bits = 5'b01111;
                    default: bits = 5'b00000;
                endcase
            end

            "D": begin
                case (row)
                    3'd0: bits = 5'b11110;
                    3'd1: bits = 5'b10001;
                    3'd2: bits = 5'b10001;
                    3'd3: bits = 5'b10001;
                    3'd4: bits = 5'b10001;
                    3'd5: bits = 5'b10001;
                    3'd6: bits = 5'b11110;
                    default: bits = 5'b00000;
                endcase
            end

            "E": begin
                case (row)
                    3'd0: bits = 5'b11111;
                    3'd1: bits = 5'b10000;
                    3'd2: bits = 5'b10000;
                    3'd3: bits = 5'b11110;
                    3'd4: bits = 5'b10000;
                    3'd5: bits = 5'b10000;
                    3'd6: bits = 5'b11111;
                    default: bits = 5'b00000;
                endcase
            end

            "F": begin
                case (row)
                    3'd0: bits = 5'b11111;
                    3'd1: bits = 5'b10000;
                    3'd2: bits = 5'b10000;
                    3'd3: bits = 5'b11110;
                    3'd4: bits = 5'b10000;
                    3'd5: bits = 5'b10000;
                    3'd6: bits = 5'b10000;
                    default: bits = 5'b00000;
                endcase
            end

            "M": begin
                case (row)
                    3'd0: bits = 5'b10001;
                    3'd1: bits = 5'b11011;
                    3'd2: bits = 5'b10101;
                    3'd3: bits = 5'b10101;
                    3'd4: bits = 5'b10001;
                    3'd5: bits = 5'b10001;
                    3'd6: bits = 5'b10001;
                    default: bits = 5'b00000;
                endcase
            end

            "N": begin
                case (row)
                    3'd0: bits = 5'b10001;
                    3'd1: bits = 5'b11001;
                    3'd2: bits = 5'b10101;
                    3'd3: bits = 5'b10011;
                    3'd4: bits = 5'b10001;
                    3'd5: bits = 5'b10001;
                    3'd6: bits = 5'b10001;
                    default: bits = 5'b00000;
                endcase
            end

            "O": begin
                case (row)
                    3'd0: bits = 5'b01110;
                    3'd1: bits = 5'b10001;
                    3'd2: bits = 5'b10001;
                    3'd3: bits = 5'b10001;
                    3'd4: bits = 5'b10001;
                    3'd5: bits = 5'b10001;
                    3'd6: bits = 5'b01110;
                    default: bits = 5'b00000;
                endcase
            end

            "S": begin
                case (row)
                    3'd0: bits = 5'b01111;
                    3'd1: bits = 5'b10000;
                    3'd2: bits = 5'b10000;
                    3'd3: bits = 5'b01110;
                    3'd4: bits = 5'b00001;
                    3'd5: bits = 5'b00001;
                    3'd6: bits = 5'b11110;
                    default: bits = 5'b00000;
                endcase
            end

            "T": begin
                case (row)
                    3'd0: bits = 5'b11111;
                    3'd1: bits = 5'b00100;
                    3'd2: bits = 5'b00100;
                    3'd3: bits = 5'b00100;
                    3'd4: bits = 5'b00100;
                    3'd5: bits = 5'b00100;
                    3'd6: bits = 5'b00100;
                    default: bits = 5'b00000;
                endcase
            end

            "Y": begin
                case (row)
                    3'd0: bits = 5'b10001;
                    3'd1: bits = 5'b10001;
                    3'd2: bits = 5'b01010;
                    3'd3: bits = 5'b00100;
                    3'd4: bits = 5'b00100;
                    3'd5: bits = 5'b00100;
                    3'd6: bits = 5'b00100;
                    default: bits = 5'b00000;
                endcase
            end

            "Z": begin
                case (row)
                    3'd0: bits = 5'b11111;
                    3'd1: bits = 5'b00001;
                    3'd2: bits = 5'b00010;
                    3'd3: bits = 5'b00100;
                    3'd4: bits = 5'b01000;
                    3'd5: bits = 5'b10000;
                    3'd6: bits = 5'b11111;
                    default: bits = 5'b00000;
                endcase
            end

            "!": begin
                case (row)
                    3'd0: bits = 5'b00100;
                    3'd1: bits = 5'b00100;
                    3'd2: bits = 5'b00100;
                    3'd3: bits = 5'b00100;
                    3'd4: bits = 5'b00100;
                    3'd5: bits = 5'b00000;
                    3'd6: bits = 5'b00100;
                    default: bits = 5'b00000;
                endcase
            end

            default: bits = 5'b00000;
        endcase
    end

endmodule