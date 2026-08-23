# MIPS32 Softmax Accelerator

A research-oriented RTL project extending a MIPS32 pipeline with a custom
instruction dedicated to accelerating the Softmax operation used in
Transformer attention. This project deliberately narrows scope to a
**single operator** rather than a full Transformer datapath, to keep the
work finishable and rigorously evaluated.

> **Status: early-stage.** The MIPS32 core is implemented. The Softmax
> accelerator itself (exponential unit, accumulator, normalization, custom
> decode) is design-in-progress, not yet built. See [Current Status](#current-status)
> for the honest breakdown.

## Motivation

Softmax is a fundamental operation in Transformer attention:

```
Softmax(x_i) = exp(x_i) / sum_j(exp(x_j))
```

Matrix multiplication dominates the FLOP count in Transformer workloads,
but Softmax is disproportionately expensive to execute efficiently on a
general-purpose core: it requires exponentiation, an accumulation across a
row, and a division per element — none of which map cleanly onto a
standard integer/float ALU pipeline. Division especially is costly in
hardware, and exponentials are usually done in software via costly
iterative approximations.

This project asks a narrow, answerable question: **does routing Softmax
through a dedicated custom MIPS32 instruction, backed by a small hardware
unit for exponential approximation and reciprocal-based division, reduce
latency and improve resource/energy efficiency compared to a pure-software
Softmax on the same core** — and at what numerical accuracy cost?

This is a deliberately smaller scope than related work such as RISC-VTF
(Jiao et al., 2021 SMC), which implements a full custom instruction set
for load/store, matrix multiply, matrix add, softmax, and ReLU on a
RISC-V core. This project isolates the softmax piece and aims to evaluate
it more rigorously — in particular, unlike that prior work, this project
tracks **numerical error** of the exponential approximation as a first-class
metric, not an afterthought.

### Why MIPS32 instead of RISC-V

Most recent custom-ISA accelerator work (including RISC-VTF) targets
RISC-V, which reserves dedicated `custom-0`–`custom-3` opcode space in its
spec explicitly for this purpose. MIPS32 has no equivalent reserved
encoding space, so this project repurposes an unused/reserved opcode
instead of a spec-sanctioned one. That is a real tradeoff versus RISC-V —
no comparable toolchain/ecosystem support, and the custom decode has to be
carved out by convention rather than by design. The choice here is
pedagogical/practical (building on existing MIPS32 familiarity), not a
claim that MIPS32 is technically preferable for this kind of extension.
This tradeoff is stated explicitly so it isn't mistaken for an oversight.

## Architecture

Based on a classic 5-stage MIPS32 pipeline:

```
IF → ID → EX → MEM → WB
```

A custom Softmax instruction will be added to the ISA, decoded in ID and
dispatched to a dedicated execution unit alongside the standard ALU:

```
MIPS32 CPU
      |
      | Custom Softmax instruction
      v
Softmax Accelerator
      |
      +── Exponential approximation unit
      +── Accumulation unit
      +── Normalization (reciprocal + multiply) unit
      |
      v
   Softmax output
```

The exponential approximation method (LUT-only, LUT + linear
interpolation, piecewise-polynomial, or bit-hack float approximation) is
not yet finalized — see [Open Design Decisions](#open-design-decisions).

## Current Status

### Completed
- MIPS32 5-stage pipeline processor (RTL, no custom instruction yet)
- Literature review: RISC-V custom ISA extensions for Transformer
  acceleration, hardware Softmax optimization techniques, hardware
  exponential approximation methods

### In Progress
- Custom instruction encoding definition (opcode/field layout)
- Exponential approximation method selection and error-bound analysis
- Softmax accelerator RTL design (exponential unit, accumulator,
  normalization)

### Planned
- Implement exponential approximation hardware
- Implement full Softmax accelerator datapath
- Integrate accelerator into the MIPS32 pipeline (hazard handling, stalls)
- Software baseline: Softmax via standard MIPS32 instructions
- Hardware-accelerated Softmax via custom instruction
- Functional verification (testbenches, directed + randomized vectors)
- FPGA synthesis and resource/power reporting
- Baseline vs. accelerated comparison (see metrics below)

## Baseline vs. Proposed Design

**Baseline:** Softmax computed with ordinary MIPS32 instructions —
software-driven exponential approximation, accumulation loop, and
division.

**Proposed:** Softmax computed by a single custom instruction that
dispatches to dedicated hardware.

```
Baseline:  MIPS32 → sequence of normal instructions → Softmax result
Proposed:  MIPS32 → single custom instruction → Softmax accelerator → result
```

### Evaluation metrics
- Clock cycles per Softmax call (fixed input size, then swept across sizes)
- End-to-end latency
- LUT utilization
- Flip-flop utilization
- DSP utilization
- BRAM utilization
- Power consumption (where the toolchain supports estimation)
- **Numerical error vs. IEEE-754 float32 softmax** (max and mean absolute
  error, and effect on argmax stability) — tracked from the first working
  version, not deferred to "future work"

## Open Design Decisions

These are unresolved and should be settled before RTL for the accelerator
proceeds, since they drive area/latency/accuracy tradeoffs:

1. **Exponential approximation method.** Candidates: pure lookup table,
   LUT + linear interpolation, piecewise-polynomial (as in RISC-VTF),
   Schraudolph-style bit-hack approximation. Each trades LUT size /
   pipeline depth against worst-case error — pick one and document the
   justification before implementation.
2. **Fixed-point vs. floating-point internal representation** for the
   accumulator and reciprocal stage.
3. **Row-size scaling.** Whether the accelerator supports arbitrary vector
   length in hardware or requires software chunking above some size.
4. **Reciprocal implementation.** One-time reciprocal + multiply (as in
   RISC-VTF) vs. direct hardware divider — affects both area and latency.

## Repository Structure

```
rtl/
├── cpu/            # MIPS32 5-stage pipeline (implemented)
├── softmax/         # Softmax accelerator datapath (planned)
└── custom_isa/       # Custom instruction decode logic (planned)

tb/
├── cpu/             # CPU testbenches
└── softmax/         # Accelerator testbenches (planned)

software/
├── baseline/         # Software-only Softmax reference (planned)
└── accelerated/       # Custom-instruction-driven Softmax test programs (planned)

docs/
├── architecture.md
├── isa_extension.md
└── results.md
```

## References

- Jiao, Hu, Liu, Dong. "RISC-VTF: RISC-V Based Extended Instruction Set
  for Transformer." 2021 IEEE International Conference on Systems, Man,
  and Cybernetics (SMC).
- Vaswani et al. "Attention Is All You Need." arXiv:1706.03762, 2017.
- Additional papers on hardware exponential approximation and Softmax
  optimization to be catalogued in `docs/`.

## Author

**Arpan Chandra**
NIT Durgapur
B.Tech 2023 - 27
