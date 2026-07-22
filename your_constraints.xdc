## ================================================================
## Blackboard 33.333 MHz FPGA clock
## ================================================================

set_property PACKAGE_PIN H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

## ================================================================
## Blackboard HDMI Source differential clock
## ================================================================

set_property -dict { PACKAGE_PIN U19 IOSTANDARD TMDS_33 } \
    [get_ports HDMI_CLK_N]

set_property -dict { PACKAGE_PIN U18 IOSTANDARD TMDS_33 } \
    [get_ports HDMI_CLK_P]


## ================================================================
## Blackboard HDMI Source differential data
## ================================================================

set_property -dict { PACKAGE_PIN V18 IOSTANDARD TMDS_33 } \
    [get_ports {HDMI_D_N[0]}]

set_property -dict { PACKAGE_PIN P18 IOSTANDARD TMDS_33 } \
    [get_ports {HDMI_D_N[1]}]

set_property -dict { PACKAGE_PIN P19 IOSTANDARD TMDS_33 } \
    [get_ports {HDMI_D_N[2]}]


set_property -dict { PACKAGE_PIN V17 IOSTANDARD TMDS_33 } \
    [get_ports {HDMI_D_P[0]}]

set_property -dict { PACKAGE_PIN N17 IOSTANDARD TMDS_33 } \
    [get_ports {HDMI_D_P[1]}]

set_property -dict { PACKAGE_PIN N18 IOSTANDARD TMDS_33 } \
    [get_ports {HDMI_D_P[2]}]