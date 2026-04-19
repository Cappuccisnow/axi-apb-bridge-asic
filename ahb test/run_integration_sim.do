quit -sim

vlog -sv ahb_lite_slave.sv
vlog -sv ahb_lite_master.sv
vlog -sv ahb_system_top.sv
vlog -sv tb_ahb_system_top.sv

vsim work.tb_ahb_system_top

add wave -position insertpoint sim:/tb_ahb_system_top/*

run -all

radix hex
wave zoomfull