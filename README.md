# ACE SystemVerilog modules for cache coherent SoC design

> 🚧 **Work in progress:** this repository is under active development. Breaking changes can happen at any time. 🚧

This repository provides modules to implement cache coherence SoCs.

## Repository structure

```
src/
├── ace_intf.sv        # ACE bus interface definitions
├── ace_pkg.sv         # ACE type definitions and constants
├── snoop_intf.sv      # Snoop channel interface definitions
└── ccu/               # Coherence Control Unit
    ├── ccu_top.sv
    ├── ccu_pkg.sv
    ├── ccu_frontend.sv
    ├── ccu_frontend_arbiter.sv
    ├── ccu_read_engine.sv
    ├── ccu_write_engine.sv
    ├── ccu_snoop_pipeline.sv
    ├── ccu_replay.sv
    ├── ccu_exclusive_monitor.sv
    ├── ccu_csr_wrap.sv
    ├── ccu_scoreboard.sv
    └── regs/          # CSR definitions and generated register files

include/
└── ace/               # SystemVerilog header files (typedef, assign, convert, domain macros)
```

## Include files

| Name                                              | Description                                        |
|---------------------------------------------------|----------------------------------------------------|
| [`ace/typedef.svh`](include/ace/typedef.svh)      | Macros for defining ACE and snoop struct types     |
| [`ace/assign.svh`](include/ace/assign.svh)        | Macros for assigning ACE and snoop signals         |
| [`ace/convert.svh`](include/ace/convert.svh)      | Macros for converting between ACE signal formats   |
| [`ace/domain.svh`](include/ace/domain.svh)        | Macros for ACE domain signal handling              |

## License

The ACE repository is released under Solderpad v0.51 (SHL-0.51) see [LICENSE](LICENSE)

## Publication

If you use ACE/Culsans in your work, you can cite us:

```
@article{tedeschi2024culsans,
    title={Culsans: An Efficient Snoop-based Coherency Unit
           for the CVA6 Open Source RISC-V application processor},
    volume={10},
    number={2},
    journal={WiPiEC Journal - Works in Progress in Embedded Computing Journal},
    author={Tedeschi, Riccardo and Valente, Luca and Ottavi, Gianmarco and
            Zelioli, Enrico and Wistoff, Nils and
            Giacometti, Massimiliano and Basit Sajjad, Abdul and
            Benini, Luca and Rossi, Davide},
    year={2024},
    month={Aug.}
}

```
