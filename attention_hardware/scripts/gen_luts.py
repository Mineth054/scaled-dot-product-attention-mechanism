#!/usr/bin/env python3

import argparse
import math
import os
import sys


def gen_recip(max_sum: int) -> list[int]:
    out = [0]
    for s in range(1, max_sum + 1):
        out.append((1 << 20) // s)
    return out


def gen_exp(depth: int) -> list[int]:
    out = []
    for d in range(depth):
        v = round(math.exp(-d) * 1024)
        out.append(max(v, 1))
    return out


def write_recip(path: str, vals: list[int]) -> None:
    with open(path, "w") as f:
        for v in vals:
            f.write(f"{v:08x}\n")


def emit_exp_verilog(vals: list[int]) -> str:
    lines = []
    for d, v in enumerate(vals):
        lines.append(f"        exp_lut[{d:2d}] = {v};")
    return "\n".join(lines)


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(here)

    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=3)
    parser.add_argument("--depth", type=int, default=16)
    parser.add_argument("--out-recip", default=os.path.join(repo, "data", "recip_lut.txt"))
    args = parser.parse_args()

    recip = gen_recip(args.n * 1024)
    write_recip(args.out_recip, recip)
    print(f"[gen_luts] wrote {len(recip)} reciprocal entries -> {args.out_recip}")

    exp_vals = gen_exp(args.depth)
    print(f"[gen_luts] exp_lut (paste into src/softmax_unit.v if you change LUT_DEPTH):")
    print(emit_exp_verilog(exp_vals))

    return 0


if __name__ == "__main__":
    sys.exit(main())
