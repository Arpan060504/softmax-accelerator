# How VEXP Computes Softmax for N Elements

Based on: *VEXP: A Low-Cost RISC-V ISA Extension for Accelerated Softmax Computation in Transformers* (Wang et al., ARITH 2025), Section IV-C and Figure 4.

## Setup

- Data type: **BF16** (2 bytes/element).
- The Snitch core's FPU datapath is **64 bits wide**, so one register load/store handles **4 BF16 elements at once** (packed SIMD).
- For a row of `N` elements, the optimized kernel therefore issues `N/4` SIMD operations per pass, and the paper's loops are commonly unrolled by 4 (written as `N/16` iterations issuing 4 SIMD instructions each = 16 elements per FREP iteration, or `N/8` iterations issuing 2 elements' worth, depending on the stage).
- Two hardware loop mechanisms from the base Snitch ISA are reused:
  - **SSR** (Stream Semantic Registers) — turns memory loads/stores into implicit register reads/writes, removing explicit load/store instructions from the loop body.
  - **FREP** (Floating-Point Repetition) — replays a short instruction sequence for a configured number of iterations without loop-control overhead (no branch/counter instructions).
- The custom instruction added by this paper is **VFEXP** (packed) / **FEXP** (scalar), which computes BF16 exponentiation in hardware in **2 clock cycles** for a 4-element SIMD group.

The three stages are: **MAX → EXP (+ running SUM) → NORM**.

## Stage 1 — MAX (find the row maximum)

Purpose: compute `M = max(x_0, ..., x_{N-1})`, needed for numerically-stable Softmax.

Assembly pattern (Fig. 4, "Optim Assembly"):
```
MAX Loop for N/16:
ssr ft0 read double
frep N/16, 4
vfmax.h ft3, ft3, ft0
vfmax.h ft4, ft4, ft0
vfmax.h ft5, ft5, ft0
vfmax.h ft6, ft6, ft0
```
- `ssr ft0 read double` streams 64-bit (4×BF16) chunks from memory into `ft0` automatically each iteration.
- `frep N/16, 4` repeats the following 4 `vfmax.h` instructions for `N/16` iterations.
- Each `vfmax.h` operates on a packed 4-element vector, and 4 different accumulator registers (`ft3..ft6`) are used so that 4 independent partial-max vectors accumulate in parallel (loop-unrolling for instruction-level parallelism).
- This processes `N/16 × 4 (instructions) × 4 (elements/instruction) = N` elements total.
- The final scalar row max is obtained by a final reduction across `ft3..ft6` (the paper doesn't spell out this last horizontal-reduction instruction sequence explicitly).

## Stage 2 — EXP (subtract max, exponentiate, accumulate sum)

Purpose: compute `e_i = exp(x_i − M)` for all `i`, and simultaneously accumulate `S = Σ e_i`.

Assembly pattern (Fig. 4):
```
EXP Loop for N/8:
ssr ft1 read double
ssr ft2 write double
frep N/8, 8
vfsub.h ft3, ft1, max
vfsub.h ft4, ft1, max
vfexp.h ft3, ft3
vfexp.h ft4, ft4
vfsgnj.h ft2, ft3
vfsgnj.h ft2, ft4
vfadd.h  ft3, ft3
vfadd.h  ft4, ft4
```
- Two SSR streams handle the loads (`ft1`, raw x-values) and stores (`ft2`, results) without explicit memory instructions.
- Within one `frep` body (8 instructions), the loop:
  1. **Subtracts max**: `vfsub.h` computes `x_i − M` for two 4-wide groups at once (`ft3`, `ft4`).
  2. **Exponentiates**: `vfexp.h` — this is the paper's new hardware instruction — computes `exp(z)` for each packed group **in 2 clock cycles**, versus the software baseline's 319 cycles/element using a `math.h`-style piecewise-polynomial LUT approximation.
  3. **Writes result**: `vfsgnj.h` moves the exponentiated values into the output stream register `ft2` (to be stored via SSR).
  4. **Accumulates sum**: `vfadd.h` adds the new exponentials into the running sum accumulators (`ft3`, `ft4` reused as accumulators), building `S = Σ_i e_i` progressively as the loop executes — the sum is computed *in the same pass* as the exponentiation, not as a separate loop.
- With `N/8` iterations, each handling 8 elements (two 4-wide `vfexp.h` calls), the loop covers all `N` elements.
- Net effect: **exponentiation + accumulation fused into one FREP/SSR loop**, at roughly 2 cycles per 4-element group instead of 319 cycles per single element.

## Stage 3 — NORM (normalize by the sum)

Purpose: compute `y_i = e_i / S` for all `i`.

Key optimization: instead of doing `N` divisions, the kernel computes **one reciprocal** `1/S` up front, then does `N` multiplications (much cheaper than division).

Assembly pattern (Fig. 4):
```
NORM Loop for N/16:
fdiv.h (1/sum), 1, sum      # single scalar reciprocal, computed once
ssr ft0 read double
ssr ft1 write double
frep N/16, 4
vfmul.h ft1, (1/sum), ft0
vfmul.h ft1, (1/sum), ft0
vfmul.h ft1, (1/sum), ft0
vfmul.h ft1, (1/sum), ft0
```
- `fdiv.h (1/sum), 1, sum` — a single scalar division, executed **once outside the SIMD loop**.
- The `frep N/16, 4` loop then applies `vfmul.h` (packed multiply) to scale every 4-element group by the precomputed reciprocal, covering all `N` elements via `N/16` iterations × 4 instructions × 4 elements.

## Summary Table (per the paper's own instruction/cycle counts)

| Kernel | Instructions/output | Cycles/output |
|---|---|---|
| Baseline (unoptimized, scalar, software EXP) | 56 | 360 |
| Optimized (FREP + SSR + SIMD + VFEXP) | 1.5 | 2.125 |

- This yields the paper's headline **162.7× latency reduction** and **74.3× energy reduction** for the Softmax kernel alone.
- The dominant cost in the baseline is the software exponential (319 cycles/element via LUT + polynomial); MAX and NORM contribute comparatively little (only ~1.1× speedup available from optimizing them alone — nearly all of the gain, ~61.6×, requires the hardware VFEXP instruction).

## Handling N Not a Multiple of 4

The paper's benchmarks use sequence lengths that are powers of two (32, 64, 128, ..., 2048), all divisible by 4 (and by 16), so the `N/16`- or `N/8`-style FREP loop counts divide evenly. The paper does **not** describe a tail-handling/masking mechanism for `N mod 4 ≠ 0`; that would need to be added separately for arbitrary sequence lengths.
