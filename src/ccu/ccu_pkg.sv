  package ccu_pkg;

  /// Configuration for `ace_ccu`.
  typedef struct packed {
    int unsigned  NoSlvPorts;
    int unsigned  MaxMstTrans;
    int unsigned  MaxSlvTrans;
    bit           FallThrough;
    ccu_latency_e LatencyMode;
    int unsigned  AxiIdWidthSlvPorts;
    int unsigned  AxiIdUsedSlvPorts;
    bit           UniqueIds;
    int unsigned  AxiAddrWidth;
    int unsigned  AxiDataWidth;
    int unsigned  AxiUserWidth;
    int unsigned  DcacheLineWidth;
    int unsigned  DcacheIndexWidth;
  } ccu_cfg_t;

  /// Slice on Demux AW channel.
  localparam logic [9:0] DemuxAw = (1 << 9);
  /// Slice on Demux W channel.
  localparam logic [9:0] DemuxW  = (1 << 8);
  /// Slice on Demux B channel.
  localparam logic [9:0] DemuxB  = (1 << 7);
  /// Slice on Demux AR channel.
  localparam logic [9:0] DemuxAr = (1 << 6);
  /// Slice on Demux R channel.
  localparam logic [9:0] DemuxR  = (1 << 5);
  /// Slice on Mux AW channel.
  localparam logic [9:0] MuxAw   = (1 << 4);
  /// Slice on Mux W channel.
  localparam logic [9:0] MuxW    = (1 << 3);
  /// Slice on Mux B channel.
  localparam logic [9:0] MuxB    = (1 << 2);
  /// Slice on Mux AR channel.
  localparam logic [9:0] MuxAr   = (1 << 1);
  /// Slice on Mux R channel.
  localparam logic [9:0] MuxR    = (1 << 0);
  /// Latency configuration for `ace_xbar`.
  typedef enum logic [9:0] {
    NO_LATENCY    = 10'b000_00_000_00,
    CUT_SLV_AX    = DemuxAw | DemuxAr,
    CUT_MST_AX    = MuxAw | MuxAr,
    CUT_ALL_AX    = DemuxAw | DemuxAr | MuxAw | MuxAr,
    CUT_SLV_PORTS = DemuxAw | DemuxW | DemuxB | DemuxAr | DemuxR,
    CUT_MST_PORTS = MuxAw | MuxW | MuxB | MuxAr | MuxR,
    CUT_ALL_PORTS = 10'b111_11_111_11
  } ccu_latency_e;

  endpackage