# Future Work

Ordered roughly by "do this before anything else" to "long-term."

## Immediate cleanup (no design work, just hygiene)

- [ ] Delete the empty `rtl/softmax/reciprocal_unit.v` stub file.
- [ ] Rename `softmax_exp_accumulator.V` → `softmax_exp_accumulator.v`.
- [ ] Decide the fate of `softmax_read_controller.v`,
      `softmax_normalization_controller.v`, and
      `softmax_normalization_stage.v`: either wire them into `softmax_top.v`
      and remove the inline FSM logic they duplicate, or delete them. Right
      now they're tested dead code, which is worse than either extreme —
      it makes the architecture look more finished than it is.
- [ ] Fix the top-level `README.md` on GitHub: it currently claims a MIPS32
      5-stage CPU is "Completed." It isn't started. This is the kind of
      inaccuracy that costs credibility if anyone (a reviewer, a
      collaborator) actually opens the repo expecting CPU code.
- [ ] Reorganize `rtl/` and `tb/` to match a consistent structure
      (`rtl/arithmetic/`, `rtl/exp/`, `rtl/softmax/`, `rtl/top/`; mirrored
      `tb/`) — see the mapping table in the top-level `README.md`.
- [ ] Add a `.gitignore` (simulation binaries, waveform dumps, editor files
      — none of this is currently ignored).

## Verification gaps (highest-value next work)

- [ ] Write missing testbenches: `fp32_multiplier`, `region_detector`,
      `exp_lut`, `exp_unit`, `input_selector`.
- [ ] Run every existing testbench and commit the actual output
      (`simulation/logs/`), rather than leaving "it has a testbench" as the
      only evidence of correctness.
- [ ] Measure `exp_unit` accuracy per-region (all 16), not just in
      aggregate, and populate `results/exp_accuracy.csv`.
- [ ] Extend `reciprocal_unit_tb.v` with negative, subnormal, and NaN/Inf
      vectors, and exercise the overflow/underflow clamp branches — all
      explicitly called out as untested in the module's own README.
- [ ] Build a golden-model comparison (Python/NumPy Softmax) against
      `softmax_top` output across a swept range of input vectors, and
      populate `results/softmax_accuracy.csv`. This is the number that
      actually validates the project's core claim.

## Design gaps

- [ ] Numerical stabilization: the design silently assumes inputs are in
      `[-4, 4]`. Either enforce/flag out-of-range inputs, or implement the
      standard `exp(x - max(x))` stabilization so the accelerator is robust
      to arbitrary input magnitudes — which real attention-layer inputs
      will have.
- [ ] Generalize beyond 4 elements. A fixed 4-wide Softmax isn't directly
      usable for real Transformer attention (sequence lengths are
      typically much larger and variable). Decide between a wider fixed
      width, a streaming/iterative architecture, or an N-configurable one.
- [ ] Document how the `exp_lut` `(a, b)` coefficients were derived (fit
      method, error bound target) so they can be regenerated or extended if
      the input range or region count changes.
- [ ] Re-evaluate whether one clock cycle (`RECIP` state) is enough margin
      for the combinational reciprocal path once synthesis timing is known.

## Toward the original MIPS32 goal

None of this exists yet and shouldn't be described as in-progress until it
is:

- [ ] MIPS32 5-stage pipeline RTL.
- [ ] Custom instruction encoding + decode support for invoking the Softmax
      accelerator.
- [ ] Software baseline Softmax implementation (MIPS32 assembly/C) for
      comparison.
- [ ] Integration of `softmax_top` as a coprocessor/functional unit off the
      pipeline.
- [ ] The actual baseline-vs-accelerated comparison (cycles, latency,
      utilization, power, numerical error) that's the stated point of the
      project.

## Infrastructure

- [ ] Synthesis flow (target FPGA/toolchain undecided) and resource
      reports.
- [ ] A run script / Makefile so `simulation/` isn't an empty folder —
      right now every testbench has to be invoked manually.
- [ ] `paper/README.md` is currently a placeholder — nothing to write up
      until there's at least one end-to-end measured result.
