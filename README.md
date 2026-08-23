# Softmax Hardware Accelerator

A synthesizable, all-combinational-plus-FSM RTL implementation of Softmax in
IEEE-754 single-precision (FP32), built from scratch: custom FP32 adder and
multiplier, a piecewise-linear exponential unit, a LUT + Newton–Raphson
reciprocal unit, and a control FSM that ties them together into a working
4-element Softmax datapath.

> **Status honesty note:** an earlier version of this README described a
> MIPS32 CPU with a custom Softmax instruction. That CPU/ISA work does not
> exist in this repository yet — there is no `cpu/`, `custom_isa/`, or
> `software/` directory. What exists today is the standalone Softmax
> accelerator datapath described below. See
> [`docs/future_work.md`](docs/future_work.md) for what MIPS integration
> would actually require.

```
Softmax(x_i) = exp(x_i) / sum_j(exp(x_j))
```

## What's actually implemented

A **fixed-width, 4-input** Softmax pipeline (`x0, x1, x2, x3` in →
`softmax0..softmax3` out), controlled by an FSM in `softmax_top.v`:

```
x0..x3 → [exp engine] → [exp accumulator] → sum
                                              │
                                     [reciprocal unit] (1/sum)
                                              │
exp values ─────────────────────────► [normalizer] → softmax0..softmax3
```

No batching, no arbitrary vector length, no exponent-max-subtraction
(numerical stabilization) — inputs are assumed to already sit inside the
`[-4, 4]` range the exponential LUT was built for. See
[`docs/algorithm.md`](docs/algorithm.md) for the exact math and
[`docs/architecture.md`](docs/architecture.md) for how the modules connect
(including the modules that are built and tested but **not** currently wired
into the top level).

## Repository layout

This repo's actual layout does **not** match a "clean" target structure yet.
Mapping what exists to what a tidier layout would look like:

| In this repo today | Would map to |
|---|---|
| `rtl/fp32/` | `rtl/arithmetic/` |
| `rtl/reciprocal_unit/` (top-level) | `rtl/softmax/reciprocal_unit.v` |
| `rtl/exp/` | matches |
| `rtl/softmax/` | matches, minus dead files (see below) |
| `rtl/top/softmax_top.v` | matches |
| `tb/fp32/`, `tb/reciprocal/`, `tb/softmax/` | should split into `tb/arithmetic/`, `tb/exp/`, `tb/softmax/`, `tb/top/` — **`tb/exp/` doesn't exist**, there is no standalone testbench for `exp_unit`/`exp_lut`/`region_detector` |

Known cruft that should be deleted or resolved, not documented as if it's
fine:

- `rtl/softmax/reciprocal_unit.v` — **empty file** (0 bytes), dead stub,
  same module name as the real `reciprocal_unit`. Delete it.
- `softmax_exp_accumulator.V` — capital `.V` extension, inconsistent with
  every other file. Rename to `.v`.
- `softmax_read_controller.v`, `softmax_normalization_controller.v`,
  `softmax_normalization_stage.v` — each has a testbench, but none of them
  is instantiated by `softmax_top.v`. Either wire them in or remove them;
  right now they're tested dead code.

## Directory structure (target)

```
softmax-hardware-accelerator/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── algorithm.md
│   ├── module_documentation.md
│   ├── verification.md
│   ├── results.md
│   └── future_work.md
├── rtl/
│   ├── arithmetic/        fp32_adder.v, fp32_multiplier.v
│   ├── exp/                exp_unit.v, exp_lut.v, region_detector.v
│   ├── softmax/             input_selector.v, softmax_exp_engine.v,
│   │                        exp_accumulator.v, reciprocal_unit.v,
│   │                        softmax_normalizer.v, ...
│   └── top/                 softmax_top.v
├── tb/
├── simulation/
├── results/
├── paper/
└── .gitignore
```

## Quick start (simulation)

No simulation scripts are checked into the repo yet (no `simulation/`
contents, no Makefile/run scripts). To run a testbench manually with
Icarus Verilog:

```bash
iverilog -o sim.out \
  rtl/arithmetic/fp32_adder.v \
  rtl/arithmetic/fp32_multiplier.v \
  rtl/reciprocal_unit/reciprocal_lut.v \
  rtl/reciprocal_unit/reciprocal_unit.v \
  tb/reciprocal/reciprocal_unit_tb.v
vvp sim.out
```

Adjust file paths for whichever module you're testing. See
[`docs/verification.md`](docs/verification.md) for what's actually been
run and what hasn't.

## Current status

| Area | Status |
|---|---|
| FP32 adder / multiplier | Implemented, has a testbench |
| Piecewise-linear exp unit | Implemented, **no standalone testbench** |
| LUT + Newton-Raphson reciprocal unit | Implemented, tested, results documented (18 vectors, max 0.092% error, positive-only) |
| Softmax datapath (4-wide) | Implemented, wired end-to-end in `softmax_top.v` |
| Alternative control modules (read/normalization controller) | Implemented, individually tested, **not integrated** |
| MIPS32 core / custom instruction | Not started |
| FPGA synthesis / resource numbers | Not started |
| `results/` data (CSVs, plots) | Not started |

## Author

Arpan
