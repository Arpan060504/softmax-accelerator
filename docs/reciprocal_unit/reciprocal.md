# FP32 Reciprocal Unit — Design Documentation

## 1. Overview

This design computes an approximate IEEE-754 single-precision (FP32) reciprocal,
`1/x`, using a classic **LUT seed + one Newton-Raphson iteration** architecture.
This is the same general strategy used by hardware FPUs and GPUs for fast
reciprocal/rsqrt approximation (e.g. the historical "fast inverse square root"
family of tricks), instead of doing a full restoring/non-restoring division.

Pipeline, conceptually:

```
x (FP32)
  │
  ├─► unpack sign / exponent / fraction
  │
  ├─► LUT lookup on top 4 mantissa bits ──► y0 ≈ 1/M   (M = 1.fraction)
  │
  ├─► Newton-Raphson refinement:
  │        y1 = y0 * (2 − M·y0)
  │
  ├─► recompute final exponent from (exponent of y1) − (exponent of x)
  │
  └─► reassemble sign / exponent / mantissa → reciprocal (FP32)
```

Three modules are involved:

| Module | Role |
|---|---|
| `reciprocal_unit` | Top-level: unpacking, NR iteration, exponent math, repacking, special cases |
| `reciprocal_lut` | 16-entry lookup table giving the initial seed `y0 ≈ 1/M` |
| `region_detector` | **Not used by `reciprocal_unit`** — a standalone 16-region range classifier (see §5) |

It relies on two external, un-shown modules: `fp32_multiplier` and `fp32_adder`,
which are assumed to be standard combinational (or pipelined) IEEE-754 FP32
multiply/add units.

---

## 2. `reciprocal_unit` — step by step

### 2.1 Unpacking the input (Section 1 in code)

```
sign     = x[31]
exponent = x[30:23]   // 8-bit biased exponent
fraction = x[22:0]    // 23-bit mantissa fraction
```

Standard IEEE-754 field split. No interpretation yet — this just slices the bits.

### 2.2 Unbiased exponent of x (Section 2)

```
unbiased_exp = exponent − 127
```

Every FP32 number (in normal form) is `x = M × 2^e`, where `M = 1.fraction`
(the implicit leading 1) and `e` is this unbiased exponent. This is computed
in 10-bit signed arithmetic (`$signed({2'b00, exponent}) - 10'sd127`) so it
can represent the full range including negative results, with headroom before
the final re-bias step.

### 2.3 LUT index (Section 3)

```
lut_index = fraction[22:19]   // top 4 bits of the mantissa
```

The mantissa's fractional part is 23 bits, but only the **top 4 bits** are
used to select a seed value. This effectively divides the mantissa range
`[1.0, 2.0)` into 16 equal sub-intervals, each `1/16` wide, and picks one
constant seed per sub-interval (see §3 for why this matters for accuracy).

### 2.4 LUT lookup (Section 4)

`reciprocal_lut` returns `reciprocal_estimate = y0`, an FP32-encoded
approximation of `1/M` for whichever segment `M` falls into (details in §3).

### 2.5 Converting the mantissa into an FP32 number (Section 5)

```
mantissa_fp32 = { 1'b0, 8'd127, fraction }
```

To feed `M` (a number in `[1.0, 2.0)`) into the FP32 multiplier, the design
re-encodes it as a normal FP32 value with biased exponent `127` (i.e.
unbiased exponent `0`) and the original fraction bits. This is just
`M = 1.fraction × 2^0`, packaged as a valid FP32 word.

### 2.6 Newton-Raphson iteration (Section 6)

The classic NR update for reciprocal approximation is:

```
y1 = y0 · (2 − M·y0)
```

This converges quadratically toward `1/M` when `y0` is a reasonably close
seed — each iteration roughly **squares** the relative error.

Implemented in three combinational stages:

1. **`mul1`**: `mul1_out = M × y0` (using `fp32_multiplier`)
2. **Negation**: `negative_mul1_out = −mul1_out`, done cheaply by flipping the
   FP32 sign bit (`~mul1_out[31]`) — valid because FP32 negation is always
   just a sign-bit flip, no magnitude change needed.
3. **`adder`**: `correction = 2.0 + (−mul1_out) = 2 − M·y0`, using the FP32
   constant `32'h40000000` = 2.0 and `fp32_adder`.
4. **`mul2`**: `y1 = y0 × correction` — the refined reciprocal of the mantissa.

At this point `y1` holds an FP32-encoded approximation of `1/M`, still with
an exponent near `127` (since `M ∈ [1,2)` implies `1/M ∈ (0.5,1]`).

### 2.7 Recovering the correct final exponent (Sections 7–9)

Because the NR iteration was done entirely on the *mantissa* (ignoring `x`'s
actual exponent), the result `y1` only represents `1/M`, not `1/x`. The
overall relationship is:

```
x = M · 2^e
1/x = (1/M) · 2^(−e)
```

So the design:

1. Extracts `y1`'s own biased exponent field (`y1[30:23]`) and unbiases it →
   `y1_unbiased_exp` (this captures any exponent drift introduced by the NR
   arithmetic itself, e.g. if `1/M` rounded into `(0.5, 1)` vs exactly `1`).
2. Computes `final_unbiased_exp = y1_unbiased_exp − unbiased_exp`, i.e.
   `ey1 − e`, matching the `2^(−e)` term above.
3. Re-biases: `final_biased_exp = final_unbiased_exp + 127`, producing a
   value ready to drop into the output's exponent field.

All of this is done in 10-bit signed arithmetic so overflow/underflow past
the 8-bit exponent range can be detected explicitly, rather than silently
wrapping.

### 2.8 Final reconstruction and special cases (Section 10)

A combinational `always @(*)` block assembles the result, handling four cases:

| Case | Condition | Output |
|---|---|---|
| **Zero input** | `x[30:0] == 0` (ignores sign, so ±0 both match) | `±∞` (sign preserved, exp = `0xFF`, mantissa = 0) |
| **Exponent overflow** | `final_biased_exp >= 255` | `±∞` (saturates rather than wrapping into a bogus finite value) |
| **Exponent underflow** | `final_biased_exp <= 0` | `±0` (flushes to zero rather than producing a subnormal) |
| **Normal case** | otherwise | `{ sign, final_biased_exp[7:0], y1[22:0] }` |

In the normal case, the **sign is taken directly from the input** (reciprocal
of a negative number is negative — correct), the **exponent is the
recomputed final exponent**, and the **mantissa is taken straight from `y1`**
(truncated, not rounded — see §4).

### 2.9 Output (Section 11)

```
assign reciprocal = reciprocal_reg;
```

Simple wire-out of the case-selected register.

---

## 3. `reciprocal_lut` — the seed table

A 16-entry combinational lookup table indexed by the top 4 mantissa bits.
Each entry is a **pre-computed constant FP32 encoding of `1/M`** for the
midpoint (or a minimax-fitted point) of that 1/16-wide mantissa segment:

| Index | Segment (M range) | Value | ≈ Decimal |
|---|---|---|---|
| 0 | [1.000, 1.0625) | `0x3F783E10` | 0.969697 |
| 1 | [1.0625, 1.125) | `0x3F6A0EA1` | 0.914286 |
| ... | ... | ... | ... |
| 15 | [1.9375, 2.000) | `0x3F020821` | 0.507937 |

Each value is itself a valid FP32 word (exponent `126`, so value is in
`(0.5, 1.0)`), which is exactly the correct range for `1/M` when
`M ∈ [1, 2)`. The `default` case returns `0`, which only fires if
`lut_index` somehow takes an out-of-range value — not reachable given it's
driven directly from 4 wire bits, so this is purely a safety net for
simulation/synthesis tools that require full case coverage.

This is a **piecewise-constant** approximation, not piecewise-linear — the
seed doesn't interpolate within a segment based on the remaining mantissa
bits, it just picks one fixed value per 1/16 slice.

---

## 4. Precision characteristics (read this before trusting the output)

This is not a full-precision, correctly-rounded FP32 divider, and it isn't
intended to be — it's a fast approximate reciprocal. Understanding its actual
error budget matters before wiring it into anything that assumes IEEE
correctness:

- **Pre-NR seed error**: each LUT segment is `1/16` of the mantissa range
  wide, giving a worst-case relative error of roughly **3%** before any
  refinement.
- **Post-NR error**: one Newton-Raphson iteration approximately **squares**
  the relative error, so post-iteration error is on the order of
  `0.03² ≈ 0.1%`, corresponding to roughly **10 correct bits** of mantissa
  precision.
- **FP32 claims 23 bits** of mantissa. The bottom ~13 bits of the output
  mantissa are effectively noise relative to the true reciprocal — the
  hardware will happily produce a full 32-bit word, but only about the top
  third of the mantissa is numerically meaningful.
- **Truncation, not rounding**: the final mantissa is taken directly from
  `y1[22:0]` with no round-to-nearest-even step, adding a small additional
  systematic (not random) bias on top of the above.

If the downstream use case can tolerate ~0.1% relative error (e.g. some
neural-network normalization/quantization paths, or as a seed for a *second*
refinement stage), this is a reasonable and cheap design. If a design or
testbench assumes this behaves like a correctly-rounded IEEE reciprocal, it
will not.

**Improving precision, in increasing order of hardware cost:**

1. **Second NR iteration** — squares the error again (~0.1% → ~10⁻⁶ range),
   at the cost of another multiplier/adder stage and pipeline latency.
2. **Wider LUT with linear interpolation** — use more mantissa bits as index
   and store a slope + intercept per segment instead of a constant, cutting
   pre-NR error dramatically without a second full NR pass.
3. **Goldschmidt's algorithm** — restructures the iteration so the two
   multiplications per step are independent and can be pipelined/parallelized,
   improving throughput over serial NR for the same convergence.
4. **Bipartite/multipartite table methods** — used in real FPU designs to
   reach full precision from table lookups plus a small adder, without any
   iterative refinement or a full multiplier in the loop.

---

## 5. `region_detector` — not part of this pipeline

This module is **not instantiated anywhere inside `reciprocal_unit`**. It
independently classifies an FP32 input into one of 16 fixed regions across
`[-4.0, 4.0]` (each 0.5 wide, clamped at the ends), using a clever trick:

- FP32 bit patterns, when the sign bit is XORed for positives or bitwise
  inverted for negatives, become **monotonically ordered as unsigned
  integers**. This lets the module do plain unsigned `<` comparisons against
  precomputed boundary constants instead of doing real floating-point
  comparison logic.
- The 14 boundary constants (`B_NEG_3_5` … `B_POS_3_5`) are exactly the
  transformed bit patterns of ±0.5, ±1.0, ±1.5, ... ±3.5.

This structure (piecewise regions over a bounded domain, boundary-based
classification) is typical of a **piecewise-linear activation function
approximator** (e.g. sigmoid, tanh, or GELU), not a reciprocal unit. It's
likely either:

- leftover/misplaced from a different module in the same project, or
- intended to be wired in later (e.g. to select per-region NR seeds or
  correction coefficients) but not yet connected.

Worth clarifying with whoever owns this file before treating it as dead code
to delete, since as-is it does not affect `reciprocal_unit`'s behavior at all.

---

## 6. Known gaps / edge cases not handled

| Input pattern | Current behavior | Correct IEEE behavior | Impact |
|---|---|---|---|
| NaN (`exponent = 0xFF`, `fraction ≠ 0`) | Falls through to the normal-case path (zero-check only checks for all-zero bits); produces a **finite garbage value** | Should propagate NaN | Silent wrong answer, not a flagged error — high severity |
| Subnormal input (`exponent = 0`, `fraction ≠ 0`) | Treated as `1.fraction` (implicit leading 1) via `mantissa_fp32` | Should use implicit leading 0 (`0.fraction`) | Reciprocal wrong by up to 2× |
| Infinity input (`exponent = 0xFF`, `fraction = 0`) | Not explicitly special-cased; falls into overflow/underflow logic depending on how the exponent math resolves | Should return signed zero | Not verified to produce the correct signed-zero result |
| Result that should round to a subnormal | Flushed to zero via the underflow branch | Should produce a subnormal result | Likely intentional flush-to-zero, but undocumented as a design decision |
| Mantissa rounding | Truncated | Round-to-nearest-even expected for IEEE compliance | Adds systematic bias (see §4) |

None of these are exotic corner cases in practice — NaN propagation and
subnormal handling in particular are common in real workloads and should be
addressed (or explicitly documented as out-of-scope) before this is treated
as a general-purpose reciprocal unit rather than a fast-path approximation
for well-behaved normal inputs.

---

## 7. Summary

`reciprocal_unit` implements a standard **LUT-seeded, single-iteration
Newton-Raphson FP32 reciprocal approximation** with correct sign handling,
independent exponent recomputation, and saturating overflow/zero-flush
underflow behavior. The mantissa refinement path is arithmetically sound.
Its main limitations are: no NaN handling, incorrect treatment of subnormal
inputs, truncation instead of rounding, and roughly 10 bits of real
precision packed into a 23-bit mantissa field. `region_detector` is present
in the same source but architecturally unrelated to this unit.
