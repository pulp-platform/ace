# ACE SystemVerilog modules for cache coherent SoC design

This repository provides modules to implement cache coherence SoC's.

## List of modules

| Name                                                 | Description                                                                                                  | Doc                            |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|--------------------------------|
| [`ace_ccu_top`](src/ace_ccu_top.sv)                  | ACE interconnector, broadcasts snooping messages to the cache controllers and AXI transactions to the slave  | [Doc](doc/ace_ccu_top.md)      |

## Verification

Generate the initial cache and memory states, as well as the transaction streams, with the following command:

```
make init_mem
```

You can control simulation parameters, such as the memory and cache sizes and structures, number of caches, and number of transactions, in `Makefile`.

You can simulate the top level design with
```
make -B sim-ace_ccu_top.log
```

## License

The ACE repository is released under Solderpad v0.51 (SHL-0.51) see [LICENSE](LICENSE)