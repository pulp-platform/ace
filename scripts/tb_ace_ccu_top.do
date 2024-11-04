log -r *

log -class cache_test_pkg::cache_scoreboard::cache_scoreboard__1

do snoop_types.do

# Figure out number of masters from number of ACE interfaces
set n_masters [llength [find instances sim:/tb_ace_ccu_top/ace_intf*]]

# number of snoop blocks
set n_snoops [llength [find blocks sim:/tb_ace_ccu_top/ccu/i_ace_ccu_top/i_master_path/gen_snoop*]]

add wave -divider "Clock and Reset"
add wave sim:/tb_ace_ccu_top/ccu/clk_i
add wave sim:/tb_ace_ccu_top/ccu/rst_ni

add wave -divider "Towards memory"
add wave sim:/tb_ace_ccu_top/ccu/mst_req
add wave sim:/tb_ace_ccu_top/ccu/mst_resp

for {set n 0} {$n < $n_masters} {incr n 1} {
  add wave -divider "Towards cached master m$n"
  add wave sim:/tb_ace_ccu_top/ccu/slv_reqs[$n]
  add wave sim:/tb_ace_ccu_top/ccu/slv_resps[$n]
  add wave -divider "Towards snooped cache m$n"
  add wave sim:/tb_ace_ccu_top/ccu/snoop_reqs[$n]
  add wave sim:/tb_ace_ccu_top/ccu/snoop_resps[$n]

  radix signal sim:/tb_ace_ccu_top/ccu/slv_reqs[$n].aw.snoop WriteSnoop
  radix signal sim:/tb_ace_ccu_top/ccu/slv_reqs[$n].ar.snoop ReadSnoop
}

for {set n 0} {$n < $n_snoops} {incr n 1} {
  add wave -divider "FSM State $n"
  add wave -label r_fsm sim:/tb_ace_ccu_top/ccu/i_ace_ccu_top/i_master_path/gen_snoop[$n]/i_snoop_path/i_ccu_ctrl_r_snoop/fsm_state_q
  add wave -label wr_fsm sim:/tb_ace_ccu_top/ccu/i_ace_ccu_top/i_master_path/gen_snoop[$n]/i_snoop_path/i_ccu_ctrl_wr_snoop/fsm_state_q
}

onfinish stop
run -all
view wave