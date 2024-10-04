module ace_ccu_lock_reg #(
    parameter type dtype = logic
)(
    input  logic clk_i,
    input  logic rst_ni,

    input  logic valid_i,
    output logic ready_o,
    input  dtype data_i,

    output logic valid_o,
    input  logic ready_i,
    output dtype data_o
);

logic clear_lock, set_lock;

logic lock_q, lock_d;
dtype data_q, data_d;

assign valid_o    = valid_i || lock_q;
assign ready_o    = (valid_o && ready_i) || !lock_q;
assign set_lock   = valid_i && (!ready_i || lock_q);
assign clear_lock = valid_o && ready_i;
assign lock_d     = set_lock || (!clear_lock && lock_q);
assign data_d     = valid_i && ready_o ? data_i : data_q;
assign data_o     = lock_q ? data_q : data_i;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        lock_q <= 1'b0;
        data_q <= dtype'('0);
    end else begin
        lock_q <= lock_d;
        data_q <= data_d;
    end
end

endmodule
