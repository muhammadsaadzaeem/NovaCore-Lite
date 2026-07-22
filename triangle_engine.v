`timescale 1ns / 1ps

module triangle_engine (
    input  wire       clk,
    input  wire       reset,
    input  wire       start,

    input  wire [7:0] x0,
    input  wire [6:0] y0,
    input  wire [7:0] x1,
    input  wire [6:0] y1,
    input  wire [7:0] x2,
    input  wire [6:0] y2,

    input  wire [7:0] color,
    input  wire [7:0] depth,

    output reg        pixel_we,
    output reg  [7:0] pixel_x,
    output reg  [6:0] pixel_y,
    output reg  [7:0] pixel_color,
    output reg  [7:0] pixel_depth,

    output reg        busy,
    output reg        done
);

    reg [7:0] min_x, max_x, current_x;
    reg [6:0] min_y, max_y, current_y;

    reg signed [21:0] triangle_area;
    reg signed [21:0] edge_01, edge_12, edge_20;
    reg signed [21:0] row_edge_01, row_edge_12, row_edge_20;

    reg signed [10:0] edge_01_step_x, edge_12_step_x, edge_20_step_x;
    reg signed [10:0] edge_01_step_y, edge_12_step_y, edge_20_step_y;

    function [7:0] min3_x;
        input [7:0] a, b, c;
        begin
            if ((a <= b) && (a <= c)) min3_x = a;
            else if (b <= c) min3_x = b;
            else min3_x = c;
        end
    endfunction

    function [7:0] max3_x;
        input [7:0] a, b, c;
        begin
            if ((a >= b) && (a >= c)) max3_x = a;
            else if (b >= c) max3_x = b;
            else max3_x = c;
        end
    endfunction

    function [6:0] min3_y;
        input [6:0] a, b, c;
        begin
            if ((a <= b) && (a <= c)) min3_y = a;
            else if (b <= c) min3_y = b;
            else min3_y = c;
        end
    endfunction

    function [6:0] max3_y;
        input [6:0] a, b, c;
        begin
            if ((a >= b) && (a >= c)) max3_y = a;
            else if (b >= c) max3_y = b;
            else max3_y = c;
        end
    endfunction

    function signed [21:0] edge_function;
        input signed [9:0] ax, ay, bx, by, px, py;
        reg signed [10:0] p_minus_ax, p_minus_ay;
        reg signed [10:0] b_minus_ax, b_minus_ay;
        reg signed [21:0] product_a, product_b;
        begin
            p_minus_ax = px - ax;
            p_minus_ay = py - ay;
            b_minus_ax = bx - ax;
            b_minus_ay = by - ay;
            product_a = p_minus_ax * b_minus_ay;
            product_b = p_minus_ay * b_minus_ax;
            edge_function = product_a - product_b;
        end
    endfunction

    wire pixel_inside =
        (triangle_area >= 0)
        ? ((edge_01 >= 0) && (edge_12 >= 0) && (edge_20 >= 0))
        : ((edge_01 <= 0) && (edge_12 <= 0) && (edge_20 <= 0));

    always @(posedge clk) begin
        if (reset) begin
            min_x <= 0; max_x <= 0; min_y <= 0; max_y <= 0;
            current_x <= 0; current_y <= 0;
            triangle_area <= 0;
            edge_01 <= 0; edge_12 <= 0; edge_20 <= 0;
            row_edge_01 <= 0; row_edge_12 <= 0; row_edge_20 <= 0;
            edge_01_step_x <= 0; edge_12_step_x <= 0; edge_20_step_x <= 0;
            edge_01_step_y <= 0; edge_12_step_y <= 0; edge_20_step_y <= 0;
            pixel_we <= 0; pixel_x <= 0; pixel_y <= 0;
            pixel_color <= 0; pixel_depth <= 8'hFF;
            busy <= 0; done <= 0;
        end else begin
            pixel_we <= 1'b0;
            done <= 1'b0;

            if (start && !busy) begin
                min_x <= min3_x(x0,x1,x2);
                max_x <= max3_x(x0,x1,x2);
                min_y <= min3_y(y0,y1,y2);
                max_y <= max3_y(y0,y1,y2);
                current_x <= min3_x(x0,x1,x2);
                current_y <= min3_y(y0,y1,y2);
                pixel_color <= color;
                pixel_depth <= depth;

                triangle_area <= edge_function(
                    $signed({2'b00,x0}), $signed({3'b000,y0}),
                    $signed({2'b00,x1}), $signed({3'b000,y1}),
                    $signed({2'b00,x2}), $signed({3'b000,y2})
                );

                edge_01 <= edge_function(
                    $signed({2'b00,x0}), $signed({3'b000,y0}),
                    $signed({2'b00,x1}), $signed({3'b000,y1}),
                    $signed({2'b00,min3_x(x0,x1,x2)}),
                    $signed({3'b000,min3_y(y0,y1,y2)})
                );
                edge_12 <= edge_function(
                    $signed({2'b00,x1}), $signed({3'b000,y1}),
                    $signed({2'b00,x2}), $signed({3'b000,y2}),
                    $signed({2'b00,min3_x(x0,x1,x2)}),
                    $signed({3'b000,min3_y(y0,y1,y2)})
                );
                edge_20 <= edge_function(
                    $signed({2'b00,x2}), $signed({3'b000,y2}),
                    $signed({2'b00,x0}), $signed({3'b000,y0}),
                    $signed({2'b00,min3_x(x0,x1,x2)}),
                    $signed({3'b000,min3_y(y0,y1,y2)})
                );

                row_edge_01 <= edge_function(
                    $signed({2'b00,x0}), $signed({3'b000,y0}),
                    $signed({2'b00,x1}), $signed({3'b000,y1}),
                    $signed({2'b00,min3_x(x0,x1,x2)}),
                    $signed({3'b000,min3_y(y0,y1,y2)})
                );
                row_edge_12 <= edge_function(
                    $signed({2'b00,x1}), $signed({3'b000,y1}),
                    $signed({2'b00,x2}), $signed({3'b000,y2}),
                    $signed({2'b00,min3_x(x0,x1,x2)}),
                    $signed({3'b000,min3_y(y0,y1,y2)})
                );
                row_edge_20 <= edge_function(
                    $signed({2'b00,x2}), $signed({3'b000,y2}),
                    $signed({2'b00,x0}), $signed({3'b000,y0}),
                    $signed({2'b00,min3_x(x0,x1,x2)}),
                    $signed({3'b000,min3_y(y0,y1,y2)})
                );

                edge_01_step_x <= $signed({3'b000,y1}) - $signed({3'b000,y0});
                edge_12_step_x <= $signed({3'b000,y2}) - $signed({3'b000,y1});
                edge_20_step_x <= $signed({3'b000,y0}) - $signed({3'b000,y2});

                edge_01_step_y <= $signed({2'b00,x0}) - $signed({2'b00,x1});
                edge_12_step_y <= $signed({2'b00,x1}) - $signed({2'b00,x2});
                edge_20_step_y <= $signed({2'b00,x2}) - $signed({2'b00,x0});

                busy <= 1'b1;
            end else if (busy) begin
                pixel_x <= current_x;
                pixel_y <= current_y;

                if ((triangle_area != 0) && pixel_inside)
                    pixel_we <= 1'b1;

                if (current_x == max_x) begin
                    current_x <= min_x;
                    if (current_y == max_y) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        current_y <= current_y + 1'b1;
                        row_edge_01 <= row_edge_01 + edge_01_step_y;
                        row_edge_12 <= row_edge_12 + edge_12_step_y;
                        row_edge_20 <= row_edge_20 + edge_20_step_y;
                        edge_01 <= row_edge_01 + edge_01_step_y;
                        edge_12 <= row_edge_12 + edge_12_step_y;
                        edge_20 <= row_edge_20 + edge_20_step_y;
                    end
                end else begin
                    current_x <= current_x + 1'b1;
                    edge_01 <= edge_01 + edge_01_step_x;
                    edge_12 <= edge_12 + edge_12_step_x;
                    edge_20 <= edge_20 + edge_20_step_x;
                end
            end
        end
    end
endmodule