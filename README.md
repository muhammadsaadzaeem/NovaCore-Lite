# NovaCore-Lite

NovaCore-Lite is a fixed-function FPGA 3D graphics accelerator implemented in Verilog for the Zynq-7000 platform.

It renders a rotating, filled, lit, and depth-tested cube through HDMI using a custom hardware graphics pipeline.

## Features

- Fixed-point 3D vertex transformation
- Filled-triangle rasterization
- Incremental edge-function evaluation
- Back-face culling
- Dynamic flat-face lighting
- Per-pixel depth interpolation
- Hardware Z-buffer
- Double-buffered RGB332 framebuffer
- 640 × 480 HDMI output
- 160 × 120 internal rendering resolution

## Hardware

- Zynq-7000 FPGA development board
- HDMI display
- Vivado 2025.2

## Project Structure

```text
draw_engine.v         Cube generation, rotation, lighting, culling, and control
triangle_engine.v     Triangle rasterization and per-pixel depth interpolation
novacore_top.v        Top-level framebuffer, depth-buffer, video, and HDMI logic
novacore_lite.xdc     FPGA pin and timing constraints
rotating_cube.mp4     Hardware demonstration video

## Demo

🎥 [Watch NovaCore-Lite running on FPGA](./rotating_cube.mp4)
