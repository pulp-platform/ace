# ACE SystemVerilog modules for cache coherent SoC design

This repository provides modules to implement cache coherence SoC's.

## List of modules

| Name                                                 | Description                                                                                                  | Doc                            |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|--------------------------------|
| [`ace_ccu_top`](src/ace_ccu_top.sv)                  | ACE interconnector, broadcasts snooping messages to the cache controllers and AXI transactions to the slave  | [Doc](doc/ace_ccu_top.md)      |
| [`ace_dummy_handler`](src/ace_dummy_handler.sv)      | ACE dummy slave, to handle some coherence requests from C910 core in the single-core configuration           |                                |

## License

The ACE repository is released under Solderpad v0.51 (SHL-0.51) see [LICENSE](LICENSE)