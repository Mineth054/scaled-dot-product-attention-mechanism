#!/usr/bin/env python3
"""Randomized regression: RTL vs bit-accurate fixed-point model.

For each run, draws random INT8-range inputs, generates the golden vectors
and LUTs into an isolated work directory, simulates the RTL there, and
checks the hardware output for EXACT equality against fixed_model.py.
Also reports the fp32 quantization error across all runs.

Usage:
    python scripts/regress.py --runs 50
    python scripts/regress.py --runs 10 --n 4 --d 8     # parameter sweep
"""

import argparse
import math
import os
import shutil
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fixed_model import attention_fixed, attention_fp32  # noqa: E402
from gen_luts import gen_exp_int, gen_exp_frac, gen_recip  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def write_hex8(path, mat):
    with open(path, "w") as f:
        for v in np.asarray(mat).flatten():
            f.write(f"{int(v) & 0xFF:02x}\n")


def write_hex(path, vals, width):
    with open(path, "w") as f:
        for v in vals:
            f.write(f"{v:0{width}x}\n")


def write_golden(path, o_fp32):
    o_int = np.round(o_fp32 * 256).astype(np.int64)
    with open(path, "w") as f:
        for v in o_int.flatten():
            f.write(f"{int(v) & 0xFFFFFFFF:08x}\n")


def build(n, d, parallel, workdir):
    """Compile the RTL + TB for a given (N, D) into workdir/top_sim."""
    src = sorted(
        os.path.join(REPO, "src", f)
        for f in os.listdir(os.path.join(REPO, "src"))
        if f.endswith(".v")
    )
    exe = os.path.join(workdir, "top_sim")
    cmd = ["iverilog", "-g2012", f"-DN={n}", f"-DD={d}",
           f"-DPARALLEL={1 if parallel else 0}", "-o", exe,
           *src, os.path.join(REPO, "tb", "top_level_tb.v")]
    subprocess.run(cmd, check=True)
    return exe


def run_one(exe, workdir, X, WQ, WK, WV, n, d):
    data = os.path.join(workdir, "data")
    write_hex8(os.path.join(data, "X.txt"), X)
    write_hex8(os.path.join(data, "WQ.txt"), WQ)
    write_hex8(os.path.join(data, "WK.txt"), WK)
    write_hex8(os.path.join(data, "WV.txt"), WV)

    o_fp32 = attention_fp32(X, WQ, WK, WV)
    write_golden(os.path.join(data, "O_expected.txt"), o_fp32)

    r = subprocess.run(["vvp", exe], cwd=workdir, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr)
        raise RuntimeError("RTL simulation failed (testbench mismatch vs fp32 golden)")

    hw = []
    with open(os.path.join(data, "output.txt")) as f:
        for line in f:
            if line.strip():
                hw.append([int(x) for x in line.split()])
    hw = np.array(hw, dtype=np.int64)

    o_fix, _, _ = attention_fixed(X, WQ, WK, WV)
    exact = np.array_equal(hw, o_fix)
    # quantization error normalized by the output scale
    fp32_err = np.max(np.abs(hw / 256.0 - o_fp32)) / max(np.max(np.abs(o_fp32)), 1.0)
    return exact, fp32_err, hw, o_fix


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=20)
    parser.add_argument("--n", type=int, default=3)
    parser.add_argument("--d", type=int, default=4)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--range", type=int, default=16,
                        help="inputs drawn from [-range, range-1]; 16 keeps "
                             "every internal register provably overflow-free")
    parser.add_argument("--parallel", action="store_true",
                        help="build with PARALLEL=1 (one dot product per cycle)")
    parser.add_argument("--keep", action="store_true",
                        help="keep the work directory for debugging")
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)
    n, d = args.n, args.d

    workdir = os.path.join(REPO, "sim", f"regress_n{n}_d{d}")
    shutil.rmtree(workdir, ignore_errors=True)
    os.makedirs(os.path.join(workdir, "data"))
    os.makedirs(os.path.join(workdir, "sim"))

    # softmax LUTs (recip LUT size depends on N)
    data = os.path.join(workdir, "data")
    write_hex(os.path.join(data, "exp_int_lut.txt"), gen_exp_int(16), 4)
    write_hex(os.path.join(data, "exp_frac_lut.txt"), gen_exp_frac(4), 4)
    write_hex(os.path.join(data, "recip_lut.txt"), gen_recip(n * 1024), 8)

    exe = build(n, d, args.parallel, workdir)

    failures = 0
    worst_fp32 = 0.0
    for k in range(args.runs):
        X = rng.integers(-args.range, args.range, size=(n, d))
        WQ = rng.integers(-args.range, args.range, size=(d, d))
        WK = rng.integers(-args.range, args.range, size=(d, d))
        WV = rng.integers(-args.range, args.range, size=(d, d))

        exact, fp32_err, hw, o_fix = run_one(exe, workdir, X, WQ, WK, WV, n, d)
        worst_fp32 = max(worst_fp32, fp32_err)
        status = "exact" if exact else "MISMATCH"
        print(f"run {k:3d}: {status}, fp32 err {fp32_err*100:.2f}% of output scale")
        if not exact:
            failures += 1
            print("  hardware:")
            print(hw)
            print("  fixed model:")
            print(o_fix)

    print()
    print(f"=== {args.runs} runs, N={n}, D={d}, PARALLEL={int(args.parallel)}, "
          f"inputs in [-{args.range}, {args.range - 1}] ===")
    print(f"bit-exact vs fixed model: {args.runs - failures}/{args.runs}")
    print(f"worst fp32 error:         {worst_fp32*100:.2f}% of output scale")

    if not args.keep:
        shutil.rmtree(workdir, ignore_errors=True)

    if failures:
        print("FAIL")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
