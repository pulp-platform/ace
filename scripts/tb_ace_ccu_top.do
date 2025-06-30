log -r *

log -class cache_test_pkg::cache_scoreboard::cache_scoreboard__1

do snoop_types.do

# Figure out number of masters from number of ACE interfaces
set n_masters [examine -radix unsigned sim:/tb_ace_ccu_top/TbNumMst]

add wave -divider "Clock and Reset"
add wave sim:/tb_ace_ccu_top/clk
add wave sim:/tb_ace_ccu_top/rst_n

add wave -divider "Towards memory"
add wave sim:/tb_ace_ccu_top/axi_intf/*

for {set n 0} {$n < $n_masters} {incr n 1} {
  add wave -divider "Towards cached master m$n"
  add wave sim:/tb_ace_ccu_top/ace_intf[$n]/*
  add wave -divider "Towards snooped cache m$n"
  add wave sim:/tb_ace_ccu_top/snoop_intf[$n]/*
}

onfinish stop
run -all
view wave
