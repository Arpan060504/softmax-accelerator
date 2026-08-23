# Algorithm

Two numerically expensive operations stand between Softmax and cheap
hardware: `exp(x)` and division. This project avoids a full transcendental
unit and a full divider by approximating both with LUT-seeded piecewise
methods.

## 1. Exponential approximation (`rtl/exp/`)

**Method:** 16-region piecewise-linear approximation over `x ∈ [-4, 4]`,
with each region 0.5 wide:

```
exp(x) ≈ a_r * x + b_r      for x in region r
```

- `region_detector.v` maps `x` (FP32) to a 4-bit region index. It does this
  by transforming the FP32 bit pattern into a monotonically-ordered
  unsigned value (`x ^ 0x80000000` for positive, `~x` for negative), which
  lets region boundaries be checked with plain unsigned comparisons instead
  of floating-point comparators. Inputs below -4 or above +4 are clamped
  into region 0 or 15 respectively — **silently**, no overflow flag.
- `exp_lut.v` stores the 16 `(a, b)` coefficient pairs as FP32 hex
  constants, one `case` per region.
- `exp_unit.v` composes: region lookup → coefficient lookup →
  `fp32_multiplier(a, x)` → `fp32_adder(result, b)`.

No documented derivation of how the 16 `(a, b)` pairs were fit (least-squares
fit to `exp(x)` per interval, endpoint-matching, etc.) exists yet, and there
is no standalone testbench for this unit — see `verification.md`. If someone
regenerates the coefficients, this file is where the fitting method should
be written down.

## 2. Reciprocal approximation (`rtl/reciprocal_unit/`)

**Method:** LUT-seeded single Newton-Raphson (NR) iteration for `1/x`, the
standard GPU/DSP approach — avoids long division / Goldschmidt / SRT
entirely.

1. Decompose `x = M · 2^e` (FP32 mantissa/exponent split).
2. Look up a coarse seed `y0 ≈ 1/M` from a 16-entry LUT, indexed by the top
   4 mantissa bits (`fraction[22:19]`).
3. One NR refinement step:
   ```
   y1 = y0 * (2 - M * y0)
   ```
   Each NR iteration for reciprocal roughly doubles the number of correct
   bits, so a ~4-5 bit seed plus one iteration lands around 8-10 correct
   bits.
4. Recombine the refined mantissa reciprocal with the correctly re-derived
   exponent (`e_final = e_y1 - e_x`, since `1/x = (1/M) · 2^-e`) to
   reconstruct the FP32 result.
5. Special cases handled: `x = 0 → ±∞`, exponent overflow `→ ±∞`, exponent
   underflow `→ ±0`. Sign is passed through but **untested** (see
   `verification.md` — all 18 test vectors were positive).

This whole path is combinational — no pipelining, no registered stages.

Measured accuracy (18 directed vectors, positive/normal inputs only):
**max relative error 0.092%**, against a 0.5% design target. See
`results.md` for the full breakdown and `verification.md` for what wasn't
tested.

## 3. Putting it together

```
softmax(x_i) = exp(x_i) * (1 / Σ_j exp(x_j))
```

The division is turned into a multiply by the reciprocal, computed once per
Softmax call over the accumulated sum, and reused for all 4 outputs — one
`reciprocal_unit` evaluation instead of 4 dividers. This is the main
hardware-cost argument for this design, though no area/LUT-count comparison
against a straightforward divider has actually been done yet (see
`future_work.md`).
