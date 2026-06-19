# attention_hardware

A fixed-point Verilog implementation of single-head scaled dot-product attention:

```
Attention(Q, K, V) = softmax(Q · Kᵀ / √dₖ) · V
```

Built for the ArchLabX task 26 brief. Targets Icarus Verilog (open-source), runs an end-to-end self-checking simulation, is cross-validated against **both** an fp32 NumPy reference and a **bit-accurate fixed-point model** (exact-equality check, randomized regression), and synthesizes with the open-source sv2v + Yosys flow.

See [`DESIGN.md`](DESIGN.md) for the Q-format derivation, numerical worked example, softmax justification, measured latency/area trade-offs, and synthesis results.

---

## Architecture

```
   tb/top_level_tb.v ── owns ALL file I/O ($readmemh in, $fwrite out)
        │  X, WQ, WK, WV (ports)
        ▼
   ┌──────────────────────── top_level FSM (synthesizable) ────────────────────┐
   │      IDLE → PROJ → SCORE → SCALE → SOFTMAX → OUTPUT → DONE → IDLE        │
   │      (single-cycle start pulses; back-to-back runs need no reset)        │
   └───────────────────────────────────────────────────────────────────────────┘

   projection_unit ──► Q,K,V   (N×D, signed Q15.0)     3× matrix_multiply
        │
   score_unit      ──► S = Q·Kᵀ        (N×N, signed Q31.0)
        │
   scale_unit      ──► S_scaled = round(S·2⁴/√dₖ)      (signed Q27.4)
        │              constant mult by round(2¹²/√D), any D
   softmax_unit    ──► A = softmax(S_scaled)           (unsigned Q.8, prob×256)
        │              e^-(i+f) = exp_int_lut[i] · exp_frac_lut[f]  (two Q1.10 ROMs)
        │              divide via recip ROM: floor(2²⁰/Σ)
   output_unit     ──► O = A·V                         (signed 32-bit, ×256)
        │
        ▼
   data/output.txt   +   sim/attention.vcd
```

The matmul-style units implement **two datapaths** selected by the `PARALLEL` parameter: sequential (one MAC, area-minimal) and parallel (full dot product per cycle through an adder tree). Measured at `N=3, D=4`: **197 cycles sequential, 77 cycles parallel** (2.6×, +50% cell area — see [`DESIGN.md`](DESIGN.md#5-synthesis-results)).

---

## Repository layout

```
attention_hardware/
├── src/                 RTL (synthesizable; no file I/O)
│   ├── top_level.v          FSM orchestrator, data in/out via ports
│   ├── projection_unit.v    3× parallel Q,K,V projection
│   ├── matrix_multiply.v    X·W (sequential MAC or PARALLEL adder tree)
│   ├── score_unit.v         Q·Kᵀ (same two datapaths)
│   ├── scale_unit.v         ×round(2¹²/√D) — elaboration-time integer sqrt
│   ├── softmax_unit.v       max-subtract + two-LUT exp + reciprocal LUT
│   └── output_unit.v        A·V weighted sum (same two datapaths)
├── tb/                  Self-checking testbenches (one per module + integration)
├── data/                Inputs (X, WQ/WK/WV), LUTs, golden vector, output
├── scripts/
│   ├── gen_luts.py          regenerate the three softmax LUT files
│   ├── gen_golden.py        regenerate data/O_expected.txt (fp32 reference)
│   ├── fixed_model.py       bit-accurate Python model of the RTL
│   └── regress.py           randomized regression: RTL vs model, exact match
├── validate.py          fp32 NumPy reference vs hardware output
├── Makefile             build / run / validate / regress / synth
├── run.ps1              Windows equivalent (no GNU make required)
└── DESIGN.md            full design walkthrough
```

CI (`.github/workflows/ci.yml`) runs the full flow on every push: end-to-end test, randomized regression across five (N, D) configurations plus the parallel datapath, Verilator lint, and Yosys synthesis of both datapaths.

---

## Build & run

### Prerequisites
- **Icarus Verilog ≥ 11** (`iverilog`, `vvp`)
- **Python ≥ 3.9** with **NumPy**
- *(optional)* **sv2v** + **yowasp-yosys** (`pip install yowasp-yosys`) for `make synth`
- *(optional)* GTKWave for `sim/attention.vcd`, GNU `make`

### One command

```bash
make test          # build + run + validate
```

On Windows without GNU make:

```powershell
.\run.ps1          # equivalent
```

### All targets

```bash
make build         # iverilog → sim/top_sim
make run           # vvp sim/top_sim → data/output.txt + sim/attention.vcd
make validate      # python validate.py against the fp32 reference
make regress       # randomized regression vs the bit-accurate model (seq + parallel)
make synth         # sv2v + Yosys: cell counts + logic depth (sequential)
make synth_par     # same for the PARALLEL=1 datapath
make luts          # regenerate LUT files + golden vector
make wave          # gtkwave sim/attention.vcd
make clean         # remove sim binaries + generated output
```

Per-module testbenches: `make mm_sim proj_sim score_sim scale_sim softmax_sim out_sim`

Compile-time configuration (testbench defines): `iverilog -g2012 -DN=4 -DD=8 -DPARALLEL=1 ...`, or `python scripts/regress.py --n 4 --d 8 --parallel`.

---

## Expected output

`vvp sim/top_sim` runs the self-checking testbench in [`tb/top_level_tb.v`](tb/top_level_tb.v): it loads the inputs, runs the attention pass **twice back-to-back** (verifying no-reset reruns are bit-identical), reports latency, and compares against [`data/O_expected.txt`](data/O_expected.txt). The tolerance is scale-proportional — `32 + 2% of max|O_expected|` raw units — because A's ±1 LSB (1/256) quantization error multiplies V, making output error proportional to output magnitude.

```
=== Attention RTL output vs golden (tol = 32 + 2% of max|O| = 40) ===
  O[0][0]: got=109 expected=109 diff=0  PASS
  ...
Latency: 197 cycles (N=3, D=4, PARALLEL=0)
=== PASS: all 12 outputs within tolerance, rerun bit-identical ===
```

`python validate.py` checks the same output in normalized fp32 space:

```
Max error:  0.0039
 PASS - max error 0.0039 within tol 0.0515 (0.02 + 2% of max|O|)
```

`python scripts/regress.py --runs 20 --range 3` drives random inputs and requires the RTL to match the bit-accurate model **exactly**:

```
run   0: exact, fp32 err 0.08% of output scale
...
bit-exact vs fixed model: 20/20
PASS
```

---

## Module reference

| Module | Parameters | Purpose | Latency (cycles, seq / par) |
|---|---|---|---|
| `top_level` | `N, D, PARALLEL` | 7-state FSM; one start pulse per pass, no reset between runs | 197 / 77 measured |
| `projection_unit` | `N, D, PARALLEL` | 3 parallel `matrix_multiply` for Q, K, V | `(D+1)·N·D` / `N·D` |
| `matrix_multiply` | `N, D, PARALLEL` | X·W; sequential MAC or D-wide adder tree | `(D+1)·N·D` / `N·D` |
| `score_unit` | `N, D, PARALLEL` | `Q·Kᵀ` | `(D+1)·N²` / `N²` |
| `scale_unit` | `N, D, FRAC, RSHIFT` | `round(S·2⁴/√D)`, constant multiply | 1 |
| `softmax_unit` | `N, FRAC, LUT_DEPTH` | max-subtract, two-LUT exp, reciprocal LUT, rounded normalize | `2 + 3·N²` |
| `output_unit` | `N, D, PARALLEL` | `A·V` | `(N+1)·N·D` / `N·D` |

---

## Verification approach

Three independent layers, all wired into `make`/CI:

1. **Self-checking RTL testbench** ([`tb/top_level_tb.v`](tb/top_level_tb.v)): golden-vector compare with scale-proportional tolerance, latency report, bit-identical rerun check. Exits non-zero on failure. Every per-module testbench in `tb/` is also self-checking (`$fatal` on mismatch).
2. **Bit-accurate fixed-point model** ([`scripts/fixed_model.py`](scripts/fixed_model.py)) + **randomized regression** ([`scripts/regress.py`](scripts/regress.py)): mirrors every LUT, rounding and bit-slice of the RTL, so hardware output is checked for *exact equality* — no tolerance to hide bugs. 185 randomized runs across `(N,D) ∈ {(3,4),(4,8),(8,8),(6,5)}`, both datapaths, small-magnitude and saturating inputs: all bit-exact; worst fp32 quantization error 0.67% of output scale.
3. **fp32 NumPy reference** ([`validate.py`](validate.py)): quantifies the fixed-point error against real attention.

---

## Notes on the design

- **Fixed-point throughout**: INT8 inputs, integer projections/scores, Q27.4 scaled scores, Q.8 attention weights. The fractional bits are introduced exactly where the math creates them (the 1/√dₖ scale) — see the format chain in [`DESIGN.md`](DESIGN.md#2-fixed-point-format-chain).
- **Softmax**: max-subtraction for stability, `e^-(i+f) = e⁻ⁱ·e⁻ᶠ` via two 16-entry Q1.10 ROMs and one multiply (1/16-resolution exponents), reciprocal-ROM divide, round-to-nearest at every truncation.
- **Parameterized and proved**: `N`, `D`, `PARALLEL` flow through every module; CI regression-tests five (N, D) configurations including non-power-of-two.
- **Synthesizable**: the DUT has no file I/O; `make synth` runs sv2v + Yosys and reports cell counts and logic depth for both datapaths ([`DESIGN.md`](DESIGN.md#5-synthesis-results)).
