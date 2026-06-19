# Design Notes

This document is the long-form companion to [`README.md`](README.md). It covers:

1. [A fully worked numerical example](#1-worked-numerical-example) — one row of attention by hand, end-to-end.
2. [The fixed-point format chain](#2-fixed-point-format-chain) — Q-format at every signal.
3. [Softmax design justification](#3-softmax-design-justification) — two-LUT exp, reciprocal divide, error budget.
4. [Cycle-latency analysis](#4-cycle-latency-analysis) — sequential vs parallel datapath, measured.
5. [Synthesis results](#5-synthesis-results) — Yosys cell counts and logic depth for both datapaths.
6. [Trade-off matrix](#6-trade-off-matrix) — choices that were made and what they cost.

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

### Scale (scale_unit)

`S_scaled = round(S · 2⁴ / √D)` in Q27.4, computed as `(S · RECIP + 128) >>> 8`
with `RECIP = round(2¹² / √D) = 2048` for `D = 4` (exact, since √4 is a power of two):

```
S_scaled[0] = [0, 32, 16]     // Q27.4 raw = real values [0, 2.0, 1.0]
```

### Softmax — Python reference

```
max(S_scaled[0]) = 2
diff             = [-2, 0, -1]
exp(diff)        = [0.1353, 1.0000, 0.3679]
sum              = 1.5032
softmax          = [0.0900, 0.6652, 0.2447]
```

### Softmax — Hardware (the two-LUT pipeline)

```
diff (Q27.4 raw) = [-32, 0, -16]
−diff            = [ 32, 0,  16]
integer part i   = −diff >> 4 = [2, 0, 1]      // index into exp_int_lut
fraction f       = −diff & 15 = [0, 0, 0]      // index into exp_frac_lut

exp = (exp_int_lut[i] · exp_frac_lut[f] + 512) >> 10     // Q1.10 · Q1.10 → Q1.10
    = [139, 1024, 377]

row_sum          = 1540                        // Q.10, max N·1024 = 3072
recip_lut[1540]  = floor(2²⁰ / 1540) = 680

A[0][0] = (139  · 680 + 2048) >> 12 = 23
A[0][1] = (1024 · 680 + 2048) >> 12 = 170
A[0][2] = (377  · 680 + 2048) >> 12 = 63

Recovered as fractions: A[0] / 256 = [0.0898, 0.6641, 0.2461]
```

Side-by-side error: Python = `[0.0900, 0.6652, 0.2447]`, hardware = `[0.0898, 0.6641, 0.2461]`. Max absolute error = 0.0014 — under the ÷256 rounding granularity (0.0039), i.e. at the quantization floor of the A representation.

### Output (output_unit)

```
O[0] = A[0][0]·V[0] + A[0][1]·V[1] + A[0][2]·V[2]
     =  23·[2,0,0,0] + 170·[0,2,0,0] + 63·[1,1,1,1]
     = [109, 403, 63, 63]
```

The fp32 golden (Python × 256, rounded) is `[109, 403, 63, 63]` — the hardware row is **bit-identical** on this vector.

---

## 2. Fixed-point format chain

Every signal carries an implicit Q-format.

| Signal | Width | Format | Reasoning |
|---|---|---|---|
| `X`, `WQ/K/V` | signed 8 | Q7.0 | INT8-style weights/embeddings; matches common ML quantization targets. |
| `Q, K, V` | signed 16 | Q15.0 | Dot product over `D` of 8-bit × 8-bit terms. Provably overflow-free for inputs in `[-16, 15]` up to `D=8` (max `8·16·16 = 2048`); full-range INT8 inputs rely on realistic magnitudes (documented input contract). |
| `S` (scores) | signed 32 | Q31.0 | 16-bit × 16-bit · D; overflow-free for the same input contract (max `8·2048² ≈ 2²⁵`). |
| `S_scaled` | signed 32 | **Q27.4** | `round(S·2⁴/√D)` via `RECIP = round(2¹²/√D)` then `>>> 8` with rounding. 4 fractional bits give the softmax 1/16-resolution exponents. 32-bit so no realistic score can overflow it. |
| `diff = S_scaled − row_max` | signed 32 | Q27.4, always ≤ 0 | Numerical-stability subtraction; integer part clamps at `LUT_DEPTH−1 = 15`. |
| `exp_int_lut[i]` | unsigned 16 | Q1.10 (`e⁻ⁱ`·2¹⁰) | 16 entries, `i ∈ [0,15]`. `e⁻¹⁵ ≈ 3·10⁻⁷` is below the Q.10 LSB, so the clamp loses nothing. |
| `exp_frac_lut[f]` | unsigned 16 | Q1.10 (`e^(−f/16)`·2¹⁰) | 16 entries covering one integer step; combined as `e^−(i+f) = e⁻ⁱ·e⁻ᶠ`. |
| `exp = (int·frac + 2⁹) >> 10` | unsigned 16 | Q1.10 | Rounded product of the two LUT reads; max 1024 = 1.0. |
| `row_sum` | unsigned `⌈log₂(N·1024+1)⌉` | Q.10 | At N=3: 12 bits, max 3072. Directly indexes the reciprocal LUT. |
| `recip_lut[s]` | unsigned 32 | `floor(2²⁰ / s)` | The 2¹⁰ in `row_sum` cancels the 2¹⁰ carried by `exp`. |
| `A = (exp·recip + 2¹¹) >> 12` | unsigned 16 | **Q.8** (prob·256) | `prob·2²⁰` rounded down to `prob·2⁸`. |
| `O` | signed 32 | Q31.0 (carries A's ×256 scale) | `Σ A·V`; `validate.py` divides by 256. |

The input contract (`|X|, |W| ≤ 16` for guaranteed-exact arithmetic at `D ≤ 8`) is exercised directly: `scripts/regress.py` drives random vectors at the contract boundary and checks the RTL against the bit-accurate model for exact equality.

---

## 3. Softmax design justification

### Why LUT-based?

1. **`exp` is transcendental.** A true `exp` in hardware costs CORDIC or polynomial evaluation (multiple multipliers + control). Two 16-entry ROMs and one multiply are far smaller at this size.
2. **Division is expensive.** A 32-bit divider is a multi-cycle SRT/Newton-Raphson core. A pre-computed reciprocal ROM trades memory for a single multiply.

### Why subtract the row max first?

The same trick `numpy` uses: shifting the input so the maximum is 0 prevents `exp(positive)` overflow. In hardware it also means **the exp path only needs negative inputs** — halving the LUT coverage requirement for free.

### Why two LUTs?

The exponent argument is Q.4 — integer part `i` and fraction `f` (sixteenths). Since
`e^−(i + f/16) = e^−i · e^−(f/16)`, one 16-entry integer LUT and one 16-entry fraction LUT plus a Q1.10×Q1.10 multiply cover the full range at 1/16 resolution. The alternatives:

- **One direct LUT over Q4.4** would need 256 entries — 8× the ROM for identical accuracy.
- **Integer-only exponents** (the obvious shortcut) quantize the argument to whole units of `e`: any two scores closer than 1.0 after scaling get *identical* attention weights. The two-LUT decomposition removes this failure mode for one extra multiply.

### LUT dimensioning

- **`exp_int_lut` depth 16**: beyond `e⁻¹⁵ ≈ 3×10⁻⁷` everything is below the Q.10 LSB (≈ 10⁻³), so the integer clamp at 15 is lossless.
- **`exp_frac_lut` is always 2⁴ = 16 entries** — set by the 4 fractional bits of `S_scaled`.
- **`recip_lut` is `N·1024 + 1` entries** (3073 at N=3) — sized to the maximum row sum. `scripts/gen_luts.py --n <N>` regenerates all three files.

### Error budget

Measured across 185 randomized regression runs (5 configurations of N, D; small-magnitude and saturating inputs): **worst-case error vs fp32 = 0.67% of the output scale**; on the committed vector, max error 0.0039 with row 0 bit-identical to the rounded fp32 golden.

Sources, in descending order:

1. **A's Q.8 quantization**: ±0.5 ULP = ±0.002 per attention weight. The dominant term; output error ≈ `Σ |V|·ΔA` is therefore proportional to the output scale — which is why both checkers gate on `tol = abs_floor + 2% · max|O_expected|` rather than a fixed absolute number.
2. **Exponent argument rounding**: `S_scaled` is rounded to 1/16, so each exp carries up to `e^(1/32) − 1 ≈ 3%` relative error; mostly common-mode (cancels in the softmax ratio).
3. **exp LUT entry rounding**: ≤ 0.5/1024 per entry. Negligible.
4. **`recip_lut` floor**: ≤ 1 ULP in Q.20. Vanishing.

### What we're *not* doing (and why)

- **Polynomial / piecewise-linear `exp`**: more multipliers than two ROMs at this size.
- **Iterative division (Newton-Raphson)**: multi-cycle, more control state, no accuracy win at Q.8 output precision.
- **More fractional bits**: 4 bits already pushes the exp-argument error below the A-quantization floor; widening A (Q.10/Q.12) would have to come first.

---

## 4. Cycle-latency analysis

The matmul-style units (`matrix_multiply`, `score_unit`, `output_unit`) implement both a
sequential datapath (one MAC, one product per cycle) and a parallel one
(`PARALLEL=1`: all D or N products of a dot product in one cycle through an adder tree).
Both are measured by the testbench (`Latency:` line) at `N=3, D=4`:

| Stage | Sequential (cycles) | Parallel (cycles) | Derivation |
|---|---|---|---|
| `PROJ` (3 parallel `matrix_multiply`) | ≈ 61 | ≈ 13 | seq `(D+1)·N·D`; par `N·D` |
| `SCORE` | ≈ 46 | ≈ 10 | seq `(D+1)·N²`; par `N²` |
| `SCALE` | 2 | 2 | constant multiply, one register stage |
| `SOFTMAX` | ≈ 31 | ≈ 31 | `2 + N²` exp + `2·N²` normalize + handshakes |
| `OUTPUT` | ≈ 49 | ≈ 13 | seq `(N+1)·N·D`; par `N·D` |
| handshakes / done | ≈ 8 | ≈ 8 | one start pulse + one done cycle per stage |
| **Total (measured)** | **197** | **77** | reported by `top_level_tb` |

The parallel datapath is **2.6× faster** end-to-end; the remaining time is dominated by the softmax, whose `NORMALIZE/NORM_STORE` pair could be pipelined to one element per cycle (a further ~9-cycle saving) at the cost of a second in-flight multiply.

Each `start` is a single-cycle pulse and every FSM returns to `IDLE` after raising `done`, so back-to-back attention passes need no reset — the testbench runs the computation twice and checks the second pass is bit-identical.

---

## 5. Synthesis results

The DUT contains no file I/O (the testbench owns all of it) and synthesizes with the
open-source flow `sv2v` (SystemVerilog → Verilog-2005) + Yosys (`make synth`, `make synth_par`).
Yosys 0.66, generic gate mapping via ABC, `N=3, D=4`:

| Metric | Sequential | Parallel (`PARALLEL=1`) |
|---|---|---|
| Total cells | 20,678 | 30,948 (+50%) |
| Flip-flops | 2,120 | 1,996 |
| Longest topological path | 77 levels | 79 levels |

Notes:

- The **reciprocal ROM dominates the gate count** (3073 × 32 bits synthesized to logic in this generic flow); on an FPGA it maps to a single block RAM and the picture shifts heavily in the LUT approach's favor.
- The parallel datapath buys its 2.6× cycle reduction with +50% combinational area at
  essentially unchanged logic depth — the adder tree is shallower than the ABC-mapped
  multiplier it feeds, so cycle time is not the casualty; area is.
- `ltp` reports topological levels, not timing; a target-specific flow (e.g.
  `synth_xilinx` + STA) would be the next step for real Fmax numbers.

---

## 6. Trade-off matrix

| Decision | Chose | Alternative | Why |
|---|---|---|---|
| Number system | INT8 weights / integer intermediates, Q.4 scaled scores, Q.8 weights | BF16/FP16/FP32 | Matches post-training INT8 quantization; all-integer logic needs no FP cores. Fractional bits are introduced exactly where information is created (the 1/√d scale) and consumed (softmax). |
| Softmax exp | Two 16-entry ROMs + 1 multiply | One 256-entry ROM; CORDIC; polynomial | 8× less ROM than the direct table at identical accuracy; far smaller than CORDIC/polynomial at this size. |
| Softmax divide | Reciprocal ROM + multiplier | Iterative divider | Single multiply, no extra FSM state. ROM is `N·1024`×32 b (one BRAM at N=3). |
| `1/√dₖ` | Constant multiply by `round(2¹²/√D)`, elaboration-time integer sqrt | Hard-coded shift | Exact for power-of-4 `D` (reduces to the shift), correct for every other `D`; keeps the design honestly parameterized. |
| Multipliers | Behavioral `*` | Hand-built shift-add array | Synthesis infers DSP blocks / optimal gate multipliers; a manual array is strictly worse on every axis and obscures intent. |
| Datapath | `PARALLEL` parameter: 1 MAC (area-min) or D-wide adder tree (2.6× faster, +50% area) | Fixed choice | Both design points are implemented, measured, and regression-tested — the sequential/parallel trade-off is data, not prose. |
| Handshakes | Single-cycle start pulses; FSMs return to IDLE | Sticky start/done, reset between runs | Back-to-back passes with no reset; rerun verified bit-identical in the TB. |
| File I/O | Testbench only; DUT is pure RTL | `$readmemh` inside the DUT | Keeps `top_level` synthesizable (proved via sv2v + Yosys). LUT ROM init via `$readmemh` in `initial` remains — the standard FPGA ROM-inference idiom. |
| Verification | Self-checking TB + fp32 reference + **bit-accurate fixed-point model** + randomized regression + CI | Any subset | The fp32 model measures quantization error; the bit-accurate model catches *any* RTL deviation (exact equality, no tolerance to hide bugs); randomization covers the input contract; CI keeps it all green. |
