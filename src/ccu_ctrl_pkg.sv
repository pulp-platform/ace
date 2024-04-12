package ccu_ctrl_pkg;

    typedef enum logic [3:0] {
        SEND_AXI_REQ_R,
        SEND_AXI_REQ_WRITE_BACK_R,
        SEND_AXI_REQ_W,
        SEND_AXI_REQ_WRITE_BACK_W,
        LEGACY_WAIT_WRITE,
        LEGACY_WAIT_READ,
        LEGACY_WAIT_WB
    } mu_op_e;

    typedef enum logic {
        READ_SNP_DATA,
        SEND_INVALID_ACK_R
    } su_op_e;

endpackage