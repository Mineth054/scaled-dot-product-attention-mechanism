# Scaled Dot-Product Attention — RTL Implementation

A fixed-point hardware implementation of single-head scaled dot-product attention in Verilog:

```
Attention(Q, K, V) = softmax(Q · Kᵀ / √dₖ) · V
```

Built for ArchLabX Task 26. Targets Icarus Verilog (open-source), runs an
end-to-end self-checking simulation, and is cross-validated against an fp32
NumPy reference. Max error vs floating-point: **0.0049**.

---

## Architecture

Five pipeline stages orchestrated by a top-level FSM:

<img width="1169" height="1600" alt="WhatsApp Image 2026-06-08 at 14 57 20" src="https://github.com/user-attachments/assets/71a3cdb4-2031-457e-9338-b704db2f0075" />


## Fixed-Point Format Chain

| Signal | Shape | Width | Format |
|---|---|---|---|
| X, WQ, WK, WV | 3×4 / 4×4 | signed 8-bit | INT8 |
| Q, K, V | 3×4 | signed 16-bit | INT16 |
| S (scores) | 3×3 | signed 32-bit | INT32 |
| S_scaled | 3×3 | signed 16-bit | INT16 |
| A (attention weights) | 3×3 | unsigned 16-bit | prob × 256 |
| O (output) | 3×4 | signed 32-bit | INT32 × 256 |

`validate.py` divides hardware output by 256 to recover true fp32 values.

---

## Repository Layout

```
attention_hardware/
├── src/                 RTL modules (Verilog-2001/2012)
│   ├── top_level.v          9-state FSM orchestrator
│   ├── projection_unit.v    3× parallel Q, K, V projection
│   ├── matrix_multiply.v    sequential dot-product MAC
│   ├── score_unit.v         Q · Kᵀ
│   ├── scale_unit.v         arithmetic right-shift ÷ √dₖ
│   ├── softmax_unit.v       max-subtract + exp LUT + reciprocal LUT
│   ├── output_unit.v        A · V weighted sum
│   ├── multiplier.v         parameterized signed multiplier
│   └── unsigned_multiplier.v  16×32 unsigned (softmax normalize)
├── tb/                  Testbenches — one per module + integration
├── data/                X, WQ, WK, WV inputs · LUTs · golden output
├── scripts/
│   ├── gen_luts.py          regenerate recip_lut.txt
│   └── gen_golden.py        regenerate O_expected.txt from fp32 reference
├── validate.py          fp32 NumPy reference vs hardware output
├── Makefile             build / run / validate
└── run.ps1              Windows equivalent (no GNU make required)
```

---

## Build & Run

### Prerequisites
- Icarus Verilog ≥ 11 (`iverilog`, `vvp`)
- Python ≥ 3.9 with NumPy

### One command

```bash
make test
```

On Windows (no GNU make):

```powershell
.\run.ps1
```

### Step by step

```bash
make build      # compile RTL → sim/top_sim
make run        # simulate → data/output.txt + sim/attention.vcd
make validate   # compare against fp32 golden
make luts       # regenerate LUTs (if N or D changes)
make wave       # open waveform in GTKWave
make clean      # remove build artefacts
```

Per-module testbenches:

```bash
make mac_sim mul_sim mm_sim proj_sim score_sim scale_sim softmax_sim out_sim
```

---

## Expected Output

```
=== Attention RTL output vs golden (tolerance = +/-32 raw units) ===
  O[0][0]: got=108 expected=109 diff=1  PASS
  O[0][1]: got=402 expected=403 diff=1  PASS
  ...
=== PASS: all 12 outputs within tolerance ===

=== Comparison ===
Max error:  0.0049
Avg error:  0.0030
 PASS - all values within 5% of golden model
```

---

## Design Decisions

| Decision | Chosen | Why |
|---|---|---|
| Number system | INT8 weights, INT16/32 intermediates | Matches ML quantization targets; all-integer logic, no FP cores |
| Softmax exp | 16-entry ROM (e⁻ᵈ × 1024) | Smallest area at N=3; one BRAM read vs. CORDIC/polynomial |
| Softmax divide | Reciprocal ROM + multiply | Single multiply, no iterative divider or extra FSM state |
| √dₖ scaling | Arithmetic right-shift by 1 | Exact for dₖ=4 (√4=2); one cycle, no multiplier needed |
| Architecture | Sequential FSM | Clarity over throughput for proof-of-concept; pipeline documented as future work |

Full derivations, Q-format analysis, cycle-latency breakdown, and softmax error budget: see [`DESIGN.md`](attention_hardware/DESIGN.md).

---

## Verification

Two independent layers:

1. **Self-checking RTL testbench** — reads golden output via `$readmemh`, prints PASS/FAIL per element, exits non-zero on failure.
2. **fp32 NumPy reference** (`validate.py`) — recomputes attention in floating point, compares against hardware output ÷ 256. Tolerance: abs < 0.125 or rel < 1%.

Total: **270 cycles** at 10 ns clock period (2705 ns simulated) for N=3, D=4.
