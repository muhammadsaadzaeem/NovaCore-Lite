`timescale 1ns / 1ps

module draw_engine #(
    parameter integer FB_WIDTH  = 160,
    parameter integer FB_HEIGHT = 120
)(
    input  wire       clk,
    input  wire       reset,

    output reg        pixel_we,
    output reg  [7:0] pixel_x,
    output reg  [6:0] pixel_y,
    output reg  [7:0] pixel_color,
    output reg  [7:0] pixel_depth,
    output reg        pixel_clear,

    output reg        done
);

    // ============================================================
    // State machine
    // ============================================================

    localparam [2:0] STATE_CLEAR = 3'd0;
    localparam [2:0] STATE_LOAD  = 3'd1;
    localparam [2:0] STATE_CULL  = 3'd2;
    localparam [2:0] STATE_START = 3'd3;
    localparam [2:0] STATE_WAIT  = 3'd4;
    localparam [2:0] STATE_HOLD  = 3'd5;

    reg [2:0] state;

    // ============================================================
    // RGB332 colors
    // ============================================================

    localparam [7:0] COLOR_BLACK = 8'b000_000_00;

    localparam [7:0] RED_BRIGHT = 8'b111_001_00;
    localparam [7:0] RED_MEDIUM = 8'b101_000_00;
    localparam [7:0] RED_DARK   = 8'b011_000_00;

    localparam [7:0] GREEN_BRIGHT = 8'b001_111_00;
    localparam [7:0] GREEN_MEDIUM = 8'b000_101_00;
    localparam [7:0] GREEN_DARK   = 8'b000_011_00;

    localparam [7:0] BLUE_BRIGHT = 8'b001_001_11;
    localparam [7:0] BLUE_MEDIUM = 8'b000_000_10;
    localparam [7:0] BLUE_DARK   = 8'b000_000_01;

    localparam [7:0] CYAN_BRIGHT = 8'b001_111_11;
    localparam [7:0] CYAN_MEDIUM = 8'b000_101_10;
    localparam [7:0] CYAN_DARK   = 8'b000_011_01;

    localparam [7:0] MAGENTA_BRIGHT = 8'b111_001_11;
    localparam [7:0] MAGENTA_MEDIUM = 8'b101_000_10;
    localparam [7:0] MAGENTA_DARK   = 8'b011_000_01;

    localparam [7:0] YELLOW_BRIGHT = 8'b111_111_01;
    localparam [7:0] YELLOW_MEDIUM = 8'b101_101_00;
    localparam [7:0] YELLOW_DARK   = 8'b011_011_00;

    // ============================================================
    // Framebuffer clearing
    // ============================================================

    reg [7:0] clear_x;
    reg [6:0] clear_y;

    // ============================================================
    // Animation control
    // ============================================================

    reg [4:0] angle_index;
    reg [3:0] triangle_index;

    localparam integer HOLD_CYCLES = 1_250_000;

    reg [20:0] hold_counter;

    // ============================================================
    // Triangle-engine interface
    // ============================================================

    reg triangle_start;

    reg [7:0] triangle_x0;
    reg [6:0] triangle_y0;

    reg [7:0] triangle_x1;
    reg [6:0] triangle_y1;

    reg [7:0] triangle_x2;
    reg [6:0] triangle_y2;

    reg [7:0] triangle_color;
    reg [7:0] triangle_depth;

    wire       triangle_pixel_we;
    wire [7:0] triangle_pixel_x;
    wire [6:0] triangle_pixel_y;
    wire [7:0] triangle_pixel_color;
    wire [7:0] triangle_pixel_depth;

    wire triangle_busy;
    wire triangle_done;

    triangle_engine triangle_engine_inst (
        .clk         (clk),
        .reset       (reset),

        .start       (triangle_start),

        .x0          (triangle_x0),
        .y0          (triangle_y0),

        .x1          (triangle_x1),
        .y1          (triangle_y1),

        .x2          (triangle_x2),
        .y2          (triangle_y2),

        .color       (triangle_color),
        .depth       (triangle_depth),

        .pixel_we    (triangle_pixel_we),
        .pixel_x     (triangle_pixel_x),
        .pixel_y     (triangle_pixel_y),
        .pixel_color (triangle_pixel_color),
        .pixel_depth (triangle_pixel_depth),

        .busy        (triangle_busy),
        .done        (triangle_done)
    );

    // ============================================================
    // Fixed-point sine lookup
    //
    // 256 represents 1.0
    // ============================================================

    function integer sin_lut;
        input [4:0] index;

        begin
            case (index)
                5'd0:  sin_lut = 0;
                5'd1:  sin_lut = 50;
                5'd2:  sin_lut = 98;
                5'd3:  sin_lut = 142;
                5'd4:  sin_lut = 181;
                5'd5:  sin_lut = 213;
                5'd6:  sin_lut = 237;
                5'd7:  sin_lut = 251;
                5'd8:  sin_lut = 256;
                5'd9:  sin_lut = 251;
                5'd10: sin_lut = 237;
                5'd11: sin_lut = 213;
                5'd12: sin_lut = 181;
                5'd13: sin_lut = 142;
                5'd14: sin_lut = 98;
                5'd15: sin_lut = 50;
                5'd16: sin_lut = 0;
                5'd17: sin_lut = -50;
                5'd18: sin_lut = -98;
                5'd19: sin_lut = -142;
                5'd20: sin_lut = -181;
                5'd21: sin_lut = -213;
                5'd22: sin_lut = -237;
                5'd23: sin_lut = -251;
                5'd24: sin_lut = -256;
                5'd25: sin_lut = -251;
                5'd26: sin_lut = -237;
                5'd27: sin_lut = -213;
                5'd28: sin_lut = -181;
                5'd29: sin_lut = -142;
                5'd30: sin_lut = -98;
                default: sin_lut = -50;
            endcase
        end
    endfunction

    function integer cos_lut;
        input [4:0] index;

        begin
            case (index)
                5'd0:  cos_lut = 256;
                5'd1:  cos_lut = 251;
                5'd2:  cos_lut = 237;
                5'd3:  cos_lut = 213;
                5'd4:  cos_lut = 181;
                5'd5:  cos_lut = 142;
                5'd6:  cos_lut = 98;
                5'd7:  cos_lut = 50;
                5'd8:  cos_lut = 0;
                5'd9:  cos_lut = -50;
                5'd10: cos_lut = -98;
                5'd11: cos_lut = -142;
                5'd12: cos_lut = -181;
                5'd13: cos_lut = -213;
                5'd14: cos_lut = -237;
                5'd15: cos_lut = -251;
                5'd16: cos_lut = -256;
                5'd17: cos_lut = -251;
                5'd18: cos_lut = -237;
                5'd19: cos_lut = -213;
                5'd20: cos_lut = -181;
                5'd21: cos_lut = -142;
                5'd22: cos_lut = -98;
                5'd23: cos_lut = -50;
                5'd24: cos_lut = 0;
                5'd25: cos_lut = 50;
                5'd26: cos_lut = 98;
                5'd27: cos_lut = 142;
                5'd28: cos_lut = 181;
                5'd29: cos_lut = 213;
                5'd30: cos_lut = 237;
                default: cos_lut = 251;
            endcase
        end
    endfunction

    // ============================================================
    // Projected X coordinate
    // ============================================================

    function [7:0] projected_x;
        input [4:0] angle;
        input [2:0] vertex;

        integer base_x;
        integer base_z;

        integer sine_value;
        integer cosine_value;

        integer rotated_x;
        integer screen_x;

        begin
            case (vertex)
                3'd0: begin base_x = -24; base_z = -24; end
                3'd1: begin base_x =  24; base_z = -24; end
                3'd2: begin base_x =  24; base_z = -24; end
                3'd3: begin base_x = -24; base_z = -24; end
                3'd4: begin base_x = -24; base_z =  24; end
                3'd5: begin base_x =  24; base_z =  24; end
                3'd6: begin base_x =  24; base_z =  24; end
                default: begin base_x = -24; base_z = 24; end
            endcase

            sine_value   = sin_lut(angle);
            cosine_value = cos_lut(angle);

            rotated_x =
                ((base_x * cosine_value) +
                 (base_z * sine_value)) >>> 8;

            screen_x = 80 + rotated_x;

            if (screen_x < 0)
                projected_x = 8'd0;
            else if (screen_x > 159)
                projected_x = 8'd159;
            else
                projected_x = screen_x[7:0];
        end
    endfunction

    // ============================================================
    // Projected Y coordinate
    // ============================================================

    function [6:0] projected_y;
        input [4:0] angle;
        input [2:0] vertex;

        integer base_x;
        integer base_y;
        integer base_z;

        integer sine_value;
        integer cosine_value;

        integer rotated_z;
        integer tilted_y;
        integer screen_y;

        begin
            case (vertex)
                3'd0: begin
                    base_x = -24;
                    base_y = -24;
                    base_z = -24;
                end

                3'd1: begin
                    base_x = 24;
                    base_y = -24;
                    base_z = -24;
                end

                3'd2: begin
                    base_x = 24;
                    base_y = 24;
                    base_z = -24;
                end

                3'd3: begin
                    base_x = -24;
                    base_y = 24;
                    base_z = -24;
                end

                3'd4: begin
                    base_x = -24;
                    base_y = -24;
                    base_z = 24;
                end

                3'd5: begin
                    base_x = 24;
                    base_y = -24;
                    base_z = 24;
                end

                3'd6: begin
                    base_x = 24;
                    base_y = 24;
                    base_z = 24;
                end

                default: begin
                    base_x = -24;
                    base_y = 24;
                    base_z = 24;
                end
            endcase

            sine_value   = sin_lut(angle);
            cosine_value = cos_lut(angle);

            rotated_z =
                ((-base_x * sine_value) +
                 (base_z * cosine_value)) >>> 8;

            tilted_y =
                ((base_y * 222) -
                 (rotated_z * 128)) >>> 8;

            screen_y = 60 - tilted_y;

            if (screen_y < 0)
                projected_y = 7'd0;
            else if (screen_y > 119)
                projected_y = 7'd119;
            else
                projected_y = screen_y[6:0];
        end
    endfunction


    // ============================================================
    // Camera-space depth, mapped to 8 bits.
    // Smaller values are closer to the camera.
    // ============================================================

    function [7:0] projected_depth;
        input [4:0] angle;
        input [2:0] vertex;

        integer base_x;
        integer base_y;
        integer base_z;
        integer sine_value;
        integer cosine_value;
        integer rotated_z;
        integer camera_z;
        integer depth_value;

        begin
            case (vertex)
                3'd0: begin base_x=-24; base_y=-24; base_z=-24; end
                3'd1: begin base_x= 24; base_y=-24; base_z=-24; end
                3'd2: begin base_x= 24; base_y= 24; base_z=-24; end
                3'd3: begin base_x=-24; base_y= 24; base_z=-24; end
                3'd4: begin base_x=-24; base_y=-24; base_z= 24; end
                3'd5: begin base_x= 24; base_y=-24; base_z= 24; end
                3'd6: begin base_x= 24; base_y= 24; base_z= 24; end
                default: begin base_x=-24; base_y=24; base_z=24; end
            endcase

            sine_value   = sin_lut(angle);
            cosine_value = cos_lut(angle);

            rotated_z =
                ((-base_x * sine_value) +
                 (base_z * cosine_value)) >>> 8;

            // Same fixed X tilt used by projected_y.
            camera_z =
                ((base_y * 128) +
                 (rotated_z * 222)) >>> 8;

            // Add bias; smaller depth wins.
            depth_value = 128 + camera_z;

            if (depth_value < 0)
                projected_depth = 8'd0;
            else if (depth_value > 254)
                projected_depth = 8'd254;
            else
                projected_depth = depth_value[7:0];
        end
    endfunction

    // ============================================================
    // Cube mesh triangle mapping
    // ============================================================

    function [2:0] triangle_vertex_a;
        input [3:0] tri_idx;

        begin
            case (tri_idx)
                4'd0:  triangle_vertex_a = 3'd0;
                4'd1:  triangle_vertex_a = 3'd0;

                4'd2:  triangle_vertex_a = 3'd4;
                4'd3:  triangle_vertex_a = 3'd4;

                4'd4:  triangle_vertex_a = 3'd0;
                4'd5:  triangle_vertex_a = 3'd0;

                4'd6:  triangle_vertex_a = 3'd1;
                4'd7:  triangle_vertex_a = 3'd1;

                4'd8:  triangle_vertex_a = 3'd0;
                4'd9:  triangle_vertex_a = 3'd0;

                4'd10: triangle_vertex_a = 3'd3;
                default: triangle_vertex_a = 3'd3;
            endcase
        end
    endfunction

    function [2:0] triangle_vertex_b;
        input [3:0] tri_idx;

        begin
            case (tri_idx)
                4'd0:  triangle_vertex_b = 3'd1;
                4'd1:  triangle_vertex_b = 3'd2;

                4'd2:  triangle_vertex_b = 3'd6;
                4'd3:  triangle_vertex_b = 3'd7;

                4'd4:  triangle_vertex_b = 3'd3;
                4'd5:  triangle_vertex_b = 3'd7;

                4'd6:  triangle_vertex_b = 3'd5;
                4'd7:  triangle_vertex_b = 3'd6;

                4'd8:  triangle_vertex_b = 3'd4;
                4'd9:  triangle_vertex_b = 3'd5;

                4'd10: triangle_vertex_b = 3'd2;
                default: triangle_vertex_b = 3'd6;
            endcase
        end
    endfunction

    function [2:0] triangle_vertex_c;
        input [3:0] tri_idx;

        begin
            case (tri_idx)
                4'd0:  triangle_vertex_c = 3'd2;
                4'd1:  triangle_vertex_c = 3'd3;

                4'd2:  triangle_vertex_c = 3'd5;
                4'd3:  triangle_vertex_c = 3'd6;

                4'd4:  triangle_vertex_c = 3'd7;
                4'd5:  triangle_vertex_c = 3'd4;

                4'd6:  triangle_vertex_c = 3'd6;
                4'd7:  triangle_vertex_c = 3'd2;

                4'd8:  triangle_vertex_c = 3'd5;
                4'd9:  triangle_vertex_c = 3'd1;

                4'd10: triangle_vertex_c = 3'd6;
                default: triangle_vertex_c = 3'd7;
            endcase
        end
    endfunction


    function [7:0] triangle_average_depth;
        input [3:0] tri_idx;
        input [4:0] angle;
        integer depth_sum;
        begin
            depth_sum =
                projected_depth(angle, triangle_vertex_a(tri_idx)) +
                projected_depth(angle, triangle_vertex_b(tri_idx)) +
                projected_depth(angle, triangle_vertex_c(tri_idx));

            triangle_average_depth = depth_sum / 3;
        end
    endfunction

    // ============================================================
    // Dynamic flat face lighting
    // ============================================================

    function [7:0] shaded_face_color;
        input [3:0] tri_idx;
        input [4:0] angle;

        integer light_value;
        integer abs_light;

        begin
            case (tri_idx)

                // Front face
                4'd0, 4'd1:
                    light_value = -cos_lut(angle);

                // Back face
                4'd2, 4'd3:
                    light_value = cos_lut(angle);

                // Left face
                4'd4, 4'd5:
                    light_value = -sin_lut(angle);

                // Right face
                4'd6, 4'd7:
                    light_value = sin_lut(angle);

                // Top face
                4'd8, 4'd9:
                    light_value = 210;

                // Bottom face
                default:
                    light_value = 70;
            endcase

            if (light_value < 0)
                abs_light = -light_value;
            else
                abs_light = light_value;

            if (tri_idx < 4'd2) begin
                if (abs_light > 190)
                    shaded_face_color = RED_BRIGHT;
                else if (abs_light > 95)
                    shaded_face_color = RED_MEDIUM;
                else
                    shaded_face_color = RED_DARK;
            end

            else if (tri_idx < 4'd4) begin
                if (abs_light > 190)
                    shaded_face_color = GREEN_BRIGHT;
                else if (abs_light > 95)
                    shaded_face_color = GREEN_MEDIUM;
                else
                    shaded_face_color = GREEN_DARK;
            end

            else if (tri_idx < 4'd6) begin
                if (abs_light > 190)
                    shaded_face_color = BLUE_BRIGHT;
                else if (abs_light > 95)
                    shaded_face_color = BLUE_MEDIUM;
                else
                    shaded_face_color = BLUE_DARK;
            end

            else if (tri_idx < 4'd8) begin
                if (abs_light > 190)
                    shaded_face_color = CYAN_BRIGHT;
                else if (abs_light > 95)
                    shaded_face_color = CYAN_MEDIUM;
                else
                    shaded_face_color = CYAN_DARK;
            end

            else if (tri_idx < 4'd10) begin
                if (abs_light > 190)
                    shaded_face_color = MAGENTA_BRIGHT;
                else if (abs_light > 95)
                    shaded_face_color = MAGENTA_MEDIUM;
                else
                    shaded_face_color = MAGENTA_DARK;
            end

            else begin
                if (abs_light > 190)
                    shaded_face_color = YELLOW_BRIGHT;
                else if (abs_light > 95)
                    shaded_face_color = YELLOW_MEDIUM;
                else
                    shaded_face_color = YELLOW_DARK;
            end
        end
    endfunction

    // ============================================================
    // Signed projected area for back-face culling
    // ============================================================

    function signed [18:0] projected_area;
        input [7:0] ax;
        input [6:0] ay;

        input [7:0] bx;
        input [6:0] by;

        input [7:0] cx;
        input [6:0] cy;

        reg signed [9:0] ab_x;
        reg signed [8:0] ab_y;

        reg signed [9:0] ac_x;
        reg signed [8:0] ac_y;

        reg signed [18:0] product_1;
        reg signed [18:0] product_2;

        begin
            ab_x =
                $signed({2'b00, bx}) -
                $signed({2'b00, ax});

            ab_y =
                $signed({2'b00, by}) -
                $signed({2'b00, ay});

            ac_x =
                $signed({2'b00, cx}) -
                $signed({2'b00, ax});

            ac_y =
                $signed({2'b00, cy}) -
                $signed({2'b00, ay});

            product_1 = ab_x * ac_y;
            product_2 = ab_y * ac_x;

            projected_area = product_1 - product_2;
        end
    endfunction

    // ============================================================
    // Framebuffer writer selection
    // ============================================================

    always @(*) begin
        if (state == STATE_CLEAR) begin
            pixel_we    = 1'b1;
            pixel_x     = clear_x;
            pixel_y     = clear_y;
            pixel_color = COLOR_BLACK;
            pixel_depth = 8'hFF;
            pixel_clear = 1'b1;
        end
        else begin
            pixel_we    = triangle_pixel_we;
            pixel_x     = triangle_pixel_x;
            pixel_y     = triangle_pixel_y;
            pixel_color = triangle_pixel_color;
            pixel_depth = triangle_pixel_depth;
            pixel_clear = 1'b0;
        end
    end

    // ============================================================
    // Main controller
    // ============================================================

    always @(posedge clk) begin
        if (reset) begin
            state          <= STATE_CLEAR;

            clear_x        <= 8'd0;
            clear_y        <= 7'd0;

            angle_index    <= 5'd0;
            triangle_index <= 4'd0;
            hold_counter   <= 21'd0;

            triangle_start <= 1'b0;

            triangle_x0    <= 8'd0;
            triangle_y0    <= 7'd0;

            triangle_x1    <= 8'd0;
            triangle_y1    <= 7'd0;

            triangle_x2    <= 8'd0;
            triangle_y2    <= 7'd0;

            triangle_color <= RED_BRIGHT;
            triangle_depth <= 8'hFF;

            done           <= 1'b0;
        end
        else begin
            triangle_start <= 1'b0;
            done           <= 1'b0;

            case (state)

                STATE_CLEAR: begin
                    if (clear_x == FB_WIDTH - 1) begin
                        clear_x <= 8'd0;

                        if (clear_y == FB_HEIGHT - 1) begin
                            clear_y        <= 7'd0;
                            triangle_index <= 4'd0;
                            state          <= STATE_LOAD;
                        end
                        else begin
                            clear_y <= clear_y + 7'd1;
                        end
                    end
                    else begin
                        clear_x <= clear_x + 8'd1;
                    end
                end

                STATE_LOAD: begin
                    triangle_x0 <= projected_x(
                        angle_index,
                        triangle_vertex_a(triangle_index)
                    );

                    triangle_y0 <= projected_y(
                        angle_index,
                        triangle_vertex_a(triangle_index)
                    );

                    triangle_x1 <= projected_x(
                        angle_index,
                        triangle_vertex_b(triangle_index)
                    );

                    triangle_y1 <= projected_y(
                        angle_index,
                        triangle_vertex_b(triangle_index)
                    );

                    triangle_x2 <= projected_x(
                        angle_index,
                        triangle_vertex_c(triangle_index)
                    );

                    triangle_y2 <= projected_y(
                        angle_index,
                        triangle_vertex_c(triangle_index)
                    );

                    triangle_color <= shaded_face_color(
                        triangle_index,
                        angle_index
                    );

                    triangle_depth <= triangle_average_depth(
                        triangle_index,
                        angle_index
                    );

                    state <= STATE_CULL;
                end

                STATE_CULL: begin
                    if (
                        projected_area(
                            triangle_x0,
                            triangle_y0,
                            triangle_x1,
                            triangle_y1,
                            triangle_x2,
                            triangle_y2
                        ) < 0
                    ) begin
                        state <= STATE_START;
                    end
                    else begin
                        if (triangle_index == 4'd11) begin
                            hold_counter <= 21'd0;
                            state        <= STATE_HOLD;
                        end
                        else begin
                            triangle_index <= triangle_index + 4'd1;
                            state          <= STATE_LOAD;
                        end
                    end
                end

                STATE_START: begin
                    triangle_start <= 1'b1;
                    state          <= STATE_WAIT;
                end

                STATE_WAIT: begin
                    if (triangle_done) begin
                        if (triangle_index == 4'd11) begin
                            hold_counter <= 21'd0;
                            state        <= STATE_HOLD;
                        end
                        else begin
                            triangle_index <= triangle_index + 4'd1;
                            state          <= STATE_LOAD;
                        end
                    end
                end

                STATE_HOLD: begin
                    done <= 1'b1;

                    if (hold_counter == HOLD_CYCLES - 1) begin
                        hold_counter <= 21'd0;

                        if (angle_index == 5'd31)
                            angle_index <= 5'd0;
                        else
                            angle_index <= angle_index + 5'd1;

                        clear_x <= 8'd0;
                        clear_y <= 7'd0;

                        state <= STATE_CLEAR;
                    end
                    else begin
                        hold_counter <= hold_counter + 21'd1;
                    end
                end

                default: begin
                    state <= STATE_CLEAR;
                end

            endcase
        end
    end

endmodule