configure wave -signalnamewidth 1

add wave -divider "Clock and Reset"
add wave sim:/tb_ccu_ctrl_wr_snoop/DUT/clk_i
add wave sim:/tb_ccu_ctrl_wr_snoop/DUT/rst_ni
add wave -divider "FSM State"
add wave sim:/tb_ccu_ctrl_wr_snoop/DUT/fsm_state_q
add wave -divider "Towards cached master"
add wave sim:/tb_ccu_ctrl_wr_snoop/DUT/slv_req_i
add wave sim:/tb_ccu_ctrl_wr_snoop/DUT/slv_resp_o
add wave -divider "Towards memory"
add wave sim:/tb_ccu_ctrl_wr_snoop/DUT/mst_req_o
add wave sim:/tb_ccu_ctrl_wr_snoop/DUT/mst_resp_i
add wave -divider "Towards snooped cache"
add wave sim:/tb_ccu_ctrl_wr_snoop/DUT/snoop_req_o
add wave sim:/tb_ccu_ctrl_wr_snoop/DUT/snoop_resp_i

log -r *
onfinish stop
run -all
view wave