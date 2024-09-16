package ccu_ctrl_pkg;

    typedef enum logic [3:0] {
        SEND_AXI_REQ_R,
        SEND_AXI_REQ_WRITE_BACK_R,
        SEND_AXI_REQ_W,
        SEND_AXI_REQ_WRITE_BACK_W,
        AMO_WAIT_WB_R,
        AMO_WAIT_WB_W
    } mu_op_e;

    typedef enum logic {
        READ_SNP_DATA,
        SEND_INVALID_ACK_R
    } su_op_e;

    typedef enum logic { MEMORY_UNIT, SNOOP_UNIT } cd_user_t;

endpackage