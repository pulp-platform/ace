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

always_comb begin
    valid_o    = 1'b0;
    ready_o    = 1'b0;
    set_lock   = 1'b0;
    clear_lock = 1'b0;

    case (lock_q)
        1'b0: begin
            ready_o = 1'b1;
            if (valid_i) begin
                valid_o = 1'b1;
                if (!ready_i)
                    set_lock = 1'b1;
            end
        end
        1'b1: begin
            valid_o = 1'b1;
            if (ready_i) begin
                if (valid_i) begin
                    ready_o = 1'b1;
                    set_lock = 1'b1;
                end else
                    clear_lock = 1'b1;
            end
        end
    endcase
end

assign lock_d  = !clear_lock && (set_lock || lock_q);
assign data_o  = lock_q ? data_q : data_i;
assign data_d  = set_lock ? data_i : data_q;

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
