module Drone_Classification_Color (
    input  logic we,
    input  logic [15:0] wData,

    output logic        pixel_ally,
    output logic        pixel_enemy
);

    // 1. RGB 정규화 (RGB565 -> 6비트로 통일)
    logic [5:0] color_red;
    logic [5:0] color_green;
    logic [5:0] color_blue;
    
    assign color_red   = { wData[15:11], wData[15] }; // 6-bit
    assign color_green = { wData[10:5]             }; // 6-bit
    assign color_blue  = { wData[4:0]  , wData[4]  }; // 6-bit

    // 2. Max, Min 및 Delta 추출
    logic [5:0] max_val;
    logic [5:0] min_val;
    logic [5:0] delta;

    always_comb begin
        if (color_red >= color_green && color_red >= color_blue)
            max_val = color_red;
        else if (color_green >= color_red && color_green >= color_blue)
            max_val = color_green;
        else
            max_val = color_blue;

        // Min (Delta 계산용)
        if (color_red <= color_green && color_red <= color_blue)
            min_val = color_red;
        else if (color_green <= color_red && color_green <= color_blue)
            min_val = color_green;
        else
            min_val = color_blue;
    end

    assign delta = max_val - min_val;

    // 3. 유하게 조정된 HSV 조건 판별
    
    // [Value] 명도 조건 완화: 기존 16 -> 10으로 하향 조정 (어두운 그늘에서도 인식 가능)
    logic valid_v;
    assign valid_v = (max_val >= 6'd10);

    // [Saturation] 채도 조건 완화: 
    // 기존에는 delta가 max_val의 50% 이상이어야 했으나, 이제는 약 25% 이상만 되어도 인정
    // 최소 delta 값도 8 -> 4로 낮추어 미세한 색상 차이도 수용
    logic valid_s;
    assign valid_s = ((delta << 2) >= max_val) && (delta >= 6'd4);

    // [Hue] 색상 판단 기준 유화:
    // 무조건 Max 채널만 보는 것이 아니라, 2등 채널과의 격차나 조화를 고려하여 
    // 붉은 기운/푸른 기운이 도는 범위를 넓힘
    logic hue_is_red;
    logic hue_is_blue;
    
    // Red 조건 유화: R이 최고값이거나, 혹은 G/B보다 확실하게 우세한 경우 (R이 G보다 크고 B보다 큰 경향)
    // 주황색이나 보라색 경계선에 걸친 빨간색까지 유연하게 흡수
    assign hue_is_red  = (color_red >= color_green) && (color_red > color_blue);
    
    // Blue 조건 유화: B가 최고값이거나, G/R보다 확실하게 우세한 경우
    // 청록색(Cyan)이나 보라색 경계선에 걸친 파란색까지 유연하게 흡수
    assign hue_is_blue = (color_blue > color_red) && (color_blue >= color_green);

    assign pixel_enemy = valid_v & valid_s & hue_is_red;
    assign pixel_ally  = valid_v & valid_s & hue_is_blue;

endmodule