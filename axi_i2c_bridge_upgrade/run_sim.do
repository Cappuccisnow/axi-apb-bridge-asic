quit -sim

vlog -sv async_fifo.sv
vlog -sv dual_port_ram.sv
vlog -sv fifo_rptr.sv
vlog -sv fifo_wptr.sv
vlog -sv sync_ptr.sv

vlog -sv axi_lite_slave.sv
vlog -sv i2c_master.sv
vlog -sv axi_i2c_bridge.sv
vlog -sv tb_axi_i2c_bridge.sv

vsim work.tb_axi_i2c_bridge

add wave -position insertpoint sim:/tb_axi_i2c_bridge/*

run -all

radix hex
wave zoomfull