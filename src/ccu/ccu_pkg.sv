  package ccu_pkg;

  typedef struct packed {
    int unsigned DcacheLineWidth;
    int unsigned AxiAddrWidth;
    int unsigned AxiDataWidth;
    int unsigned AxiUserWidth;
    int unsigned AxiSlvIdWidth;
    int unsigned NoSlvPorts;
    int unsigned NoSlvPerGroup;
    bit          AmoHotfix;
  } ccu_cfg_t;

  function automatic int unsigned CcuAxiMstIdWidth (ccu_cfg_t ccu_cfg);
      int unsigned NoGroups = ccu_cfg.NoSlvPorts / ccu_cfg.NoSlvPerGroup;
      return (ccu_cfg.AxiSlvIdWidth         + // Initial ID width
              $clog2(ccu_cfg.NoSlvPerGroup) + // Internal MUX additional bits
              $clog2(3*NoGroups)            + // Final MUX additional bits
              1);                             // AMO support
  endfunction

  endpackage
