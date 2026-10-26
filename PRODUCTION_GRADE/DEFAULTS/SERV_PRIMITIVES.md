# SERV primitive coverage diagnostics

The synthesized SERV netlist uses RAMB36E1, RAM64M, SRLC32E,
MUXF7 and MUXF8, absent from previously passing individual examples.
Each example uses LED0 as an independent heartbeat, LED1 as a completed
observation, LED2 as a sticky mismatch, and LED3 as a live primitive output.
When correct, LED0 toggles, LED1 eventually illuminates, and LED2 stays off.

11_ramb36: initialized 4096 x 8 RAM, full read sweep.
12_ram64m: 64 x 4 distributed register-memory, read/write.
13_srlc32e: direct SRLC32E and reference shift sequence.
14_muxf78: direct LUT6 -> MUXF7 -> MUXF8 hierarchy.

The CI synthesis and routing checks do not establish FPGA physical behavior.
Flash each pair of top.v/top.xdc to verify its primitive on the real board.
