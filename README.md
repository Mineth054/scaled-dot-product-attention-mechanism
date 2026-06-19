# Scaled Dot-Product Attention — RTL Implementation

A fixed-point hardware implementation of single-head scaled dot-product attention in Verilog:

```
Attention(Q, K, V) = softmax(Q · Kᵀ / √dₖ) · V
```

Built for ArchLabX Task 26. Targets Icarus Verilog (open-source), runs an
end-to-end self-checking simulation, and is verified three independent ways:
a golden-vector RTL testbench, an fp32 NumPy reference, and a **bit-accurate
fixed-point model** checked for exact equality across 185 randomized
regression runs (worst fp32 quantization error: **0.67% of output scale**).
The DUT is synthesizable and comes with Yosys area/depth numbers for both of
its datapaths.

---

## Architecture

Five pipeline stages orchestrated by a synthesizable top-level FSM; all file
I/O lives in the testbench:

```
Testbench ($readmemh)
(X, WQ, WK, WV via ports)
      │
      ▼
┌─────────────────────────────────────┐
│         Projection Unit             │
│  Q = X·WQ  │  K = X·WK  │  V = X·WV │
│     (3 matrix multiplies, parallel) │
└────┬──────────────┬──────────┬──────┘
     │ Q            │ K        │ V (bypasses to output)
     └──────┬───────┘          │
            ▼                  │
      ┌───────────────────┐    │
      │  Score Unit       │    │
      │  S = Q · Kᵀ       │    │
      └──────┬────────────┘    │
             ▼                 │
      ┌───────────────────┐    │
      │  Scale Unit       │    │
      │  × round(2¹²/√D)  │    │
      └──────┬────────────┘    │
             ▼                 │
      ┌───────────────────┐    │
      │  Softmax Unit     │    │
      │  two-LUT exp +    │    │
      │  reciprocal LUT   │    │
      └──────┬────────────┘    │
             │ A               │
             └────────┬────────┘
                      ▼
               ┌────────────┐
               │Output Unit │──► output.txt (written by TB)
               │  O = A · V │
               └────────────┘
```

The matmul-style units implement **two datapaths**, selected by the `PARALLEL`
parameter: sequential (one MAC, area-minimal) and parallel (one full dot
product per cycle through an adder tree). Measured at N=3, D=4:

| Datapath | Latency | Yosys cells | Logic depth |
|---|---|---|---|
| Sequential | 197 cycles | 20,678 | 77 levels |
| Parallel | 77 cycles (2.6×) | 30,948 (+50%) | 79 levels |

---

## Fixed-Point Format Chain

| Signal | Width | Format |
|---|---|---|
| X, WQ, WK, WV | signed 8-bit | Q7.0 (INT8) |
| Q, K, V | signed 16-bit | Q15.0 |
| S (scores) | signed 32-bit | Q31.0 |
| S_scaled | signed 32-bit | **Q27.4** — round(S·2⁴/√dₖ) |
| A (attention weights) | unsigned 16-bit | Q.8 (prob × 256) |
| O (output) | signed 32-bit | ×256 of true output |

Fractional bits are introduced exactly where the math creates them (the 1/√dₖ
scale) and consumed by the softmax, whose exponent resolves 1/16 steps via
`e^-(i+f) = e⁻ⁱ · e⁻ᶠ` — two 16-entry Q1.10 ROMs and one multiply.
`validate.py` divides hardware output by 256 to recover fp32 values.

---

## Repository Layout

```
attention_hardware/
├── src/                 RTL (synthesizable; no file I/O)
│   ├── top_level.v          FSM orchestrator, data via ports
│   ├── projection_unit.v    3× parallel Q, K, V projection
│   ├── matrix_multiply.v    X·W (sequential MAC or PARALLEL adder tree)
│   ├── score_unit.v         Q · Kᵀ (same two datapaths)
│   ├── scale_unit.v         × round(2¹²/√D), elaboration-time integer sqrt
│   ├── softmax_unit.v       max-subtract + two-LUT exp + reciprocal LUT
│   └── output_unit.v        A · V weighted sum (same two datapaths)
├── tb/                  Self-checking testbenches — one per module + integration
├── data/                X, WQ, WK, WV inputs · LUT files · golden output
├── scripts/
│   ├── gen_luts.py          regenerate the three softmax LUT files
│   ├── gen_golden.py        regenerate O_expected.txt from fp32 reference
│   ├── fixed_model.py       bit-accurate Python model of the RTL
│   └── regress.py           randomized regression (exact-match vs model)
├── validate.py          fp32 NumPy reference vs hardware output
├── Makefile             build / run / validate / regress / synth
└── run.ps1              Windows equivalent (no GNU make required)
```

CI (`.github/workflows/ci.yml`): end-to-end test, randomized regression across
five (N, D) configurations plus the parallel datapath, Verilator lint, and
Yosys synthesis on every push.

---

## Build & Run

### Prerequisites
- Icarus Verilog ≥ 11 (`iverilog`, `vvp`)
- Python ≥ 3.9 with NumPy
- *(optional, for `make synth`)* sv2v + `pip install yowasp-yosys`

### One command

```bash
cd attention_hardware
make test
```

On Windows (no GNU make):

```powershell
cd attention_hardware
.\run.ps1
```

### Step by step

```bash
make build      # compile RTL → sim/top_sim
make run        # simulate → data/output.txt + sim/attention.vcd
make validate   # compare against fp32 reference
make regress    # randomized regression vs bit-accurate model (seq + parallel)
make synth      # sv2v + Yosys: cell counts and logic depth
make luts       # regenerate LUTs (if N or D changes)
make wave       # open waveform in GTKWave
make clean      # remove build artefacts
```

Per-module testbenches: `make mm_sim proj_sim score_sim scale_sim softmax_sim out_sim`

Other configurations: `iverilog -g2012 -DN=4 -DD=8 -DPARALLEL=1 ...` or
`python scripts/regress.py --n 4 --d 8 --parallel`.

---

## Expected Output

```
=== Attention RTL output vs golden (tol = 32 + 2% of max|O| = 40) ===
  O[0][0]: got=109 expected=109 diff=0  PASS
  ...
Latency: 197 cycles (N=3, D=4, PARALLEL=0)
=== PASS: all 12 outputs within tolerance, rerun bit-identical ===

=== Comparison ===
Max error:  0.0039
 PASS - max error 0.0039 within tol 0.0515 (0.02 + 2% of max|O|)
```

---

## Design Decisions

| Decision | Chosen | Why |
|---|---|---|
| Number system | INT8 inputs, integer intermediates, Q.4 scaled scores, Q.8 weights | Matches ML quantization targets; fractional bits exactly where information is created/consumed |
| Softmax exp | Two 16-entry ROMs + 1 multiply (`e⁻ⁱ·e⁻ᶠ`) | 1/16-resolution exponents at 8× less ROM than a direct 256-entry table |
| Softmax divide | Reciprocal ROM + multiply | Single multiply, no iterative divider or extra FSM state |
| √dₖ scaling | Constant multiply by round(2¹²/√D), computed at elaboration | Exact for power-of-4 dₖ, correct for all others — honestly parameterized |
| Datapath | `PARALLEL` parameter, both implemented and measured | The sequential/parallel trade-off is data (197 vs 77 cycles, +50% area), not prose |
| Verification | TB + fp32 reference + bit-accurate model + randomized regression + CI | Exact-equality checking leaves no tolerance for bugs to hide in |

Full derivations, Q-format analysis, cycle-latency breakdown, softmax error
budget, and synthesis results: see [`DESIGN.md`](attention_hardware/DESIGN.md).
