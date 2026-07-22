# NovaCore-Lite

NovaCore-Lite is a fixed-function FPGA 3D graphics accelerator written in Verilog.

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
rtl/          Verilog source files
constraints/  FPGA constraints file
demo/         Hardware demonstration video