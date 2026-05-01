# WashU-2 CPU — VHDL Implementation

A 16-bit accumulator-based multi-cycle CPU implemented in VHDL, based on the
WashU-2 architecture. The project involved studying the CPU design, implementing
missing instructions in the ALU and FSM, and writing testbenches to verify correctness.

---

## What it does

- Implements the **ADD** operation in the ALU and verifies it with a testbench
- Implements the **BRPOS** (Branch if Positive) instruction in the FSM state handler
- Writes a combined **ADD + AND** test program exercising both operations together
- Verifies all implementations via simulation waveforms in ModelSim / GHDL / Vivado

---

## Architecture

The WashU-2 is a 16-bit, accumulator-based, non-pipelined processor controlled by
a 17-state FSM. Each instruction takes 4–7 clock cycles through a
fetch → execute → wrapup pipeline.

**Key registers:** ACC (accumulator), PC (program counter), iReg (instruction register),
IAR (indirect address), THIS (saved PC), tick (4-bit sub-cycle counter)

**Instruction format:** 4-bit opcode + 12-bit operand, encoded as a 16-bit word

**Address modes:**
- Page-relative: `opAdr = THIS[15:12] & iReg[11:0]`
- PC-relative branch: `target = THIS + sign_extend(iReg[7:0])`

---

## Tasks

**Task 1 — Study & simulate:** Simulated the provided AND testbench across 3 test
cases (`0xFF AND 0xFF`, `0x0F AND 0xF0`, `0x0F AND 0xAB`) and studied the full
FSM, decode function, and fetch-execute cycle.

**Task 2 — ADD implementation:** Added the missing ADD operation to the ALU
combinational assignment, following the same `unsigned` arithmetic pattern as NEGATE.
Wrote a testbench verifying `7 + 8 = 15` stored at `mem[0x12]`.

**Task 3 — Combined ADD + AND:** Wrote a single instruction sequence performing
two additions (`7+8=15`, `5+6=11`) then ANDing the results (`15 AND 11 = 0x0B`),
verifying all three memory locations.

**Task 4 — BRPOS implementation:** Implemented the branch-if-positive logic
checking `acc(15) = '0'` AND `acc ≠ 0x0000` simultaneously. Wrote a testbench
covering all three cases (positive → branch taken, zero → not taken, negative → not
taken).

---

## Instruction Set (subset used)

| Mnemonic | Encoding | Description |
|----------|----------|-------------|
| `CLOAD imm` | `0x1xxx` | ACC = sign_extend(imm) |
| `DLOAD adr` | `0x2xxx` | ACC = memory[adr] |
| `DSTORE adr` | `0x5xxx` | memory[adr] = ACC |
| `ADD adr` | `0x8xxx` | ACC = ACC + memory[adr] |
| `AND adr` | `0xCxxx` | ACC = ACC AND memory[adr] |
| `BRPOS offset` | `0x03xx` | PC = PC + offset if ACC > 0 |
| `HALT` | `0x0000` | Stop execution |

---



## Tools

VHDL · ModelSim Alterra
