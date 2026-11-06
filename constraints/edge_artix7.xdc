## ============================================================
## edge_artix7.xdc - Light ABFT + Traditional ABFT, EDGE Artix-7 XC7A35T-1FTG256
## Pins from the team's previous working EDGE projects.
## ============================================================

## 50 MHz onboard clock
set_property -dict { PACKAGE_PIN N11 IOSTANDARD LVCMOS33 } [get_ports {clk}]
create_clock -name sys_clk -period 20.000 [get_ports {clk}]

## Push-buttons (pressed = 1): center = reset, top = start
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {rst}]
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {start_btn}]

## Data switches SW0-SW3
set_property -dict { PACKAGE_PIN L5 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {data_sw[0]}]
set_property -dict { PACKAGE_PIN L4 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {data_sw[1]}]
set_property -dict { PACKAGE_PIN M4 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {data_sw[2]}]
set_property -dict { PACKAGE_PIN M2 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {data_sw[3]}]

## Fault switch = SW7
set_property -dict { PACKAGE_PIN N1 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {fault_sw}]

## LEDs (active-high)
set_property -dict { PACKAGE_PIN J3 IOSTANDARD LVCMOS33 } [get_ports {led_done}]
set_property -dict { PACKAGE_PIN H3 IOSTANDARD LVCMOS33 } [get_ports {led_ok}]
set_property -dict { PACKAGE_PIN J1 IOSTANDARD LVCMOS33 } [get_ports {led_error}]
set_property -dict { PACKAGE_PIN K1 IOSTANDARD LVCMOS33 } [get_ports {led_trad_error}]
set_property -dict { PACKAGE_PIN L3 IOSTANDARD LVCMOS33 } [get_ports {led_col[0]}]
set_property -dict { PACKAGE_PIN L2 IOSTANDARD LVCMOS33 } [get_ports {led_col[1]}]
set_property -dict { PACKAGE_PIN K3 IOSTANDARD LVCMOS33 } [get_ports {led_col[2]}]
set_property -dict { PACKAGE_PIN K2 IOSTANDARD LVCMOS33 } [get_ports {led_col[3]}]

## Bitstream settings
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
