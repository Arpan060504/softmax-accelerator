# Architecture

This document describes what is actually instantiated in `softmax_top.v`,
not the full inventory of files in `rtl/`. A few modules that exist and have
testbenches are **not** part of this architecture — see the "Modules that
exist but are not wired in" section at the bottom. Don't read `module_documentation.md`'s
file list as a description of the live datapath; this document is.

## Scope

The design computes Softmax over exactly **4 FP32 inputs** (`x0..x3`) and
produces 4 FP32 outputs. It is not parameterized for arbitrary vector length.
It does not implement the max-subtraction numerical-stability trick
(`exp(x_i - max(x))`) — correctness depends on inputs already lying in the
`[-4.0, +4.0]` range the exponential LUT covers. Inputs outside that range
are clamped in `region_detector.v`, which silently produces a wrong (but
bounded) answer rather than flagging overflow.

## Top-level block diagram

```
              ┌────────────────────────┐
   x0..x3 ───►│  softmax_exp_accumulator│
              │  (softmax_exp_accumulator.V)│
              │                          │
              │  ┌────────────────────┐  │
              │  │ softmax_exp_engine  │  │──► exp_out (per-element, RAM-read)
              │  │  input_selector     │  │
              │  │  exp_unit           │  │
              │  │   region_detector   │  │
              │  │   exp_lut           │  │
              │  │   fp32_multiplier   │  │
              │  │   fp32_adder        │  │
              │  └────────────────────┘  │
              │  ┌────────────────────┐  │
              │  │ exp_accumulator     │  │──► sum  (Σ exp(x_i))
              │  │  fp32_adder          │  │──► done
              │  │  exp_mem[0:3] (RAM)  │  │
              │  └────────────────────┘  │
              └───────────┬──────────────┘
                          │ sum
                          ▼
              ┌────────────────────────┐
              │   reciprocal_unit       │   1 / sum, LUT-seeded
              │   (rtl/reciprocal_unit/)│   Newton-Raphson (see algorithm.md)
              └───────────┬──────────────┘
                          │ reciprocal_value
                          ▼
              ┌────────────────────────┐
   exp_out ──►│   softmax_normalizer    │──► softmax0..softmax3
              │   (fp32_multiplier)     │
              └────────────────────────┘
```

## Control FSM (`softmax_top.v`)

States: `IDLE → EXP → RECIP → READ → NORMALIZE → FINISH → IDLE`

- **IDLE** — waits for `start`.
- **EXP** — waits for `exp_done` from `softmax_exp_accumulator` (which
  internally streams all 4 inputs through the exp engine one at a time and
  accumulates the sum in `exp_accumulator`'s internal RAM).
- **RECIP** — one clock cycle allotted for the (combinational) reciprocal
  path to settle before it's read.
- **READ / NORMALIZE** — loop 4 times, reading one stored `exp_out` value
  per cycle from `exp_accumulator`'s internal memory via `read_addr`,
  multiplying it by the reciprocal, and latching the result into
  `softmax0..softmax3`. `softmax_valid` pulses high for one cycle per
  output.
- **FINISH** — asserts `done` for one cycle, returns to `IDLE`.

Total latency is on the order of 4 (exp engine cycles) + 1 (recip settle) +
4 (normalize loop) + a couple of FSM overhead cycles — exact cycle count
hasn't been measured/documented anywhere yet (see `results.md`).

## Modules that exist but are not wired in

These have their own testbenches (`tb/softmax/*_tb.v`) and pass in
isolation, but `softmax_top.v` does not instantiate them. They appear to be
an earlier or alternative control-path design that was superseded by the
FSM directly in `softmax_top.v`:

- `softmax_read_controller.v`
- `softmax_normalization_controller.v` (which itself wraps `softmax_normalization_stage.v`)

If there's a reason to keep them (e.g. a planned refactor to move
normalization sequencing out of `softmax_top`), that reasoning belongs in
this file. As it stands, a reader has no way to know whether this is
intentional or leftover.

## Known correctness gaps at the architecture level

- **No numerical stabilization.** Standard Softmax implementations subtract
  `max(x)` before exponentiating to avoid overflow. This design doesn't —
  it relies entirely on the input range being pre-constrained to `[-4, 4]`.
  That constraint is not enforced or checked anywhere in hardware; it's an
  assumption on the caller.
- **Fixed width of 4.** Any real workload (attention softmax over a
  sequence) will need either an N-wide version or an iterative/streaming
  version. Neither exists yet.
- **`reciprocal_unit` is purely combinational** and only verified for
  positive, normal inputs (see `verification.md`). The FSM gives it exactly
  one clock cycle (`RECIP` state) to settle — if the combinational path
  turns out to be timing-critical at synthesis, one cycle may not be
  enough margin; this has not been checked because synthesis hasn't been
  run.
