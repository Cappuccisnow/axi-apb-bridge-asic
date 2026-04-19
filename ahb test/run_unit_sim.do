quit -sim

vlog -sv ahb_lite_slave.sv
vlog -sv tb_ahb_lite_slave.sv

vsim work.tb_ahb_lite_slave

add wave -position insertpoint sim:/tb_ahb_lite_slave/*

run -all

radix hex
wave zoomfull