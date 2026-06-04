# Design Notes

This document is the long-form companion to [`README.md`](README.md). It covers:

1. [A fully worked numerical example](#1-worked-numerical-example) — one row of attention by hand, end-to-end.
2. [The fixed-point format chain](#2-fixed-point-format-chain) — Q-format at every signal.
3. [Softmax design justification](#3-softmax-design-justification) — why LUT-based, error budget.
4. [Cycle-latency analysis](#4-cycle-latency-analysis) — per-stage cost.
5. [Trade-off matrix](#5-trade-off-matrix) — choices that were made and what they cost.
6. [Future work](#6-future-work) — what the next iteration would add.

---

## 1. Worked numerical example

The committed inputs in `data/*.txt` give a small, hand-verifiable case for `N=3, D=4`. All values are signed 8-bit integers stored as hex (`ff` = -1).

```
X  = [[ 1,  0,  1,  0],
      [ 0,  1,  0,  1],
      [ 1,  1,  0,  0]]

WQ = [[ 1,  0,  1,  0],          WK = [[ 0,  1,  0,  1],          WV = [[ 1,  0,  0,  1],
      [ 0,  1,  0,  1],                [ 1,  0,  1,  0],                [ 0,  1,  1,  0],
      [ 1,  0, -1,  0],                [ 0, -1,  0,  1],                [ 1,  0,  0, -1],
      [ 0,  1,  0, -1]]                [ 1,  0, -1,  0]]                [ 0,  1, -1,  0]]
```

### Projection (matrix_multiply ×3)

```
Q[0] = X[0] · WQ = [1,0,1,0] · WQ = [ 2,  0,  0,  0]
K[0] = X[0] · WK = [0, 0, 0, 2]    V[0] = X[0] · WV = [ 2,  0,  0,  0]
K[1] = X[1] · WK = [2, 0, 0, 0]    V[1] = X[1] · WV = [ 0,  2,  0,  0]
K[2] = X[2] · WK = [1, 1, 1, 1]    V[2] = X[2] · WV = [ 1,  1,  1,  1]
```

### Scores (score_unit)

```
S[0][0] = Q[0]·K[0] = [2,0,0,0]·[0,0,0,2] = 0
S[0][1] = Q[0]·K[1] = [2,0,0,0]·[2,0,0,0] = 4
S[0][2] = Q[0]·K[2] = [2,0,0,0]·[1,1,1,1] = 2
```

### Scale (scale_unit, `>>> 1` for √dₖ = √4 = 2)

```
S_scaled[0] = [0, 2, 1]
```

### Softmax — Python reference

```
max(S_scaled[0]) = 2
diff             = [-2, 0, -1]
exp(diff)        = [0.1353, 1.0000, 0.3679]
sum              = 1.5032
softmax          = [0.0900, 0.6652, 0.2447]
```

### Softmax — Hardware (the LUT pipeline)

```
diff            = [-2, 0, -1]
−diff           = [ 2, 0, 1]                  // indices into exp_lut
exp_lut         = [139, 1024, 377]            // Q6.10
row_sum         = 1540                        // 12-bit, exact (max would be 3072 at N=3)
recip_lut[1540] = floor(2^20 / 1540) = 680    // Q.20 effective

A[0][0] = 139  · 680 = 94 520   → bits[27:12] = 23
A[0][1] = 1024 · 680 = 696 320  → bits[27:12] = 170
A[0][2] = 377  · 680 = 256 360  → bits[27:12] = 62

Recovered as fractions: A[0] / 256 = [0.0898, 0.6641, 0.2422]
```

Side-by-side error: Python = `[0.0900, 0.6652, 0.2447]`, hardware = `[0.0898, 0.6641, 0.2422]`. Max absolute error = 0.0025 — under the ÷256 rounding granularity (0.0039), so this is at the quantization floor.

### Output (output_unit)

```
O[0] = A[0][0]·V[0] + A[0][1]·V[1] + A[0][2]·V[2]
     =  23·[2,0,0,0] + 170·[0,2,0,0] + 62·[1,1,1,1]
     = [46,   0,  0,  0]
     + [ 0, 340,  0,  0]
     + [62,  62, 62, 62]
     = [108, 402, 62, 62]
```

This is exactly what the hardware writes to `data/output.txt` row 0 and what the self-checking testbench compares against the golden `[109, 403, 63, 63]` (Python fp32 × 256, rounded) with `diff = 1`.

---

## 2. Fixed-point format chain

Every signal carries an implicit Q-format. The interview will probe this.

| Signal | Width | Format | Reasoning |
|---|---|---|---|
| `X`, `WQ/K/V` | signed 8 | Q7.0 | INT8-style weights/embeddings; matches common ML quantization targets. |
| `Q, K, V` | signed 16 | Q15.0 | Dot product over `D=4` of 8-bit × 8-bit. Worst case 4·127² = 64 516 → 17 bits; we trust real magnitudes are smaller. Headroom is intentionally tight to keep accumulators in a single 16-bit word. |
| `S` (scores) | signed 32 | Q31.0 | 16-bit × 16-bit · D = up to 34 bits in the absolute worst case. 32 bits is a deliberate trade — we trust upstream magnitudes from real Q/K weights are well below worst case. |
| `S_scaled` | signed 16 | Q15.0 | `S >>> 1`. Drops one LSB; for `dₖ=4` this is exact. |
| `diff = S_scaled − row_max` | signed 16 | Q15.0, always ≤ 0 | Numerical-stability subtraction; clamped at `−(LUT_DEPTH−1)`. |
| `exp_lut[d]` | unsigned 16 | **Q6.10** (e⁻ᵈ · 2¹⁰) | Max value 1024 = 1.0. 10 fractional bits give ~0.001 resolution — finer than any tail entry needs. |
| `row_sum` | unsigned `⌈log₂(N·1024+1)⌉` | Q.10 (carries the 2¹⁰ scale from exp) | At N=3: 12 bits, max 3072. Bound also indexes the reciprocal LUT directly. |
| `recip_lut[s]` | unsigned 32 | `floor(2²⁰ / s)` | Effective: when multiplied by `exp_val` (which carries 2¹⁰), the 2¹⁰ in `row_sum` cancels, leaving `prob · 2²⁰`. |
| `mul_result = exp_val · recip` | unsigned 48 | prob · 2²⁰ | `(e^d · 2¹⁰) · (2¹⁰ / Σe^d) = prob · 2²⁰` after the implicit 2¹⁰ cancellation. |
| `A[i][j] = mul_result[27:12]` | unsigned 16 | **Q.8** (prob · 256) | `prob · 2²⁰ >> 12 = prob · 2⁸`. 16-bit container easily holds the full 0..256 range. |
| `O[i][j]` | signed 32 | Q31.0 (carries A's ×256 scale) | `Σ A · V`. Max: 3 · 256 · 127 ≈ 97 k, fits in 17 bits; 32 bits gives wide headroom. |
| `data/output.txt` integers | — | × 256 of true output | `validate.py` divides by 256 to compare against fp32 reference. |

The trickiest derivation is the `[27:12]` bit-slice in `softmax_unit`; the Verilog header comment in [`src/softmax_unit.v`](src/softmax_unit.v) carries the same algebra inline.

---

## 3. Softmax design justification

### Why LUT-based?

Two reasons:

1. **`exp` is transcendental.** Implementing a true `exp` in hardware is several DSPs + iterative methods (CORDIC, Taylor + range reduction). A small ROM is a few hundred FFs, no DSPs.
2. **Division is expensive.** Building a divider for 32-bit operands costs a multi-cycle SRT/Newton-Raphson core or a large LUT. A pre-computed reciprocal LUT trades BRAM for a single multiply — which we already have from the existing `unsigned_multiplier`.

### Why subtract the row max first?

Exact same trick `numpy.softmax` uses: shifting the input so the maximum is 0 prevents `exp(large positive)` overflow. In hardware this also means **the exp LUT only needs to cover negative inputs** — we get a factor-of-2 LUT-depth saving for free.

### How the LUT is dimensioned

- **`exp_lut` depth = 16.** Covers integer `diff ∈ [0, 15]`. Beyond that, `e⁻¹⁵ ≈ 3 × 10⁻⁷`, which is below the Q6.10 LSB of 1/1024 ≈ 9.8 × 10⁻⁴, so the saturation clamp loses nothing. The clamp lives in the `lut_index` function in [`src/softmax_unit.v`](src/softmax_unit.v).
- **`recip_lut` size = `N · 1024 + 1` = 3073 entries at N=3.** Sized to the max possible `row_sum`. For larger `N`, regenerate with `scripts/gen_luts.py --n <N>`.

### Error budget (measured)

The end-to-end error from `validate.py` on the committed input:

```
Max error: 0.0049    Avg error: 0.0030
```

Where this error comes from (in descending magnitude):

1. **A's Q.8 quantization**: rounding `prob · 256` to integer ⇒ ±0.5 ULP = ±0.002 per A entry.
2. **`exp_lut` integer-`d` quantization**: e.g. `e⁻³ = 0.04979`, stored as `51/1024 = 0.04980` — only ~0.0002 absolute. Negligible.
3. **`recip_lut` floor**: at most 1 ULP in Q.20 ≈ 1 × 10⁻⁶, vanishing.
4. **S_scaled = S >> 1**: 1-LSB loss on the score. Tiny influence since softmax is shift-invariant.
5. **Output accumulator**: integer addition, no error.

The 0.005 max-error figure is dominated by source (1), the inherent ÷256 granularity of the A representation. To beat it we'd widen A to Q.10 or Q.12.

### What we're *not* doing (and why)

- **Polynomial / piecewise-linear `exp`.** Would cost more multipliers than a LUT for our `N`. Justified only when LUT size dominates area.
- **Iterative division (Newton-Raphson).** Multi-cycle, more control state, no accuracy win at our precision.
- **CORDIC `exp`.** Worth considering for larger `N` where the LUT grows. At `N=3`, the LUT wins on area.

---

## 4. Cycle-latency analysis

Measured: `vvp sim/top_sim` reports `$finish at 2705 ns` at a 10 ns clock — **271 cycles** total. Breakdown:

| Stage | Cycles | Derivation |
|---|---|---|
| `IDLE → LOAD` | 1 | start-pulse handshake |
| `LOAD` | 1 | `$readmemh` is zero-time in sim |
| `PROJ` (3 parallel `matrix_multiply`) | ≈ 62 | per-element: D=4 compute + 1 store; N·D=12 outputs → `(D+1)·N·D = 60` + handshake |
| `SCORE` (sequential `matrix_multiply`-style) | ≈ 47 | N·N=9 outputs, D-cycle accumulate + 1 store → `(D+1)·N² = 45` + handshake |
| `SCALE` | 1 | combinational shift latched in one cycle |
| `SOFTMAX` | ≈ 23 | 3 fixed + `2·N²` normalize (`NORMALIZE` + `NORM_STORE`) = `3 + 18` + handshakes |
| `OUTPUT` | ≈ 124 | per O[i][j]: 3 cycles per term (LOAD/WAIT/ACC) × N + 1 store → `(3N+1)·N·D = 120` + handshakes |
| `WRITE → DONE` | 1 | file write, zero-time in sim |

Per-stage handshake overhead (start-pulse + done propagation) costs ~1–2 cycles per stage, accounting for the residual.

The dominant cost is `OUTPUT` (≈ 46 % of total), then `PROJ` (≈ 23 %). Three obvious wins, in order of effort:

1. Collapse the `LOAD/WAIT/ACC` triad in `output_unit` to a single cycle by pre-registering operands and pipelining the multiply (saves ≈ 80 cycles).
2. Share the `score_unit` accumulator across rows via banking (saves ≈ 20 cycles).
3. Overlap `PROJ` with `LOAD` of the next batch in a streaming setup.

None of these change the observable output — they're area/throughput trades.

---

## 5. Trade-off matrix

| Decision | Chose | Alternative | Why we chose it |
|---|---|---|---|
| Number sys. | INT8 weights / INT16 intermediates | BF16, FP16, FP32 | Matches deployed ML quantization (post-training INT8). All-integer logic synthesises to LUTs/DSPs without FP cores. |
| Softmax exp | 16-entry ROM | CORDIC / polynomial | Smallest area at our `N`; LUT is one BRAM read. |
| Softmax divide | Reciprocal ROM + multiplier | Iterative divider | Single multiply, no extra FSM state. ROM cost is `N·1024` × 32-bit = 12 KB at N=3 (fits one BRAM). |
| Architecture | Sequential FSM with handshakes | Systolic / fully pipelined | Clarity over throughput; 270 cycles for `(N=3, D=4)` is fine for a proof-of-concept; pipelining is documented as future work. |
| `√dₖ` divide | Arithmetic right-shift | Multiply by reciprocal | At `dₖ=4`, `√dₖ=2` is a pure power-of-two — `>>>1` is exact. Doc'd for non-power cases. |
| Parameterisation | `N`, `D`, `LUT_DEPTH` flow through every module | Hard-code N=3 (was the previous state) | Demonstrates we understand the scaling story; lets `gen_luts.py --n N` regenerate everything consistently. |
| Verification | Self-checking RTL TB **+** fp32 NumPy ref | Either alone | Two independent checks catch different bugs: TB catches RTL regressions, `validate.py` catches Q-format drift. |

---

## 6. Future work

- **Pipeline the FSM stages.** PROJ → SCORE → OUTPUT can overlap on streaming inputs once the per-stage handshake is replaced with valid/ready. Expected 3–4× throughput.
- **Multi-head attention.** Replicate the pipeline and add a head-concat at the output stage. Q,K,V already factor naturally.
- **Causal masking.** Add a triangular mask between `score_unit` and `scale_unit` — one extra register file, no FSM change.
- **Wider `A` (Q.10 or Q.12).** Halves the quantization-floor error reported in §3 at the cost of a wider `output_unit` multiplier.
- **Replace LUT with CORDIC `exp`** if `N` grows beyond a few hundred (LUT cost scales linearly with the post-max-subtract range).
- **Auto-clear the top-level `done` flag** so the block is re-runnable without an external reset — single line of FSM logic but worth doing for any real integration.
- **Add formal property checks** (e.g. SystemVerilog assertions) on the `done` handshake invariants between FSM stages.
