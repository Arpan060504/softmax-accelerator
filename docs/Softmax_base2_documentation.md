# `softmax_base2` — Base-2 Exponential Softmax Accelerator
## Full RTL & Verification Documentation

---

## 1. Overview

`softmax_base2` is a fully combinational/pipelined-FSM hardware implementation of the
**Softmax** function over `N = 4` IEEE-754 single-precision (FP32) inputs:

```
                exp(x_i)
softmax(x_i) = -----------------------
                Σ_j exp(x_j)   for j = 0..N-1
```

Rather than implementing `exp()` with a CORDIC engine, a Taylor series, or a large
direct LUT spanning the whole input range, this design uses the classic **base-2
exponential decomposition** trick used in software math libraries (e.g. `expf()` in
glibc) to shrink the exponential function down to a tiny piecewise-linear LUT over a
narrow range, plus a free "multiply by power of two" step implemented purely by integer
addition on the FP32 exponent field.

### 1.1 The core identity

```
exp(y) = exp(k*ln(2) + r) = 2^k * exp(r),   where y = k*ln(2) + r,  0 <= r < ln(2)
```

This means:
1. Reduce `y` to an integer `k` and a small remainder `r` in `[0, ln 2)`.
2. Approximate `exp(r)` with a cheap piecewise-linear LUT (since `r` is now confined to
   a narrow, fixed range instead of the full input range).
3. Multiply the LUT result by `2^k` — which, for FP32, is **not a real multiplication**
   at all; it's simply adding `k` to the number's stored exponent field.

This lets a full softmax pipeline be built almost entirely from an FP32 adder, an FP32
multiplier, and small LUTs — no iterative CORDIC rotations, no large `exp()` LUT.

### 1.2 Numerical stability: max-subtraction

Before any exponentiation, the design performs the standard numerically-stable softmax
rewrite:

```
softmax(x_i) = softmax(x_i - max(x))
```

Subtracting the maximum guarantees every exponent argument is `<= 0`, so `exp()` never
overflows, and the largest term in the sum is always exactly `exp(0) = 1`.

---

## 2. End-to-End Algorithm

```
Step 0:  y_i      = x_i - max(x0, x1, x2, x3)              (exp_range_reducer + max_finder)
Step 1:  y_i       = k_i * ln(2) + r_i,  0 <= r_i < ln(2)   (exp_kr_reducer)
Step 2:  exp(r_i) ≈ a*r_i + b   (piecewise-linear, 8 regions)  (exp_r_lut)
Step 3:  exp(y_i) = 2^(k_i) * exp(r_i)   (exponent-field add only)  (exp_power_of_two)
Step 4:  sum      = Σ exp(y_i)                               (softmax_exp_accumulator)
Step 5:  recip    = 1 / sum   (Newton-Raphson, LUT-seeded)    (softmax_reciprocal / reciprocal_unit)
Step 6:  softmax_i = exp(y_i) * recip                         (softmax_normalizer)
```

All FP32 arithmetic building blocks (`fp32_adder`, `fp32_multiplier`) are shared and
reused throughout the pipeline.

---

## 3. Top-Level Module: `softmax_base2`

```verilog
module softmax_base2 #(
    parameter integer N = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    input  wire [31:0] x0, x1, x2, x3,

    output wire [31:0] softmax0, softmax1, softmax2, softmax3,
    output wire        done
);
```

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | System clock. |
| `rst` | in | 1 | Synchronous, active-high reset. |
| `start` | in | 1 | Pulse to launch a new softmax computation on the current `x0..x3`. |
| `x0..x3` | in | 32 each | FP32 input logits. |
| `softmax0..3` | out | 32 each | FP32 softmax probabilities, valid when `done = 1`. |
| `done` | out | 1 | Asserted once the accumulation FSM has consumed all `N` exponentials; stays high until the next `start`. |

**Parameter `N`:** Declared as a generic parameter (used by `softmax_exp_accumulator`),
but the top level's datapath (max-finder tree, `exp_kr_reducer`/`exp_r_lut`/
`exp_power_of_two` instances, and the FSM's `S_EXP0..S_EXP3` states) is **hardwired
for exactly 4 inputs**. Changing `N` alone does not generalize the design to other
input counts without also editing the top-level wiring and FSM.

### 3.1 Block Diagram

```
 x0 x1 x2 x3
   │  │  │  │
   ▼  ▼  ▼  ▼
┌─────────────────────┐
│  exp_range_reducer   │  y_i = x_i - max(x)     (uses max_finder x3, fp32_adder x4)
└─────────────────────┘
   │  │  │  │  (y0..y3)
   ▼  ▼  ▼  ▼
┌─────────────────────┐
│   exp_kr_reducer x4  │  y_i = k_i*ln2 + r_i    (uses fp32_multiplier, fp32_adder)
└─────────────────────┘
   │k0..k3   │r0..r3
   │         ▼
   │  ┌─────────────────┐
   │  │  exp_r_lut x4    │  exp(r_i) ≈ a*r_i + b  (8-region piecewise-linear)
   │  └─────────────────┘
   │         │ exp_r0..3
   ▼         ▼
┌─────────────────────┐
│ exp_power_of_two x4  │  exp(y_i) = 2^k_i * exp(r_i)   (exponent-field add only)
└─────────────────────┘
   │ exp0..exp3
   ▼
┌─────────────────────────────┐        ┌────────────┐
│ softmax_exp_accumulator     │──sum──▶│ softmax_    │──reciprocal──┐
│ (FSM: S_EXP0→1→2→3→DONE)    │        │ reciprocal  │              │
└─────────────────────────────┘        └────────────┘              │
   │ exp0..exp3 (combinational, held externally)                    │
   ▼                                                                 ▼
┌───────────────────────────────────────────────────────────────────────┐
│                        softmax_normalizer                              │
│      softmax_i = exp_i * reciprocal   (fp32_multiplier x4)             │
└───────────────────────────────────────────────────────────────────────┘
   │
   ▼
softmax0..softmax3
```

### 3.2 Accumulation FSM

```verilog
localparam [2:0]
    S_IDLE = 3'd0, S_EXP0 = 3'd1, S_EXP1 = 3'd2,
    S_EXP2 = 3'd3, S_EXP3 = 3'd4, S_DONE = 3'd5;
```

| State | Behavior |
|---|---|
| `S_IDLE` | Waits for `start`. |
| `S_EXP0` | Feeds `exp0` into the accumulator (`exp_valid = 1`). |
| `S_EXP1` | Feeds `exp1`. |
| `S_EXP2` | Feeds `exp2`. |
| `S_EXP3` | Feeds `exp3`. |
| `S_DONE` | Holds; a new `start` restarts at `S_EXP0`. |

Since `exp0..exp3` are all computed **combinationally** in parallel (from `x0..x3`),
the FSM's only job is to *time-multiplex* these four already-available values into the
single-input `softmax_exp_accumulator`, one per clock cycle. This trades hardware area
(one shared FP32 adder/accumulator instead of 4) for a small fixed latency (4 cycles to
walk through `S_EXP0..S_EXP3`, plus 1–2 cycles of `start`/FSM setup — 5 cycles observed
in simulation, as reflected in the testbench log: `DONE : 1 after 5 cycles`).

`done = exp_done`, forwarded directly from `softmax_exp_accumulator`.

---

## 4. Datapath Modules

### 4.1 `max_finder` — FP32 Maximum of Two Values

```verilog
module max_finder (input [31:0] a, b, output reg [31:0] max);
```

Implements IEEE-754 comparison **without floating-point subtraction**, by directly
comparing sign, then exponent, then fraction fields:

1. **Different signs** → the positive operand wins.
2. **Both positive** → larger exponent wins; on a tie, larger fraction wins.
3. **Both negative** → *smaller* exponent wins (since more negative exponent = smaller
   magnitude = larger, less-negative value); on a tie, *smaller* fraction wins (same
   reasoning — for negative numbers, larger stored fraction means more negative value).

This comparator is correct for all normal, zero, and subnormal FP32 values, since FP32's
bit layout is designed so that for same-signed numbers, unsigned integer comparison of
the exponent+fraction bits matches numeric comparison.

### 4.2 `exp_range_reducer` — Max-Subtraction for Numerical Stability

```verilog
module exp_range_reducer (input [31:0] x0,x1,x2,x3, output [31:0] y0,y1,y2,y3);
```

- Computes `max(x0,x1,x2,x3)` via a 3-instance `max_finder` reduction tree
  (`max1 = max(x0,x1)`, `max2 = max(x2,x3)`, `max = max(max2,max1)`).
- Negates `max` by flipping its sign bit (`neg_max = {~max[31], max[30:0]}`) — cheap
  FP32 negation, avoiding a dedicated negate/subtract circuit.
- Computes each `y_i = x_i + (-max) = x_i - max` using four parallel `fp32_adder`
  instances.

Output: `y0..y3`, all `<= 0`, with at least one `y_i == 0` (the input that was the max).

### 4.3 `fp32_adder` — IEEE-754 Single-Precision Adder/Subtractor

```verilog
module fp32_adder (input [31:0] a, b, output reg [31:0] result);
```

Standard textbook floating-point add/subtract datapath:

1. **Zero bypass:** if either operand is exact zero, the other operand passes straight
   through (avoids the general path entirely, and correctly handles `-0`-style edge
   cases since only `[30:0]` is checked, allowing signed zero to still bypass).
2. **Mantissa alignment:** the operand with the smaller exponent has its (implicit-1)
   24-bit mantissa right-shifted by the exponent difference; shifts `>= 24` clamp the
   aligned mantissa to zero (since it's insignificant — this is the source of the
   design's ULP-level rounding error, discussed in §9).
3. **Add or subtract:** if signs match, mantissas add (25-bit result to catch carry-out);
   if signs differ, the smaller-magnitude mantissa is subtracted from the larger, with
   the result taking the sign of the larger-magnitude operand.
4. **Normalization:**
   - **Addition path:** a carry into bit 24 means the result needs a 1-bit right shift
     and exponent increment.
   - **Subtraction path:** a 24-bit priority encoder (`casez`) finds the number of
     leading zeros in the raw subtraction result and left-shifts / decrements the
     exponent accordingly. If the adjusted exponent underflows to `<= 0`, the result
     flushes to zero.
   - An exact-zero mantissa result (from subtracting two equal-magnitude,
     opposite-sign-adjusted values) is special-cased to `32'h00000000`.

**Note:** this adder does **not** implement round-to-nearest-even; it truncates during
alignment shifting and normalization. This is a primary contributor to the small
(<0.1%) numerical error seen in the verification results.

### 4.4 `fp32_multiplier` — IEEE-754 Single-Precision Multiplier

```verilog
module fp32_multiplier (input [31:0] a, b, output reg [31:0] result);
```

1. **Zero bypass:** any operand being zero *or* having a zero exponent field (i.e. a
   subnormal, which this design treats as effectively zero rather than handling
   subnormal arithmetic) produces a `0` result.
2. **Mantissa multiply:** `24 x 24 -> 48`-bit unsigned multiply of the two
   implicit-1 mantissas.
3. **Exponent combine:** `exp_a + exp_b - 127` (removing the double-counted bias),
   computed in a 10-bit signed register to detect over/underflow safely.
4. **Normalization:** if the 48-bit product's top bit (`[47]`) is set, the product spans
   one extra bit, so the exponent is incremented and bits `[46:24]` are taken as the
   fraction; otherwise bits `[45:23]` are taken directly.
5. **Range clamp:** `exp_calc <= 0` flushes to zero; `exp_calc >= 255` saturates to
   `{sign, 8'hFF, 0}` (infinity). Otherwise the normal FP32 result is packed.

Like the adder, this multiplier **truncates** rather than rounds the 48-bit product down
to 23 fraction bits.

### 4.5 `exp_kr_reducer` — Range Reduction (`y = k·ln2 + r`)

```verilog
module exp_kr_reducer (input [31:0] y, output signed [7:0] k, output [31:0] r);
```

Implements `k = floor(y / ln 2)` and `r = y - k*ln2`, using only the FP32 adder/
multiplier plus small integer-conversion helper functions — no floating-point division
is used.

1. **`q_fp = y * (1/ln2)`** via `fp32_multiplier`, using the constant
   `INV_LN2 = 0x3FB8AA3B` (`1/ln(2) ≈ 1.4426950`).
2. **Truncate towards zero:** `fp32_to_integer()` extracts the integer part of a
   non-negative FP32 magnitude by shifting the implicit-1 mantissa according to the
   unbiased exponent (`shift = exponent - 127`); values with `exponent < 127` (i.e.
   `|value| < 1`) truncate to `0`.
3. **Convert truncation to floor:** IEEE-754 truncation-towards-zero of a *negative*
   number is equivalent to `ceil`, not `floor`. Since softmax inputs `y` are always
   `<= 0` (after max-subtraction) `q_fp` is always `<= 0`, so the module must correct
   for this:
   - `has_fraction()` checks whether the truncated-away bits of `q_fp` were non-zero
     (i.e. whether `q_fp` had a genuine fractional part).
   - If `q_fp` is negative **and** has a fractional part, `k = q_trunc - 1` (converts
     ceil to floor).
   - If `q_fp` is negative and exactly integral, or if `q_fp` is `0`/non-negative,
     `k = q_trunc` directly (truncation already equals floor in these cases).
4. **Compute residual:** `k_fp = integer_to_fp32(k)`, then `k_ln2 = k_fp * LN2`
   (`LN2 = 0x3F317218 ≈ 0.6931472`), then `r = y - k_ln2` via `fp32_adder` with a
   sign-flipped `k_ln2`.
5. **Roundoff guard:** because the FP32 adder/multiplier truncate rather than round,
   `r` can occasionally compute as a tiny negative value instead of exactly `0` due to
   accumulated rounding error. The module clamps any negative `r_computed` to exactly
   `32'h00000000`, guaranteeing `r` is always in the valid `[0, ln2)` LUT input range.

**Important limitation — `integer_to_fp32` range:** this helper function is a **fixed
case-statement LUT covering only `k ∈ {0, -1, -2, ..., -12}`**; any other integer value
(including any positive `k`) falls through to the `default: 32'h00000000` case. This
hardcodes the assumption that softmax inputs, after max-subtraction, never require a
downshift larger than `2^-12` — consistent with the design comment `y >= approximately
-6` and the intended Softmax input dynamic range, but it means this module is **not a
general-purpose range reducer**; it would silently produce an incorrect `k_ln2 = 0` (and
therefore incorrect `r = y`) for `y` more negative than roughly `-12*ln2 ≈ -8.3`, or for
any positive `y` (which should not occur post max-subtraction, since `y <= 0` always).

### 4.6 `exp_r_lut` — Piecewise-Linear Approximation of `exp(r)` for `r ∈ [0, 0.7)`

```verilog
module exp_r_lut (input [31:0] r, output [31:0] exp_r);
```

Approximates `exp(r) ≈ a·r + b` using **8 fixed linear segments**, each spanning a
region of width `h = 0.0875` (so that `8 * 0.0875 = 0.7`, comfortably covering the full
`[0, ln2) ≈ [0, 0.6931)` range produced by `exp_kr_reducer`):

| Region | Range | `a` (slope) | `b` (intercept) |
|---|---|---|---|
| 0 | [0.0000, 0.0875) | 1.04505328 | 1.00000000 |
| 1 | [0.0875, 0.1750) | 1.14061778 | 0.99163810 |
| 2 | [0.1750, 0.2625) | 1.24491666 | 0.97338580 |
| 3 | [0.2625, 0.3500) | 1.35875569 | 0.94350306 |
| 4 | [0.3500, 0.4375) | 1.48300232 | 0.90001674 |
| 5 | [0.4375, 0.5250) | 1.61861810 | 0.84068483 |
| 6 | [0.5250, 0.6125) | 1.76660865 | 0.76298980 |
| 7 | [0.6125, ~0.7000] | 1.92817273 | 0.66403180 |

Region selection is a simple priority `if / else if` chain comparing `r` against 7
boundary constants. The selected `(a, b)` pair feeds one shared `fp32_multiplier`
(`a*r`) followed by one shared `fp32_adder` (`+ b`) to produce `exp(r)`.

An explicit **exact-zero bypass** (`r == 0 → exp_r = 1.0` i.e. `0x3F800000`) sidesteps
any small residual error the linear fit would otherwise introduce at the boundary
`exp(0) = 1` exactly.

This is the module primarily responsible for the ~0.05–0.1% relative error observed in
the final softmax outputs (see §9), since a piecewise-linear fit necessarily has some
curvature-fitting error inside each region, maximized near each segment's midpoint.

### 4.7 `exp_power_of_two` — `2^k` Scaling via Exponent-Field Arithmetic

```verilog
module exp_power_of_two (input [31:0] exp_r, input signed [7:0] k, output reg [31:0] exp_out);
```

This is the module documented in detail in the companion
`exp_power_of_two_documentation.md`. In brief: because `exp(r)` is always a normalized,
positive FP32 value, multiplying by `2^k` is done by adding `k` directly to `exp_r`'s
biased exponent field — no real multiplication hardware is needed. It handles:

- **Zero** input → zero output.
- **Inf/NaN** (`exponent == 0xFF`) → pass-through unchanged.
- **Subnormal** (`exponent == 0x00`, value non-zero) → pass-through unchanged (not
  expected in this pipeline since `exp(r) >= 1.0` always).
- **Underflow** (`new_exponent <= 0`) → flush to `+0.0`.
- **Overflow** (`new_exponent >= 255`) → saturate to `+Infinity`.
- **Normal case** → `{sign, new_exponent[7:0], fraction}`.

Since this design's `y_i <= 0` always (post max-subtraction) and therefore `k_i <= 0`
always, the overflow path is not expected to be exercised in normal softmax operation
(it exists as a defensive/general-purpose safeguard).

---

## 5. Accumulation: `softmax_exp_accumulator`

```verilog
module softmax_exp_accumulator #(parameter integer N = 4) (
    input clk, rst, start,
    input [31:0] exp_in, input exp_valid,
    input [$clog2(N)-1:0] read_addr, output [31:0] exp_out,
    output reg [31:0] sum, output reg done
);
```

A small sequential accumulator with an internal memory array (`exp_mem[0:N-1]`):

- On `rst` or `start`: `sum`, `count` reset to `0`; `done` deasserted.
- On each cycle where `exp_valid = 1`: the incoming `exp_in` is stored into
  `exp_mem[count]` **and** added into `sum` (via a shared `fp32_adder`) in the same
  cycle.
- When `count` reaches `N-1`, `done` is asserted on that same cycle (the last valid
  sample is still correctly folded into `sum` before/while `done` goes high).
- Otherwise `count` increments to accept the next sample.

**`exp_out` / `read_addr` port:** this accumulator exposes a combinational read port
into its internal `exp_mem` array (`exp_out = exp_mem[read_addr]`), intended to let a
consumer read back individual stored exponentials by index. In the current
`softmax_base2` top level, this port is **wired to a constant `read_addr = 2'b00`** and
its output is left completely unused (`exp_out_unused`) — the actual `exp0..exp3`
values consumed by `softmax_normalizer` come directly from the combinational datapath,
not from this memory. This makes `exp_mem`/`exp_out` a **vestigial/debug interface** in
the current top-level wiring; it consumes extra RAM but contributes nothing to the
functional output.

---

## 6. Reciprocal & Final Normalization

### 6.1 `softmax_reciprocal`

A thin wrapper: `reciprocal = 1 / sum`, delegated entirely to `reciprocal_unit`.

### 6.2 `reciprocal_unit` — Newton–Raphson FP32 Reciprocal

```verilog
module reciprocal_unit (input [31:0] x, output [31:0] reciprocal);
```

Classic hardware reciprocal technique: **LUT-seeded one-iteration Newton-Raphson**.

1. **Unpack** `x = M * 2^e` (mantissa `M ∈ [1,2)`, unbiased exponent `e`).
2. **Seed lookup:** the top 4 bits of the fraction (`fraction[22:19]`) index a 16-entry
   `reciprocal_lut`, giving an initial estimate `y0 ≈ 1/M` accurate to roughly 4 bits.
3. **One Newton-Raphson refinement step:**
   ```
   y1 = y0 * (2 - M*y0)
   ```
   implemented as: `mul1_out = M*y0` → negate → `correction = 2 - M*y0` (via
   `fp32_adder` with the constant `2.0 = 0x40000000`) → `y1 = y0 * correction` (via
   `fp32_multiplier`). Each Newton-Raphson iteration roughly **doubles** the number of
   correct bits, so one iteration on a ~4-bit-accurate seed yields on the order of 8
   correct mantissa bits — noticeably less than FP32's full 23-bit mantissa, which is a
   direct contributor to the reciprocal-stage error discussed in §9.
4. **Exponent reconstruction:** since `1/x = (1/M) * 2^(-e)`, and `y1` itself carries
   its own floating-point exponent `e_y1` representing `1/M`'s scale, the final unbiased
   exponent is `e_final = e_y1 - e`, re-biased by `+127` for storage.
5. **Special cases:** `x == 0` → `+Infinity`/`-Infinity` (sign preserved); exponent
   overflow/underflow on the final result saturate to `Infinity`/`0` respectively
   (sign preserved in both cases, i.e. this path handles a negative `x` defensively,
   even though `sum` in this pipeline is always positive).

### 6.3 `reciprocal_lut` — 16-Entry Seed Table

A simple `case` statement mapping a 4-bit index (`fraction[22:19]`, i.e. the mantissa
sub-range `[1.0, 2.0)` split into 16 equal sub-intervals) to a pre-computed FP32
reciprocal estimate (e.g. index `0 → 0.969697 ≈ 1/1.03125`, down to index
`15 → 0.507937 ≈ 1/1.96875`). Any index outside `0–15` (not reachable given a 4-bit
input) defaults to `0`.

### 6.4 `softmax_normalizer` — Final Division-by-Multiplication

```verilog
module softmax_normalizer (input [31:0] exp0,exp1,exp2,exp3, input [31:0] reciprocal,
                            output [31:0] softmax0,softmax1,softmax2,softmax3);
```

Since `reciprocal = 1/sum`, division is turned into multiplication:
`softmax_i = exp_i * reciprocal`, computed by four parallel `fp32_multiplier`
instances — the final combinational stage of the pipeline.

---

## 7. Present but Unused Module: `region_detector`

```verilog
module region_detector (input [31:0] x, output reg [3:0] region);
```

This module classifies an FP32 input into **16 regions** across `[-4.0, 4.0]` (width
`0.5` each, clamped at both ends), using a clever **monotonic bit-reordering trick**
(`ordered_x = x ^ 0x80000000` for positive numbers, `ordered_x = ~x` for negative
numbers) that lets ordinary unsigned integer comparison correctly order IEEE-754
floats, including across the positive/negative boundary — avoiding a full floating-point
comparator entirely.

**This module is not instantiated anywhere in the `softmax_base2` hierarchy** as
provided. `exp_r_lut` performs its own independent 8-region classification with a
simple inline `if/else if` chain over `[0, 0.7)`, rather than using `region_detector`.
`region_detector`'s 16-region, `±4.0`-range design looks suited to a *different*,
wider-range exponential LUT variant (e.g. one that skips the `k·ln2 + r` decomposition
in favor of directly bucketing the whole range reduction output). It is included in the
file set but currently dead code from the top level's perspective — worth flagging in
case it was meant to replace part of `exp_kr_reducer`/`exp_r_lut` in a future revision,
or is simply left over from an earlier design iteration.

---

## 8. Testbench: `softmax_base2_tb`

### 8.1 Structure

- **Reference model:** for each test vector, the testbench computes a **software
  reference softmax** using Verilog's built-in real-number `$exp()` function, applying
  the same max-subtraction the DUT is expected to perform (`e_i = $exp(r_i - max)`),
  then normalizing (`expected_i = e_i / Σe`). This is a *behavioral* golden reference,
  not a bit-exact IEEE-754 reference — it uses full double-precision real math.
- **`fp32_to_real`:** converts a DUT FP32 output/input bit pattern into a Verilog `real`
  for comparison and display (zero, normal-number cases handled; Inf/NaN mapped to
  `0.0` as a simplification since they are not expected to occur in this test suite).
- **`check_output` task:** computes `error_percent = |actual - expected| / |expected| *
  100`, comparing it against `MAX_ERROR_PERCENT = 0.5` (i.e. a **0.5% relative error
  tolerance** per individual softmax output). A PASS/FAIL is logged per output.
- **Sum check:** verifies `|Σ softmax_i - 1.0| <= SUM_TOLERANCE (0.01)`, i.e. the four
  outputs must sum to `1.0 ± 0.01` (1% absolute tolerance), a basic sanity/conservation
  check independent of individual-element accuracy.
- **Latency check:** verifies `done` asserts within `<= 6` clock cycles of `start`
  (accounting for FSM state-transition timing).
- **`run_test` task:** drives `x0..x3` on a `negedge clk`, pulses `start` for one cycle,
  waits (polling on `posedge clk`, timeout at 20 cycles) for `done`, then runs all of the
  above checks and prints a detailed per-test report.

### 8.2 Test Plan

**30 directed test vectors** are run, covering:
- Degenerate/uniform inputs (all-zero, all-equal → softmax = 0.25 each).
- One-hot inputs (`[1,0,0,0]`, `[0,1,0,0]`, etc.) exercising each output position as the
  "peak."
- Increasing/decreasing integer sequences at various offsets (`[2,1,0,-1]`,
  `[3,2,1,0]`, `[4,3,2,1]`, and their negated/shifted counterparts) — testing
  translation-invariance of softmax (`softmax(x) == softmax(x + c)`).
- Wide dynamic-range inputs (`[0,-3,-6,-8]`, `[-8,-6,-4,0]`) stressing the `exp_kr_reducer`
  range-reduction limits discussed in §4.5.
- Fine fractional-step inputs (`[0,-0.1,-0.2,-0.3]`, `[0,-0.25,-0.5,-0.75]`,
  `[-0.5,-0.5,-1,-1]`) exercising `exp_r_lut`'s piecewise regions at sub-integer
  granularity.

### 8.3 How to Run

```bash
iverilog -o sim.out \
    fp32_adder.v fp32_multiplier.v max_finder.v \
    exp_range_reducer.v exp_kr_reducer.v exp_r_lut.v exp_power_of_two.v \
    softmax_exp_accumulator.v reciprocal_lut.v reciprocal_unit.v softmax_reciprocal.v \
    softmax_normalizer.v softmax_base2.v softmax_base2_tb.v
vvp sim.out
```

(`region_detector.v` may be compiled alongside without effect, since it is unused by the
hierarchy; it is not required to run the testbench.)

---

## 9. Verification Results

### 9.1 Summary

| Metric | Value |
|---|---|
| Total test vectors | 30 |
| Failed checks | 0 |
| **Result** | **ALL TESTS PASSED** |
| Per-output error tolerance | 0.5% |
| **Minimum observed per-output error** (across all 30×4 = 120 checks) | **0.000371%** (Tests 25 & 29, `softmax1`) |
| **Maximum observed per-output error** (across all 30×4 = 120 checks) | **0.091833%** (Tests 1, 2, 11, 12 — the uniform-input cases) |
| Sum tolerance | ±0.01 (all observed sums within ±0.0009 of 1.0) |
| Observed latency | 5 cycles from `start` to `done`, every test (well under the 6-cycle check limit) |

### 9.2 Per-Test Results

Each test checks 4 individual softmax outputs; **Min Error** and **Max Error** below
are the smallest and largest of those 4 per-output relative errors for that test.

| Test | Input `[x0,x1,x2,x3]` | DUT Output `[s0,s1,s2,s3]` | Sum | Min Error | Max Error | Result |
|---|---|---|---|---|---|---|
| 1 | [0, 0, 0, 0] | [0.249770]×4 | 0.999082 | 0.0918% | 0.0918% | PASS |
| 2 | [1, 1, 1, 1] | [0.249770]×4 | 0.999082 | 0.0918% | 0.0918% | PASS |
| 3 | [1, 0, 0, 0] | [0.474935, 0.174882, 0.174882, 0.174882] | 0.999582 | 0.0026% | 0.0908% | PASS |
| 4 | [0, 1, 0, 0] | [0.174882, 0.474935, 0.174882, 0.174882] | 0.999582 | 0.0026% | 0.0908% | PASS |
| 5 | [0, 0, 1, 0] | [0.174882, 0.174882, 0.474935, 0.174882] | 0.999582 | 0.0026% | 0.0908% | PASS |
| 6 | [0, 0, 0, 1] | [0.174882, 0.174882, 0.174882, 0.474935] | 0.999582 | 0.0026% | 0.0908% | PASS |
| 7 | [2, 1, 0, -1] | [0.643602, 0.236989, 0.087129, 0.032070] | 0.999790 | 0.0173% | 0.0485% | PASS |
| 8 | [3, 2, 1, 0] | [0.643602, 0.236989, 0.087129, 0.032070] | 0.999790 | 0.0173% | 0.0485% | PASS |
| 9 | [0, -1, -2, -3] | [0.643602, 0.236989, 0.087129, 0.032070] | 0.999790 | 0.0173% | 0.0485% | PASS |
| 10 | [-1, -2, -3, -4] | [0.643602, 0.236989, 0.087129, 0.032070] | 0.999790 | 0.0173% | 0.0485% | PASS |
| 11 | [-2, -2, -2, -2] | [0.249770]×4 | 0.999082 | 0.0918% | 0.0918% | PASS |
| 12 | [-4, -4, -4, -4] | [0.249770]×4 | 0.999082 | 0.0918% | 0.0918% | PASS |
| 13 | [0, -0.5, -1, -1.5] | [0.454850, 0.276057, 0.167486, 0.101582] | 0.999975 | 0.0192% | 0.0485% | PASS |
| 14 | [0, -2, -4, -6] | [0.864914, 0.117090, 0.015851, 0.002146] | 1.000000 | 0.0047% | 0.0710% | PASS |
| 15 | [0, -3, -6, -8] | [0.949578, 0.047317, 0.002356, 0.000319] | 0.999570 | 0.0284% | 0.0473% | PASS |
| 16 | [-0.5, -0.5, -1, -1] | [0.311133, 0.311133, 0.188833, 0.188833] | 0.999932 | 0.0310% | 0.0331% | PASS |
| 17 | [-0.25, -0.5, -0.75, -1] | [0.349723, 0.272431, 0.212254, 0.165324] | 0.999731 | 0.0043% | 0.0598% | PASS |
| 18 | [-1, -1, 0, 0] | [0.134518, 0.134518, 0.365316, 0.365316] | 0.999668 | 0.0351% | 0.0583% | PASS |
| 19 | [4, 3, 2, 1] | [0.643602, 0.236989, 0.087129, 0.032070] | 0.999790 | 0.0173% | 0.0485% | PASS |
| 20 | [-4, -3, -2, -1] | [0.032070, 0.087129, 0.236989, 0.643602] | 0.999790 | 0.0173% | 0.0485% | PASS |
| 21 | [-6, -4, -2, 0] | [0.002146, 0.015851, 0.117090, 0.864914] | 1.000000 | 0.0047% | 0.0710% | PASS |
| 22 | [-8, -6, -4, 0] | [0.000329, 0.002429, 0.017945, 0.979201] | 0.999904 | 0.0108% | 0.0760% | PASS |
| 23 | [0.5, 0, -0.5, -1] | [0.454850, 0.276057, 0.167486, 0.101582] | 0.999975 | 0.0192% | 0.0485% | PASS |
| 24 | [2.5, 1.5, 0.5, -0.5] | [0.643602, 0.236989, 0.087129, 0.032070] | 0.999790 | 0.0173% | 0.0485% | PASS |
| 25 | [0, -0.1, -0.2, -0.3] | [0.288462, 0.261182, 0.236383, 0.213903] | 0.999929 | 0.0004% | 0.0655% | PASS |
| 26 | [0, -0.25, -0.5, -0.75] | [0.349723, 0.272431, 0.212254, 0.165324] | 0.999731 | 0.0043% | 0.0598% | PASS |
| 27 | [0, -1.25, -2.5, -3.75] | [0.718097, 0.205937, 0.058968, 0.016902] | 0.999904 | 0.0057% | 0.0632% | PASS |
| 28 | [3.5, 3, 2.5, 2] | [0.454850, 0.276057, 0.167486, 0.101582] | 0.999975 | 0.0192% | 0.0485% | PASS |
| 29 | [-0.1, -0.2, -0.3, -0.4] | [0.288462, 0.261182, 0.236383, 0.213903] | 0.999929 | 0.0004% | 0.0655% | PASS |
| 30 | [0.25, 0.25, -0.25, -0.25] | [0.311133, 0.311133, 0.188833, 0.188833] | 0.999932 | 0.0310% | 0.0331% | PASS |

**Overall across all 30 tests:** minimum per-output error observed = **0.000371%**
(Tests 25 & 29, `softmax1`); maximum per-output error observed = **0.091833%**
(Tests 1, 2, 11, 12 — the uniform-input, `1/N`-each cases).

*(Full per-output expected/actual/error figures are in the raw simulation log; the table
above summarizes each test's minimum and maximum per-output error.)*

### 9.3 Accuracy Analysis

- **Error is consistently small and bounded:** across all 30 tests, per-output relative
  error stayed in the **0.0004%–0.092%** range, far inside the 0.5% pass threshold, and
  the output sum stayed within **0.03%** of the ideal `1.0` in every test.
- **Translation invariance holds:** Tests 7–10, 19–20, and 24 all represent the same
  relative input pattern shifted by a constant offset, and all produce **bit-identical**
  DUT outputs (`0.643602, 0.236989, 0.087129, 0.032070`), confirming the max-subtraction
  stage correctly normalizes translation before exponentiation, exactly as intended.
- **Error sources, in order of expected contribution:**
  1. **`exp_r_lut` piecewise-linear fit error** — inherent to approximating a convex
     curve with straight-line segments; error is largest near each segment's midpoint
     and best at segment boundaries (where the fit was presumably anchored).
  2. **`fp32_adder`/`fp32_multiplier` truncation (no rounding)** — every FP32 op in the
     pipeline truncates rather than rounds, compounding a small systematic downward
     bias through the ~5–6 arithmetic stages each input passes through
     (multiply → add → multiply → LUT-mult → LUT-add → exponent-add → accumulate →
     reciprocal-multiply → normalize-multiply).
  3. **`reciprocal_unit`'s single Newton-Raphson iteration** — only one refinement pass
     is performed, yielding roughly half of FP32's full mantissa precision; a second
     iteration would substantially tighten this at the cost of one more
     multiply-add-multiply-multiply sequence.
- **No failures were triggered by the `exp_kr_reducer` k-range limitation (§4.5):** the
  most extreme test (`Test 22: [-8,-6,-4,0]`) produces a post-max-subtraction range of
  `[-8, 0]`, i.e. a worst-case `k` of `floor(-8/0.693) = -12`, which lands exactly at the
  edge of, but still within, the `integer_to_fp32` table's supported `{0..-12}` range.
  Any input requiring a `k` more negative than `-12` (e.g. inputs with a spread
  exceeding roughly `8.3` in the range-reduced domain) is **not covered by this test
  suite** and would silently mis-compute (see §4.5).

---

## 10. Known Limitations

1. **`exp_kr_reducer`'s `k` range is hardcoded to `{0, -1, ..., -12}`.** Any range-reduced
   input requiring a more negative `k` (post max-subtraction spread greater than
   ~`8.3`) will silently use `k_ln2 = 0`, corrupting the residual `r` and therefore the
   final result — with **no error flag or saturation**, this fails silently rather than
   clamping safely. This is the most significant latent risk in the current design.
2. **No IEEE-754 rounding (round-to-nearest-even):** both `fp32_adder` and
   `fp32_multiplier` truncate. This is the dominant source of the (still-small, <0.1%)
   systematic error seen throughout §9.3, and would compound further in a deeper
   pipeline (e.g. larger `N`, or chained softmax layers).
3. **Single Newton-Raphson iteration** in `reciprocal_unit` trades reciprocal precision
   for lower latency/area; sufficient to clear the 0.5% test tolerance here, but a
   tighter downstream requirement would need a second iteration.
4. **`softmax_exp_accumulator`'s `exp_out`/`read_addr` interface is unused/vestigial**
   in the current top-level wiring (§5) — it allocates an `N`-deep FP32 memory array
   that is written every cycle but never read by anything in `softmax_base2`.
5. **`softmax_base2`'s top-level datapath is hardwired for `N = 4`**, despite the `N`
   parameter existing; changing `N` alone (without also modifying `x0..x3`, the
   FSM's `S_EXP0..S_EXP3` states, and the per-input module instantiation) will not
   generalize the module to other input counts.
6. **`region_detector` is present in the file set but not used anywhere in the current
   hierarchy** (§7) — likely leftover or prepared-but-unwired scaffolding for an
   alternative/future exponential approximation strategy.
7. **Subnormal FP32 inputs are not correctly handled end-to-end.** `fp32_multiplier`
   treats any subnormal operand as zero; `exp_power_of_two` passes subnormals through
   unmodified rather than scaling them. These paths are consistent with the
   assumption that softmax inputs and intermediate exponentials never legitimately
   become subnormal, but they are not general-purpose IEEE-754-compliant behaviors.
8. **`exp_range_reducer`/`max_finder` assume no NaN inputs.** FP32 comparison logic in
   `max_finder` does not special-case NaN; an NaN input would propagate through the
   sign/exponent/fraction comparison as if it were an ordinary (very large-magnitude)
   number, producing an incorrect "max" silently rather than propagating NaN as IEEE-754
   would require.

---

## 11. File Summary

| File | Role |
|---|---|
| `softmax_base2.v` | Top-level pipeline: wires together range reduction, `k`/`r` decomposition, `exp(r)` LUT, `2^k` scaling, accumulation FSM, reciprocal, and normalization. |
| `softmax_base2_tb.v` | Self-checking testbench: 30 test vectors, software `$exp()` golden reference, per-output/sum/latency checks. |
| `exp_range_reducer.v` | Computes `y_i = x_i - max(x)` for numerical stability. |
| `max_finder.v` | Bit-level FP32 comparator (no float subtraction) used to find the max of two values. |
| `exp_kr_reducer.v` | Range-reduces `y` into `k` (integer) and `r ∈ [0, ln2)` via `y = k*ln2 + r`. |
| `exp_r_lut.v` | 8-region piecewise-linear approximation of `exp(r)` for `r ∈ [0, 0.7)`. |
| `exp_power_of_two.v` | Applies `2^k` scaling to an FP32 value via exponent-field addition only (no multiplication). |
| `fp32_adder.v` | General-purpose IEEE-754 FP32 adder/subtractor (truncating, not rounding). |
| `fp32_multiplier.v` | General-purpose IEEE-754 FP32 multiplier (truncating, not rounding). |
| `softmax_exp_accumulator.v` | FSM-driven sequential accumulator summing the 4 exponentials; also exposes an unused memory read-back port. |
| `softmax_reciprocal.v` | Thin wrapper delegating `1/sum` to `reciprocal_unit`. |
| `reciprocal_unit.v` | LUT-seeded, single-iteration Newton-Raphson FP32 reciprocal. |
| `reciprocal_lut.v` | 16-entry seed table for `reciprocal_unit`'s Newton-Raphson initial guess. |
| `softmax_normalizer.v` | Final `softmax_i = exp_i * (1/sum)` stage via 4 parallel multipliers. |
| `region_detector.v` | 16-region FP32 classifier over `[-4, 4]`; present in the file set but **not instantiated** anywhere in the current hierarchy. |
