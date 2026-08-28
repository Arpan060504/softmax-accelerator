# `exp_power_of_two` — RTL & Verification Documentation

## 1. Overview

`exp_power_of_two` is a combinational Verilog module that computes:

```
exp_out = exp_r * 2^k
```

where `exp_r` is an IEEE-754 single-precision (FP32) floating-point number and `k` is a
signed integer exponent shift. The module is designed for use in hardware **Softmax**
pipelines, where a base value `exp(r)` (already computed by some other block, e.g. a
piecewise/LUT-based `exp()` unit) needs to be rapidly rescaled by a power-of-two factor
`2^k` without going through a general floating-point multiplier.

Because multiplying an FP32 number by a power of two only changes its **exponent field**
(the sign and mantissa/fraction are untouched), this operation can be implemented as pure
integer addition on the exponent field — no mantissa multiplication, rounding, or
normalization logic is required. This makes the block extremely cheap in area and single
combinational-cycle in latency.

---

## 2. Module Interface

```verilog
module exp_power_of_two (
    input  wire [31:0]        exp_r,
    input  wire signed [7:0]  k,
    output reg  [31:0]        exp_out
);
```

| Signal    | Direction | Width          | Description                                                        |
|-----------|-----------|----------------|----------------------------------------------------------------------|
| `exp_r`   | Input     | 32 bits        | IEEE-754 FP32 value to be scaled. Expected to be `>= 0` (a value produced by an `exp()` computation), but the module also handles the general IEEE-754 cases (zero, subnormal, Inf/NaN, negative sign) defensively. |
| `k`       | Input     | 8 bits, signed | Power-of-two exponent shift. `exp_out = exp_r * 2^k`.                |
| `exp_out` | Output    | 32 bits        | IEEE-754 FP32 result, registered as `reg` but driven combinationally from an `always @(*)` block. |

**Latency:** 0 clock cycles (purely combinational).
**Timescale:** `1ns / 1ps` (used for simulation only; does not affect synthesis).

---

## 3. IEEE-754 FP32 Background

```
 31        30                23 22                                0
+-----+------------------------+----------------------------------+
| S   |        Exponent (E)    |             Fraction (F)          |
+-----+------------------------+----------------------------------+
  1 bit         8 bits                        23 bits
```

- **Sign (S):** 0 = positive, 1 = negative.
- **Exponent (E):** biased by 127. Actual exponent = `E - 127`.
- **Fraction (F):** 23-bit stored mantissa. For a *normal* number, the value is
  `(1.F) * 2^(E-127)`. `E = 0` denotes zero/subnormal; `E = 255` denotes Inf/NaN.

**Key property exploited by this design:**

```
value = (1.F) * 2^(E - 127)
value * 2^k = (1.F) * 2^(E - 127 + k) = (1.F) * 2^((E + k) - 127)
```

So multiplying by `2^k` is equivalent to simply computing a **new biased exponent**
`E_new = E + k`, leaving the sign and fraction bits completely unchanged. No bias
re-addition/subtraction juggling is needed because `k` is added directly to the already
biased field `E`.

---

## 4. RTL Design (`exp_power_of_two.v`)

### 4.1 Internal Registers

| Signal          | Width            | Purpose                                                          |
|-----------------|------------------|-------------------------------------------------------------------|
| `sign`          | 1 bit            | Unpacked sign bit of `exp_r`.                                     |
| `exponent`      | 8 bits           | Unpacked biased exponent field of `exp_r`.                        |
| `fraction`      | 23 bits          | Unpacked fraction field of `exp_r` (passed through unmodified).   |
| `new_exponent`  | 10 bits, signed  | `exponent + k`, computed in a wider signed field to safely detect underflow (≤0) and overflow (≥255) without wraparound. |

### 4.2 Case-by-Case Logic

The `always @(*)` block evaluates the following cases **in priority order**:

1. **Exact zero** (`exp_r == 32'h00000000`)
   → `exp_out = 0`. Scaling zero by any power of two is still zero.

2. **Inf / NaN** (`exponent == 8'hFF`)
   → `exp_out = exp_r` (pass-through, unmodified). These special values are not scaled;
     `Inf * 2^k = Inf`, and `NaN` must remain `NaN` regardless of `k`.

3. **Subnormal** (`exponent == 8'h00` and `exp_r != 0`)
   → `exp_out = exp_r` (pass-through, unmodified).
   Rationale: `exp(r) >= 1.0` is always true for the intended Softmax use case, so a
   subnormal input is not expected in practice. Rather than mis-handle it with the
   normalized-number formula (which would corrupt the value), the design safely passes
   it through unchanged.

4. **Normalized number** (`0 < exponent < 255`)
   - Compute `new_exponent = signed({1'b0, exponent}) + k` in a 10-bit signed register
     (wide enough to hold `exponent` up to 254 plus/minus an 8-bit signed `k`, i.e. a
     range of roughly `-128` to `+382`, without overflow/wraparound corrupting the
     comparison).
   - **Underflow** (`new_exponent <= 0`): result would be below the smallest normalized
     FP32 magnitude (or exactly at the zero-exponent boundary) → flush to `+0.0`
     (`exp_out = 32'h00000000`). This is a "flush-to-zero" underflow policy — subnormal
     results are *not* generated; they simply round down to zero.
   - **Overflow** (`new_exponent >= 255`): result exceeds the largest finite FP32
     exponent → saturate to `+Infinity` (`exp_out = {1'b0, 8'hFF, 23'h0}`). Note the sign
     bit of the overflow result is hardwired to `0`, consistent with the assumption that
     `exp_r` is always non-negative in the intended use case.
   - **Normal case** (`0 < new_exponent < 255`): `exp_out = {sign, new_exponent[7:0],
     fraction}` — sign and fraction are carried through unchanged; only the exponent
     field is replaced.

### 4.3 Design Notes / Assumptions

- The module assumes `exp_r >= 0` in its primary use case (output of an `exp()`
  function), but the Inf/NaN and pass-through branches still respect the original sign
  bit, so negative Inf (`0xFF800000`) is correctly passed through unchanged.
- No rounding is required or performed — since only the exponent changes, the mantissa
  bits are bit-exact between input and output.
- The overflow/underflow thresholds are checked against the *biased* exponent field
  directly (`new_exponent <= 0` and `new_exponent >= 255`), which map to the standard
  IEEE-754 reserved boundaries (`E = 0` for zero/subnormal, `E = 255` for Inf/NaN).
- The design is purely combinational; no clock or reset ports exist.

---

## 5. Testbench (`exp_power_of_two_tb.v`)

### 5.1 Structure

- **DUT instantiation:** `exp_power_of_two dut (.exp_r(exp_r), .k(k), .exp_out(exp_out));`
- **Waveform dump:** VCD file `exp_power_of_two_tb.vcd`, capturing all testbench and DUT
  signals via `$dumpvars(0, exp_power_of_two_tb)`.
- **`fp32_to_real` function:** A behavioral (non-synthesizable) bit-to-real converter used
  purely for human-readable `$display` output. It manually reconstructs sign, exponent,
  and mantissa per IEEE-754 rules, including:
  - Exact zero → `0.0`
  - `exponent == 8'hFF` → a large sentinel value (`±9.99e37`) used to visually represent
    Inf/NaN in the log (not a bit-exact real-number reproduction of Inf/NaN, just a
    display marker).
  - Normal numbers → standard `(1.F) * 2^(E-127)` reconstruction via iterative
    multiplication/division by 2.
  - Subnormal numbers → reconstructed using the fixed `2^-126` weight scale with no
    implicit leading 1.
- **`test_case` task:** Applies `exp_r` and `k`, waits `#5` for combinational settling,
  converts input/output/expected values to real numbers for logging, and performs a
  **bit-exact comparison** (`exp_out === expected_out`) using Verilog's case-equality
  operator (`===`), which is important for verifying exact bit patterns of special
  values like Infinity and NaN (a plain `==` could be ambiguous/undefined for `x`/`z`,
  though not an issue here since all values are fully defined).
- **Pass/fail tracking:** `pass_count` / `fail_count` integers accumulate results, with a
  final summary block printed at the end of simulation.

### 5.2 Test Plan / Coverage

The testbench exercises **26 directed test cases** grouped into 7 categories:

| # | Category | Purpose | Test Count |
|---|----------|---------|------------|
| 1 | Zero Corner Cases | Confirm `0.0 * 2^k = 0.0` for `k = 0`, negative, and positive | 3 |
| 2 | Identity Scaling (`k = 0`) | Confirm the pass-through path when no scaling is requested | 3 |
| 3 | Typical Softmax Range (negative `k`) | Down-scaling of values in `[1.0, 2.0)` mantissa range, typical of normalized Softmax inputs | 7 |
| 4 | Positive `k` | Up-scaling / exponent growth | 3 |
| 5 | Underflow Boundaries | Exercise `E_new = 1` (last valid normal), `E_new = 0`, and `E_new = -1` (flush-to-zero) | 3 |
| 6 | Overflow Boundaries | Exercise `E_new = 254` (max normal), `E_new = 255`, and deep overflow (`E_new = 264`) saturating to `+Inf` | 3 |
| 7 | Special IEEE-754 Pass-throughs | `+Inf`, `-Inf`, `NaN`, and subnormal inputs, confirming unmodified pass-through | 4 |

### 5.3 How to Run

Using **Icarus Verilog** (or any compatible simulator):

```bash
iverilog -o sim.out exp_power_of_two.v exp_power_of_two_tb.v
vvp sim.out
# Optional waveform viewing:
gtkwave exp_power_of_two_tb.vcd
```

---

## 6. Verification Results

### 6.1 Summary

| Metric        | Value |
|---------------|-------|
| Total Tests   | 26    |
| Passed        | 26    |
| Failed        | 0     |
| **Result**    | **ALL TESTS PASSED** |

### 6.2 Detailed Results

| # | Test Name | `exp_r` (hex) | `k` | Expected (hex) | Actual (hex) | Result |
|---|-----------|---------------|-----|-----------------|---------------|--------|
| 1 | Exact Zero: 0.0 * 2^0 | `0x00000000` | 0 | `0x00000000` | `0x00000000` | PASS |
| 2 | Exact Zero: 0.0 * 2^(-5) | `0x00000000` | -5 | `0x00000000` | `0x00000000` | PASS |
| 3 | Exact Zero: 0.0 * 2^(+5) | `0x00000000` | +5 | `0x00000000` | `0x00000000` | PASS |
| 4 | k=0: 1.0 * 2^0 = 1.0 | `0x3F800000` | 0 | `0x3F800000` | `0x3F800000` | PASS |
| 5 | k=0: 1.5 * 2^0 = 1.5 | `0x3FC00000` | 0 | `0x3FC00000` | `0x3FC00000` | PASS |
| 6 | k=0: 2.0 * 2^0 = 2.0 | `0x40000000` | 0 | `0x40000000` | `0x40000000` | PASS |
| 7 | k=-1: 1.0 * 2^(-1) = 0.5 | `0x3F800000` | -1 | `0x3F000000` | `0x3F000000` | PASS |
| 8 | k=-2: 1.0 * 2^(-2) = 0.25 | `0x3F800000` | -2 | `0x3E800000` | `0x3E800000` | PASS |
| 9 | k=-3: 1.0 * 2^(-3) = 0.125 | `0x3F800000` | -3 | `0x3E000000` | `0x3E000000` | PASS |
| 10 | k=-4: 1.3 * 2^(-4) | `0x3FA66666` | -4 | `0x3DA66666` | `0x3DA66666` | PASS |
| 11 | k=-6: 1.75 * 2^(-6) | `0x3FE00000` | -6 | `0x3CE00000` | `0x3CE00000` | PASS |
| 12 | k=-8: 2.0 * 2^(-8) = 2^(-7) | `0x40000000` | -8 | `0x3C000000` | `0x3C000000` | PASS |
| 13 | k=-12: 1.0 * 2^(-12) | `0x3F800000` | -12 | `0x39800000` | `0x39800000` | PASS |
| 14 | k=+1: 1.0 * 2^(+1) = 2.0 | `0x3F800000` | +1 | `0x40000000` | `0x40000000` | PASS |
| 15 | k=+2: 1.0 * 2^(+2) = 4.0 | `0x3F800000` | +2 | `0x40800000` | `0x40800000` | PASS |
| 16 | k=+3: 1.5 * 2^(+3) = 12.0 | `0x3FC00000` | +3 | `0x41400000` | `0x41400000` | PASS |
| 17 | Min Normal Limit: E_new = 1 | `0x3F800000` | -126 | `0x00800000` | `0x00800000` | PASS |
| 18 | Underflow Boundary: E_new = 0 → 0 | `0x3F800000` | -127 | `0x00000000` | `0x00000000` | PASS |
| 19 | Deep Underflow: E_new = -1 → 0 | `0x3F800000` | -128 | `0x00000000` | `0x00000000` | PASS |
| 20 | Max Normal FP32: Exp = 254 | `0x7F000000` | 0 | `0x7F000000` | `0x7F000000` | PASS |
| 21 | Overflow Boundary: Exp = 255 → +Inf | `0x7F000000` | +1 | `0x7F800000` | `0x7F800000` | PASS |
| 22 | Deep Overflow: Exp = 264 → +Inf | `0x7F000000` | +10 | `0x7F800000` | `0x7F800000` | PASS |
| 23 | Pass-through: +Infinity | `0x7F800000` | +2 | `0x7F800000` | `0x7F800000` | PASS |
| 24 | Pass-through: -Infinity | `0xFF800000` | -2 | `0xFF800000` | `0xFF800000` | PASS |
| 25 | Pass-through: NaN | `0x7FC00000` | +4 | `0x7FC00000` | `0x7FC00000` | PASS |
| 26 | Pass-through: Subnormal (Exp=0) | `0x00400000` | -1 | `0x00400000` | `0x00400000` | PASS |

All 26 test cases matched their expected FP32 bit patterns exactly (`===` bit-exact
comparison), with **zero failures**.

### 6.3 Coverage Analysis

- **Functional coverage:** All primary RTL branches are exercised — exact zero,
  Inf/NaN pass-through, subnormal pass-through, normal-to-normal scaling, underflow
  flush-to-zero, and overflow saturation to Infinity.
- **Boundary coverage:** Both underflow (`E_new = 1, 0, -1`) and overflow
  (`E_new = 254, 255, 264`) boundaries are tested at, just past, and well past the
  transition point, confirming correct `<=`/`>=` comparison behavior in the RTL.
- **Sign handling:** Verified for both `+Infinity` and `-Infinity` pass-through,
  confirming the sign bit is preserved correctly through the special-value paths.
- **Mantissa preservation:** Cases like `k=-4: 1.3 * 2^(-4)` confirm the 23-bit
  fraction field (`0x266666` pattern) survives exponent-only scaling without any bit
  corruption or unintended rounding.

---

## 7. Known Limitations / Future Considerations

1. **Flush-to-zero underflow:** The module does not generate subnormal results when
   `E_new <= 0`; it flushes directly to zero. This is a common simplification for
   Softmax-style pipelines (since subnormal precision is rarely significant there) but
   should be called out explicitly if bit-exact IEEE-754 subnormal generation is ever
   required downstream.
2. **Sign is not forced on overflow:** The `+Infinity` overflow result is hardwired
   with `sign = 0`. If `exp_r` could ever legitimately be negative and overflow, the
   result would incorrectly saturate to `+Inf` instead of `-Inf`. This is safe under
   the stated assumption that `exp_r >= 0` (output of an exponential function) but is
   a latent risk if the module is reused in a more general context.
3. **Subnormal-input handling is a pass-through, not a true scale:** If a genuine
   subnormal `exp_r` is ever presented (not expected under current assumptions), the
   module will *not* actually apply the `2^k` scaling to it — it returns the value
   unmodified. This should be revisited if the module's usage assumptions change.
4. **No rounding modes:** Since mantissa bits are never modified, no IEEE-754 rounding
   mode (round-to-nearest, etc.) is applicable or implemented — this is by design, not
   an oversight.

---

## 8. File Summary

| File | Purpose |
|------|---------|
| `exp_power_of_two.v` | Synthesizable RTL implementing FP32 × 2^k via exponent-only arithmetic. |
| `exp_power_of_two_tb.v` | Self-checking testbench with 26 directed bit-exact test cases and a real-number display helper for waveform/log readability. |
| `exp_power_of_two_tb.vcd` | Generated waveform dump for visual debugging in a viewer such as GTKWave. |
