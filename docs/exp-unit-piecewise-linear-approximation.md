# Exponential Unit (`exp_unit`) — Piecewise-Linear Approximation of eˣ

## Overview

`exp_unit` computes an IEEE-754 single-precision (FP32) approximation of
`e^x` in hardware using a **16-segment piecewise-linear (secant) model**.
Instead of implementing a Taylor series, CORDIC, or a table of high-order
polynomial coefficients, the design divides the supported input domain
`x ∈ [-4, 4]` into 16 equal sub-intervals of width `0.5` and, within each
sub-interval, approximates `eˣ` with a single straight line:

```
e^x ≈ a_i · x + b_i        for x in region i
```

`a_i` and `b_i` are pre-computed constants stored in a lookup table
(`exp_lut`), and the line is evaluated at runtime with one FP32 multiply
and one FP32 add. This trades a small, bounded amount of accuracy for a
very simple, fully combinational datapath (region select → LUT read →
multiply → add).

---

## 1. Mathematical Method

### 1.1 Segment definition

The domain is split into 16 regions of width 0.5:

```
region i covers  x ∈ [ -4 + 0.5·i ,  -4 + 0.5·(i+1) ),   i = 0 … 15
```

### 1.2 Coefficient derivation (secant / two-point interpolation)

For each region `i` with boundaries `x_lo` and `x_hi`, the line is chosen
to pass **exactly** through the true function value at both endpoints
(a secant line, not a least-squares or Taylor fit):

```
a_i = ( e^(x_hi) − e^(x_lo) ) / ( x_hi − x_lo )
b_i =   e^(x_lo)  −  a_i · x_lo
```

This guarantees the approximation is **exact at every region boundary**
(error = 0% at `x_lo` and `x_hi`) and reaches its **maximum error at the
midpoint** of each segment, where the convexity of `eˣ` causes the secant
line to sit above the true curve. Because the segments are only 0.5 wide,
that worst-case error stays small everywhere in `[-4, 4]`.

### 1.3 Region coefficient table

`a` and `b` below are shown as decimal values for reference; the RTL
stores them as FP32 hex literals (see `exp_lut.v`).

| Region | x range | a (slope) | b (intercept) | a (hex) | b (hex) |
|:--:|:--|--:|--:|:--|:--|
| 0  | [-4.0, -3.5) | 0.023763 | 0.113370 | `0x3CC2ABA6` | `0x3DE82E51` |
| 1  | [-3.5, -3.0) | 0.039179 | 0.167325 | `0x3D207A8C` | `0x3E2B574B` |
| 2  | [-3.0, -2.5) | 0.064596 | 0.243575 | `0x3D844AD6` | `0x3E796BA2` |
| 3  | [-2.5, -2.0) | 0.106501 | 0.348336 | `0x3DDA1CF8` | `0x3EB25927` |
| 4  | [-2.0, -1.5) | 0.175590 | 0.486515 | `0x3E33CDCD` | `0x3EF91877` |
| 5  | [-1.5, -1.0) | 0.289499 | 0.657378 | `0x3E943928` | `0x3F2849ED` |
| 6  | [-1.0, -0.5) | 0.477302 | 0.845182 | `0x3EF460FC` | `0x3F585DD7` |
| 7  | [-0.5,  0.0) | 0.786939 | 1.000000 | `0x3F4974D0` | `0x3F800000` |
| 8  | [ 0.0,  0.5) | 1.297443 | 1.000000 | `0x3FA61299` | `0x3F800000` |
| 9  | [ 0.5,  1.0) | 2.139121 | 0.579161 | `0x4008E75C` | `0x3F1443E0` |
| 10 | [ 1.0,  1.5) | 3.526814 | -0.808533 | `0x4061B754` | `0xBF4EFBFF` |
| 11 | [ 1.5,  2.0) | 5.814734 | -4.240412 | `0x40BA124D` | `0xC087B175` |
| 12 | [ 2.0,  2.5) | 9.586876 | -11.784696 | `0x411963D8` | `0xC13C8E1D` |
| 13 | [ 2.5,  3.0) | 15.806086 | -27.332722 | `0x417CE5BA` | `0xC1DAA96A` |
| 14 | [ 3.0,  3.5) | 26.059830 | -58.093952 | `0x41D07A88` | `0xC2686035` |
| 15 | [ 3.5,  4.0] | 42.965397 | -117.263435 | `0x422BDC91` | `0xC2EA86E1` |

Note the continuity at `x = 0`: region 7 and region 8 both give `b = 1.0`,
matching `e⁰ = 1`.

---

## 2. Hardware Architecture

### 2.1 Block diagram

```
                 x (FP32)
                    │
                    ▼
         ┌─────────────────────┐
         │   region_detector    │   4-bit region index (0–15)
         └─────────┬────────────┘
                    │ region
                    ▼
         ┌─────────────────────┐
         │       exp_lut        │   combinational ROM / case-mux
         │  region → (a, b)     │
         └───────┬─────┬───────┘
                 │ a   │ b
                 ▼     │
       ┌──────────────┐│
   x ─▶│ fp32_multiplier││   ax = a * x
       └──────┬───────┘│
              │ ax      │
              ▼         ▼
          ┌───────────────┐
          │   fp32_adder   │   exp_out = ax + b
          └───────┬────────┘
                   ▼
               exp_out (FP32 ≈ eˣ)
```

### 2.2 Pipeline stages (as wired in `exp_unit.v`)

1. **Region Detector** (`region_detector`, referenced but not shown in
   this doc set) — classifies the FP32 input `x` into one of 16 regions
   by comparing it against the region boundaries.
2. **Exponential LUT** (`exp_lut.v`) — a purely combinational `case`
   statement that maps the 4-bit `region` index to its FP32 coefficients
   `a` and `b`.
3. **FP32 Multiply** (`fp32_multiplier.v`) — computes `ax = a * x` using
   standard unpack → multiply mantissas → sum exponents → normalize →
   pack.
4. **FP32 Add** (`fp32_adder.v`) — computes `exp_out = ax + b`, handling
   exponent alignment, mantissa add/subtract based on sign, and
   post-add normalization (including the subtraction-side leading-zero
   normalization loop for cancellation cases).

The whole unit is **combinational** (no clock): `exp_out` settles some
propagation delay after `x` changes.

### 2.3 Module reference

| Module | File | Role |
|---|---|---|
| `exp_unit` | `exp_unit.v` | Top-level: wires region detector → LUT → multiplier → adder |
| `exp_lut` | `exp_lut.v` | 16-entry ROM of `(a, b)` FP32 secant-line coefficients |
| `fp32_multiplier` | `fp32_multiplier.v` | Combinational IEEE-754 FP32 multiplier |
| `fp32_adder` | `fp32_adder.v` | Combinational IEEE-754 FP32 adder/subtractor |
| `exp_accumulator` | `exp_accumulator.v` | Clocked helper that sums up to 4 `exp_unit` outputs (e.g. for a softmax-style reduction) and stores each term in a small register file |
| `reciprocal_unit` | `reciprocal_unit.v` | Standalone FP32 reciprocal (`1/x`) unit; not currently wired into `exp_unit`, but usable alongside it (e.g. to derive `e^-x` from `e^x`, or for softmax normalization) |

### 2.4 Top-level interface

```verilog
module exp_unit (
    input  wire [31:0] x,        // FP32 input, domain [-4, 4]
    output wire [31:0] exp_out   // FP32 approximation of e^x
);
```

### 2.5 Accumulator interface (optional downstream stage)

`exp_accumulator` is a clocked FSM-like block that can sum a stream of
up to 4 `exp_unit` results (`exp_in`) — useful for building blocks like
softmax denominators — while also caching each individual term for later
readback via `read_addr`.

```verilog
module exp_accumulator (
    input        clk,
    input        rst,
    input        start,       // begin a new accumulation (clears sum)
    input [31:0] exp_in,      // one exp(x) term, FP32
    input        exp_valid,   // exp_in is valid this cycle
    input  [1:0] read_addr,   // index into the 4-entry term cache
    output reg   done,        // asserted after the 4th term is accepted
    output reg [31:0] sum,    // running FP32 sum
    output [31:0] exp_out     // cached term at read_addr
);
```

---

## 3. Worked Example

For `x = 1.0` (region 9, `[0.5, 1.0)`)... actually `x = 1.0` falls exactly
on the boundary and is handled by region 10's convention `[1.0, 1.5)`:

```
a  = 3.526814
b  = -0.808533
e^1 ≈ a·1.0 + b = 3.526814 - 0.808533 = 2.718281   (true e ≈ 2.718282)
```

Relative error ≈ 0.00003% at this boundary point, consistent with the
secant method being exact at region endpoints.

For a **midpoint** case, `x = 0.25` (region 8, `[0.0, 0.5)`):

```
a = 1.297443, b = 1.0
e^0.25 ≈ 1.297443 · 0.25 + 1.0 = 1.324361   (true e^0.25 ≈ 1.284025)
```

Relative error ≈ 3.1% — this is close to the worst-case error for the
widest/steepest segments near the edges of the domain; segments closer to
`x = 0` are flatter and have smaller absolute midpoint error.

---

## 4. Verification

`exp_unit_phase6b_tb.v` is a self-checking testbench that:

1. Converts the DUT's FP32 output back to a Verilog `real` (`fp32_to_real`).
2. Computes relative error against a double-precision expected value.
3. Applies a **0.5% relative-error tolerance** (`error <= 0.005`) as the
   pass/fail criterion.
4. Sweeps representative points across the domain: `x = -2, -1, 0, 1, 2,
   3, 4, 5, 6, 7, 8` (note the testbench exercises inputs beyond the
   nominal `[-4, 4]` LUT range up to `x = 8`, which will fall through to
   the `default` case of `exp_lut` — `a = b = 0` — for any region index
   the detector doesn't recognize; see **Limitations** below).
5. Reports a pass/fail count and an overall `PASS`/`FAIL` summary.

To run it in a standard open-source flow:

```bash
iverilog -o exp_unit_tb.out \
    exp_unit.v exp_lut.v fp32_multiplier.v fp32_adder.v \
    exp_unit_phase6b_tb.v
vvp exp_unit_tb.out
```

---

## 5. Limitations & Future Work

- **Domain**: coefficients are only defined for `x ∈ [-4, 4]`. Inputs
  outside this range depend entirely on how `region_detector` classifies
  them; anything that maps to an undefined region hits `exp_lut`'s
  `default` case and returns `0`, not a saturated/clamped value.
- **Error bound**: worst-case relative error is bounded by segment width
  and the local curvature of `eˣ`; it is largest at segment midpoints and
  grows in absolute (though not necessarily relative) terms toward the
  edges of the domain, where `eˣ` is steepest.
- **No rounding/subnormal handling**: `fp32_multiplier` / `fp32_adder`
  implement round-to-nearest-even implicitly via truncation of the
  product/sum bits rather than a dedicated rounding stage, and do not
  special-case subnormals, infinities, or NaNs.
- **`reciprocal_unit` is not yet integrated** into `exp_unit`; it is a
  natural candidate for deriving `e^-x = 1 / e^x` or for building a
  softmax unit on top of `exp_unit` + `exp_accumulator`.
- **Finer segmentation** (more than 16 regions, or non-uniform segment
  widths concentrated where `eˣ` curves most) would tighten the error
  bound at the cost of a larger LUT and wider region index.

---

## 6. File Index

| File | Description |
|---|---|
| `exp_unit.v` | Top-level piecewise-linear `e^x` unit |
| `exp_lut.v` | 16-region coefficient ROM |
| `exp_accumulator.v` | Clocked accumulator/cache for streams of `exp_unit` outputs |
| `fp32_multiplier.v` | FP32 multiplier |
| `fp32_adder.v` | FP32 adder/subtractor |
| `reciprocal_unit.v` | Standalone FP32 reciprocal unit (companion block) |
| `exp_unit_phase6b_tb.v` | Self-checking testbench (0.5% tolerance) |
