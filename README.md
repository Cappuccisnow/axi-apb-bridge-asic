# AXI4-to-I2C and APB-to-SPI Bridges for ASIC Design

This repository contains the Verilog RTL, verification environments, and physical implementation results for my Bachelor's Thesis: **"Design and Implementation of AXI-to-I2C and APB-to-SPI Bridges, using Sky130 open-source PDK."**

## Overview
This project addresses the integration of low-speed peripherals into high-performance SoCs by implementing two essential bridge modules using the **SkyWater 130nm PDK** and the **OpenLane** ASIC flow:

1.  **AXI4-Lite to I2C Bridge:**
    * Designed for robust, handshake-driven communication.
    * Features independent Read/Write channels and full AXI4-Lite protocol compliance.
    * Includes a custom I2C Master core with clock synchronization.

2.  **APB to SPI Bridge:**
    * A lightweight, area-optimized interface for simple peripherals.
    * Implements a standard 4-wire SPI (Mode 0) interface.
    * Designed for high density and low power consumption.

## Repository Structure
The project is organized to separate the source code, verification, and physical implementation files for each bridge.

```
/axi-apb-bridge-asic
  ├── /src               # Synthesizable Verilog RTL
  │     ├── /axi_i2c     # AXI Bridge source files
  │     └── /apb_spi     # APB Bridge source files
  ├── /test              # Simulation Testbenches
  │     ├── /axi_i2c     # AXI Testbench
  │     └── /apb_spi     # APB Testbench
  ├── /openlane          # OpenLane Configuration Files (config.json)
  │     ├── /axi_i2c
  │     └── /apb_spi
  ├── /fpga              # Quartus Prime Projects & Pin Assignments (.qsf)
  └── /results           # Final GDSII Layouts & Reports
```
## How to Run

### 1. Pre-requisites
* **Simulation:** Icarus Verilog (`iverilog`) & GTKWave
* **ASIC Flow:** OpenLane (Docker version)
* **FPGA:** Intel Quartus Prime (Lite Edition)

### 2. Run Simulation (Icarus Verilog)
To verify the logic before synthesis:

**AXI4-Lite to I2C Bridge:**
```
cd test/axi_i2c
iverilog -o tb_axi tb_axi_bridge.v ../../src/axi_i2c/*.v
vvp tb_axi
gtkwave waves.vcd  # Optional: View waveforms
```

**APB to SPI Bridge: **
```
cd test/apb_spi
iverilog -o tb_apb tb_apb_bridge.v ../../src/apb_spi/*.v
vvp tb_apb
gtkwave waves.vcd
```

### 3. Run Physical Implementation (OpenLane)
To generate the GDSII layout from RTL:
# Start OpenLane Shell
cd openlane
make mount

# Run AXI Bridge Flow
./flow.tcl -design axi_i2c -tag final_run

# Run APB Bridge Flow
./flow.tcl -design apb_spi -tag final_run

Check /result for the final .gds and .rpt files.

### 4. FPGA Prototyping (Altera DE2)
1. Open Quartus Prime.
2. Load the project file (.qpf) from the fpga/ directory.
3. Ensure pin assignments match fpga/de2_assignments.qsf.
4. Compile and click Programmer to flash the .sof file.
