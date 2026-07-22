`timescale 1ns / 1ps

module novacore_top (
    input  wire       clk,

    output wire       HDMI_CLK_N,
    output wire       HDMI_CLK_P,
    output wire [2:0] HDMI_D_N,
    output wire [2:0] HDMI_D_P
);

    // ============================================================
    // Clock generation
    //
    // Input clock:       100 MHz
    // Pixel clock:        25 MHz
    // HDMI serializer:   125 MHz
    // ============================================================

    wire pixel_clk;
    wire pixel_clk_5x;
    wire clocks_locked;

    video_clock video_clock_inst (
        .clk_out1 (pixel_clk),
        .clk_out2 (pixel_clk_5x),
        .reset    (1'b0),
        .locked   (clocks_locked),
        .clk_in1  (clk)
    );

    wire video_reset;

    assign video_reset = ~clocks_locked;

    // ============================================================
    // 640 x 480 video timing
    // ============================================================

    localparam integer H_ACTIVE = 640;
    localparam integer H_FRONT  = 16;
    localparam integer H_SYNC   = 96;
    localparam integer H_BACK   = 48;
    localparam integer H_TOTAL  = 800;

    localparam integer V_ACTIVE = 480;
    localparam integer V_FRONT  = 10;
    localparam integer V_SYNC   = 2;
    localparam integer V_BACK   = 33;
    localparam integer V_TOTAL  = 525;

    reg [9:0] h_count = 10'd0;
    reg [9:0] v_count = 10'd0;

    always @(posedge pixel_clk) begin
        if (video_reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end
        else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;

                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end
            else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    wire hsync_raw;
    wire vsync_raw;
    wire vde_raw;

    assign hsync_raw =
        ~((h_count >= H_ACTIVE + H_FRONT) &&
          (h_count <  H_ACTIVE + H_FRONT + H_SYNC));

    assign vsync_raw =
        ~((v_count >= V_ACTIVE + V_FRONT) &&
          (v_count <  V_ACTIVE + V_FRONT + V_SYNC));

    assign vde_raw =
        (h_count < H_ACTIVE) &&
        (v_count < V_ACTIVE);

    // First pixel clock of vertical blanking.
    wire vertical_blank_start;

    assign vertical_blank_start =
        (h_count == 10'd0) &&
        (v_count == V_ACTIVE);

    // ============================================================
    // Framebuffer configuration
    //
    // Logical framebuffer: 160 x 120
    // Display scaling:      4 x 4
    // Pixel format:         RGB332
    // ============================================================

    localparam integer FB_WIDTH  = 160;
    localparam integer FB_HEIGHT = 120;
    localparam integer FB_SIZE   = FB_WIDTH * FB_HEIGHT;

    // Force both framebuffers into FPGA Block RAM rather than LUT RAM.
    (* ram_style = "block" *)
    reg [7:0] framebuffer_0 [0:FB_SIZE-1];

    (* ram_style = "block" *)
    reg [7:0] framebuffer_1 [0:FB_SIZE-1];

    (* ram_style = "block" *)
    reg [7:0] depthbuffer_0 [0:FB_SIZE-1];

    (* ram_style = "block" *)
    reg [7:0] depthbuffer_1 [0:FB_SIZE-1];

    // 0: framebuffer 0 is displayed; framebuffer 1 is drawn.
    // 1: framebuffer 1 is displayed; framebuffer 0 is drawn.
    reg front_buffer_select = 1'b0;

    // The screen remains black until the first complete frame is ready.
    reg frame_valid = 1'b0;

    // ============================================================
    // Display framebuffer address
    // ============================================================

    wire [7:0] fb_x;
    wire [6:0] fb_y;

    // Divide the 640 x 480 coordinates by four.
    assign fb_x = h_count[9:2];
    assign fb_y = v_count[8:2];

    // Address = y * 160 + x
    //         = y * 128 + y * 32 + x
    wire [14:0] read_address;

    assign read_address =
        ({8'd0, fb_y} << 7) +
        ({8'd0, fb_y} << 5) +
        fb_x;

    // Each BRAM has its own registered read output.
    reg [7:0] framebuffer_0_read = 8'h00;
    reg [7:0] framebuffer_1_read = 8'h00;

    wire [7:0] framebuffer_pixel;

    assign framebuffer_pixel =
        front_buffer_select
        ? framebuffer_1_read
        : framebuffer_0_read;

    // ============================================================
    // Drawing engine
    // ============================================================

    wire       draw_pixel_we;
    wire [7:0] draw_pixel_x;
    wire [6:0] draw_pixel_y;
    wire [7:0] draw_pixel_color;
    wire [7:0] draw_pixel_depth;
    wire       draw_pixel_clear;
    wire       draw_done;

    draw_engine #(
        .FB_WIDTH  (FB_WIDTH),
        .FB_HEIGHT (FB_HEIGHT)
    ) draw_engine_inst (
        .clk         (pixel_clk),
        .reset       (video_reset),

        .pixel_we    (draw_pixel_we),
        .pixel_x     (draw_pixel_x),
        .pixel_y     (draw_pixel_y),
        .pixel_color (draw_pixel_color),
        .pixel_depth (draw_pixel_depth),
        .pixel_clear (draw_pixel_clear),

        .done        (draw_done)
    );

    wire [14:0] draw_address;

    assign draw_address =
        ({8'd0, draw_pixel_y} << 7) +
        ({8'd0, draw_pixel_y} << 5) +
        draw_pixel_x;

    // ============================================================
    // Frame-completion detection
    //
    // draw_done stays high during the HOLD state. Detect only its
    // rising edge so one completed frame creates one swap request.
    // ============================================================

    reg draw_done_delayed = 1'b0;
    reg swap_pending      = 1'b0;

    wire draw_done_rising;

    assign draw_done_rising =
        draw_done && !draw_done_delayed;

    // ============================================================
    // Vertical-blank buffer swap
    // ============================================================

    always @(posedge pixel_clk) begin
        if (video_reset) begin
            draw_done_delayed   <= 1'b0;
            swap_pending        <= 1'b0;
            front_buffer_select <= 1'b0;
            frame_valid         <= 1'b0;
        end
        else begin
            draw_done_delayed <= draw_done;

            // The drawing engine completed a full back-buffer image.
            if (draw_done_rising)
                swap_pending <= 1'b1;

            // Swap only when the active video region has ended.
            if (
                vertical_blank_start &&
                (swap_pending || draw_done_rising)
            ) begin
                front_buffer_select <= ~front_buffer_select;
                swap_pending        <= 1'b0;
                frame_valid         <= 1'b1;
            end
        end
    end

    // ============================================================
    // Pipelined Z-test request
    // ============================================================

    reg        fragment_valid_d = 1'b0;
    reg        fragment_clear_d = 1'b0;
    reg        fragment_buffer_d = 1'b0;
    reg [14:0] fragment_address_d = 15'd0;
    reg [7:0]  fragment_color_d = 8'd0;
    reg [7:0]  fragment_depth_d = 8'hFF;

    reg [7:0] depthbuffer_0_read = 8'hFF;
    reg [7:0] depthbuffer_1_read = 8'hFF;

    always @(posedge pixel_clk) begin
        if (video_reset) begin
            fragment_valid_d   <= 1'b0;
            fragment_clear_d   <= 1'b0;
            fragment_buffer_d  <= 1'b0;
            fragment_address_d <= 15'd0;
            fragment_color_d   <= 8'd0;
            fragment_depth_d   <= 8'hFF;
        end
        else begin
            fragment_valid_d   <= draw_pixel_we;
            fragment_clear_d   <= draw_pixel_clear;
            fragment_buffer_d  <= ~front_buffer_select;
            fragment_address_d <= draw_address;
            fragment_color_d   <= draw_pixel_color;
            fragment_depth_d   <= draw_pixel_depth;
        end
    end

    // ============================================================
    // Buffer 0: scanout read plus back-buffer depth test/write
    // ============================================================

    always @(posedge pixel_clk) begin
        framebuffer_0_read <= framebuffer_0[read_address];

        // Read candidate depth for the current request.
        if (draw_pixel_we && (front_buffer_select == 1'b1))
            depthbuffer_0_read <= depthbuffer_0[draw_address];

        // Apply previous cycle's request.
        if (fragment_valid_d && (fragment_buffer_d == 1'b0)) begin
            if (fragment_clear_d) begin
                framebuffer_0[fragment_address_d] <= fragment_color_d;
                depthbuffer_0[fragment_address_d] <= 8'hFF;
            end
            else if (fragment_depth_d < depthbuffer_0_read) begin
                framebuffer_0[fragment_address_d] <= fragment_color_d;
                depthbuffer_0[fragment_address_d] <= fragment_depth_d;
            end
        end
    end

    // ============================================================
    // Buffer 1: scanout read plus back-buffer depth test/write
    // ============================================================

    always @(posedge pixel_clk) begin
        framebuffer_1_read <= framebuffer_1[read_address];

        // Read candidate depth for the current request.
        if (draw_pixel_we && (front_buffer_select == 1'b0))
            depthbuffer_1_read <= depthbuffer_1[draw_address];

        // Apply previous cycle's request.
        if (fragment_valid_d && (fragment_buffer_d == 1'b1)) begin
            if (fragment_clear_d) begin
                framebuffer_1[fragment_address_d] <= fragment_color_d;
                depthbuffer_1[fragment_address_d] <= 8'hFF;
            end
            else if (fragment_depth_d < depthbuffer_1_read) begin
                framebuffer_1[fragment_address_d] <= fragment_color_d;
                depthbuffer_1[fragment_address_d] <= fragment_depth_d;
            end
        end
    end

    // ============================================================
    // Delay video timing by one pixel clock
    //
    // Block RAM reads are synchronous, so the RGB pixel appears one
    // clock after the read address is supplied.
    // ============================================================

    reg hsync = 1'b1;
    reg vsync = 1'b1;
    reg vde   = 1'b0;

    always @(posedge pixel_clk) begin
        if (video_reset) begin
            hsync <= 1'b1;
            vsync <= 1'b1;
            vde   <= 1'b0;
        end
        else begin
            hsync <= hsync_raw;
            vsync <= vsync_raw;
            vde   <= vde_raw;
        end
    end

    // ============================================================
    // Convert RGB332 framebuffer data to RGB888
    // ============================================================

    reg [7:0] red;
    reg [7:0] green;
    reg [7:0] blue;

    always @(*) begin
        red   = 8'h00;
        green = 8'h00;
        blue  = 8'h00;

        if (vde && frame_valid) begin
            // Expand 3-bit red to 8 bits.
            red = {
                framebuffer_pixel[7:5],
                framebuffer_pixel[7:5],
                framebuffer_pixel[7:6]
            };

            // Expand 3-bit green to 8 bits.
            green = {
                framebuffer_pixel[4:2],
                framebuffer_pixel[4:2],
                framebuffer_pixel[4:3]
            };

            // Expand 2-bit blue to 8 bits.
            blue = {
                framebuffer_pixel[1:0],
                framebuffer_pixel[1:0],
                framebuffer_pixel[1:0],
                framebuffer_pixel[1:0]
            };
        end
    end

    // ============================================================
    // HDMI encoder
    // ============================================================

    hdmi_tx_0 hdmi_encoder_inst (
        .pix_clk        (pixel_clk),
        .pix_clkx5      (pixel_clk_5x),
        .pix_clk_locked (clocks_locked),
        .rst            (video_reset),

        .red            (red),
        .green          (green),
        .blue           (blue),

        .hsync          (hsync),
        .vsync          (vsync),
        .vde            (vde),

        .aux0_din       (4'b0000),
        .aux1_din       (4'b0000),
        .aux2_din       (4'b0000),
        .ade            (1'b0),

        .TMDS_CLK_P     (HDMI_CLK_P),
        .TMDS_CLK_N     (HDMI_CLK_N),
        .TMDS_DATA_P    (HDMI_D_P),
        .TMDS_DATA_N    (HDMI_D_N)
    );

endmodule