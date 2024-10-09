`include "ace/assign.svh"

module ace_to_axi #(
    parameter type slv_req_t     = logic, // Slave port request type
    parameter type slv_resp_t    = logic, // Slave port response type
    parameter type mst_req_t     = logic, // Master ports request type
    parameter type mst_resp_t    = logic  // Master ports response type
) (
    input  slv_req_t  ace_req_i,
    output slv_resp_t ace_resp_o,
    output mst_req_t  axi_req_o,
    input  mst_resp_t axi_resp_i
);

    // Drop all ACE fields not present in AXI

    // AW
    assign axi_req_o.aw.id     = ace_req_i.id      ;
    assign axi_req_o.aw.addr   = ace_req_i.addr    ;
    assign axi_req_o.aw.len    = ace_req_i.len     ;
    assign axi_req_o.aw.size   = ace_req_i.size    ;
    assign axi_req_o.aw.burst  = ace_req_i.burst   ;
    assign axi_req_o.aw.lock   = ace_req_i.lock    ;
    assign axi_req_o.aw.cache  = ace_req_i.cache   ;
    assign axi_req_o.aw.prot   = ace_req_i.prot    ;
    assign axi_req_o.aw.qos    = ace_req_i.qos     ;
    assign axi_req_o.aw.region = ace_req_i.region  ;
    assign axi_req_o.aw.atop   = ace_req_i.atop    ;
    assign axi_req_o.aw.user   = ace_req_i.user    ;
    assign axi_req_o.aw_valid  = ace_req_i.aw_valid;
    assign ace_req_i.aw_ready  = axi_req_o.aw_ready;

    // AR
    assign axi_req_o.ar.id     = ace_req_i.id      ;
    assign axi_req_o.ar.addr   = ace_req_i.addr    ;
    assign axi_req_o.ar.len    = ace_req_i.len     ;
    assign axi_req_o.ar.size   = ace_req_i.size    ;
    assign axi_req_o.ar.burst  = ace_req_i.burst   ;
    assign axi_req_o.ar.lock   = ace_req_i.lock    ;
    assign axi_req_o.ar.cache  = ace_req_i.cache   ;
    assign axi_req_o.ar.prot   = ace_req_i.prot    ;
    assign axi_req_o.ar.qos    = ace_req_i.qos     ;
    assign axi_req_o.ar.region = ace_req_i.region  ;
    assign axi_req_o.ar.user   = ace_req_i.user    ;
    assign axi_req_o.ar_valid  = ace_req_i.ar_valid;
    assign ace_req_i.ar_ready  = axi_req_o.ar_ready;

    // W
    `AXI_ASSIGN_W (axi_req_o, ace_req_i)

    // B
    `AXI_ASSIGN_B (ace_req_i, axi_req_o)

    // R
    assign ace_req_i.r.id    = axi_req_o.id           ;
    assign ace_req_i.r.data  = axi_req_o.data         ;
    assign ace_req_i.r.resp  = {2'b00, axi_req_o.resp};
    assign ace_req_i.r.last  = axi_req_o.last         ;
    assign ace_req_i.r.user  = axi_req_o.user         ;
    assign ace_req_i.r_valid = axi_req_o.r_valid      ;
    assign axi_req_o.r_ready = ace_req_i.r_ready      ;

endmodule
