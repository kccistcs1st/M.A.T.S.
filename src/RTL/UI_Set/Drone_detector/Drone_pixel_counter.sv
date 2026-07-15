module Drone_pixel_counter #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int DIVIDE_X = 16,
    parameter int DIVIDE_Y = 12,
    parameter int THRESHOLD = 50
) (
    input logic clk,
    input logic reset,
    input logic we,
    input logic [$clog2(WIDTH*HEIGHT)-1:0] wAddr,

    input logic drone_ally,  // 1이면 아군 픽셀
    input logic drone_enemy, // 1이면 적군 픽셀

    output logic out_type,  // 1: 아군, 0: 적군
    output logic [$clog2(DIVIDE_X * DIVIDE_Y)-1:0] out_area_addr,
    output logic out_valid,
    output logic frame_done // 프레임 출력이 끝났음을 알리는 펄스
);

    localparam int DIV_WIDTH = WIDTH / DIVIDE_X;
    localparam int DIV_HEIGHT = HEIGHT / DIVIDE_Y;
    localparam int TOTAL_AREAS = DIVIDE_X * DIVIDE_Y;
    localparam int MAX_PIXELS_PER_AREA = DIV_WIDTH * DIV_HEIGHT;

    logic [$clog2(
MAX_PIXELS_PER_AREA+1
)-1:0] ally_area_counter[0:TOTAL_AREAS-1];
    logic [$clog2(
MAX_PIXELS_PER_AREA+1
)-1:0] enemy_area_counter[0:TOTAL_AREAS-1];

    logic [TOTAL_AREAS-1:0] current_ally_met;
    logic [TOTAL_AREAS-1:0] current_enemy_met;
    logic [TOTAL_AREAS-1:0] latched_ally_met;
    logic [TOTAL_AREAS-1:0] latched_enemy_met;

    logic [$clog2(WIDTH)-1:0] pixel_x;
    logic [$clog2(HEIGHT)-1:0] pixel_y;
    logic [$clog2(TOTAL_AREAS)-1:0] grid_idx;

    assign pixel_x = wAddr % WIDTH;
    assign pixel_y = wAddr / WIDTH;
    assign grid_idx = (pixel_y / DIV_HEIGHT) * DIVIDE_X + (pixel_x / DIV_WIDTH);

    integer i;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_ally_met  <= '0;
            current_enemy_met <= '0;
            latched_ally_met  <= '0;
            latched_enemy_met <= '0;

            for (i = 0; i < TOTAL_AREAS; i = i + 1) begin
                ally_area_counter[i]  <= 0;
                enemy_area_counter[i] <= 0;
            end
        end else if (we) begin
            if (wAddr == 0) begin
                latched_ally_met  <= current_ally_met;
                latched_enemy_met <= current_enemy_met;

                current_ally_met  <= '0;
                current_enemy_met <= '0;

                for (i = 0; i < TOTAL_AREAS; i = i + 1) begin
                    ally_area_counter[i]  <= 0;
                    enemy_area_counter[i] <= 0;
                end

                if (drone_ally) begin
                    ally_area_counter[grid_idx] <= 1;
                    if (1 >= THRESHOLD) current_ally_met[grid_idx] <= 1'b1;
                end
                if (drone_enemy) begin
                    enemy_area_counter[grid_idx] <= 1;
                    if (1 >= THRESHOLD) current_enemy_met[grid_idx] <= 1'b1;
                end
            end else begin
                if (drone_ally) begin
                    ally_area_counter[grid_idx] <= ally_area_counter[grid_idx] + 1;
                    if (ally_area_counter[grid_idx] + 1 >= THRESHOLD) begin
                        current_ally_met[grid_idx] <= 1'b1;
                    end
                end
                if (drone_enemy) begin
                    enemy_area_counter[grid_idx] <= enemy_area_counter[grid_idx] + 1;
                    if (enemy_area_counter[grid_idx] + 1 >= THRESHOLD) begin
                        current_enemy_met[grid_idx] <= 1'b1;
                    end
                end
            end
        end
    end
    localparam ST_IDLE = 2'b00;
    localparam ST_ALLY = 2'b01;
    localparam ST_ENEMY = 2'b10;
    logic [1:0] state;

    logic [$clog2(TOTAL_AREAS+1)-1:0] scan_idx;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= ST_IDLE;
            scan_idx      <= 0;
            out_type      <= 1'b0;
            out_area_addr <= 0;
            out_valid     <= 0;
            frame_done    <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    out_valid  <= 0;
                    scan_idx   <= 0;
                    frame_done <= 0;

                    if (we && wAddr == 0) begin
                        // [수정된 부분 1] 이전 프레임 전체의 탐지 결과를 판별하여 분기
                        if (current_ally_met != '0) begin
                            // 아군이 1개라도 탐지되었으면 ST_ALLY로 이동
                            state <= ST_ALLY;
                        end else if (current_enemy_met != '0) begin
                            // 아군은 없지만 적군이 탐지되었으면 ST_ENEMY로 직행 (시간 단축)
                            state <= ST_ENEMY;
                        end else begin
                            // 둘 다 없으면 스캔을 완전히 생략하고 프레임 종료 펄스만 출력
                            state <= ST_IDLE;
                            frame_done <= 1;
                        end
                    end
                end

                ST_ALLY: begin
                    if (scan_idx < TOTAL_AREAS) begin
                        if (latched_ally_met[scan_idx]) begin
                            out_valid     <= 1;
                            out_type      <= 1'b1;
                            out_area_addr <= scan_idx[$clog2(TOTAL_AREAS)-1:0];
                        end else begin
                            out_valid <= 0;
                        end
                        scan_idx <= scan_idx + 1;
                    end else begin
                        out_valid <= 0;
                        scan_idx  <= 0;

                        // [수정된 부분 2] 아군 스캔 완료 후 적군 데이터 유무에 따라 분기
                        if (latched_enemy_met != '0) begin
                            // 적군 데이터가 존재하면 ST_ENEMY로 전이
                            state <= ST_ENEMY;
                        end else begin
                            // 적군 데이터가 없으면 스킵하고 바로 ST_IDLE로 복귀
                            state <= ST_IDLE;
                            frame_done <= 1;
                        end
                    end
                end

                ST_ENEMY: begin
                    if (scan_idx < TOTAL_AREAS) begin
                        if (latched_enemy_met[scan_idx]) begin
                            out_valid     <= 1;
                            out_type      <= 1'b0;
                            out_area_addr <= scan_idx[$clog2(TOTAL_AREAS)-1:0];
                        end else begin
                            out_valid <= 0;
                        end
                        scan_idx <= scan_idx + 1;
                    end else begin
                        out_valid <= 0;
                        scan_idx <= 0;
                        state <= ST_IDLE;
                        frame_done <= 1; // 프레임 완료 신호 1사이클 방출
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
