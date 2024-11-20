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

### Coherency check

To run coherency check, run
```
make init_mem CHECK=1
```
It will generate the initial cache and memory states, and stall until given a prompt.

Next, open another terminal and simulate the top level design with
```
make -B sim-ace_ccu_top.log
```
Once the simulation finishes, press enter on the coherency check prompt. A coherency check will be run. A log file is generated called `cache_python.log`. Search with keyword `ERROR` to find whether coherency was broken during the simulation. When run with `DEBUG=1` (the default option), a pdb session is opened the moment a coherency problem is found.

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
