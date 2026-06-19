#!/usr/bin/env python3
"""Generate the three softmax LUT files read by src/softmax_unit.v.

  exp_int_lut.txt   e^-i        * 1024   for integer i in [0, depth)
  exp_frac_lut.txt  e^-(f/2^F)  * 1024   for fraction f in [0, 2^F)
  recip_lut.txt     floor(2^20 / s)      for row sums s in [0, N*1024]

The exponent argument arrives in Q11.4 (F=4 fractional bits); the unit
splits it as e^-(i+f) = e^-i * e^-f with one multiply between the LUTs.
"""

import argparse
import math
import os
import sys


def gen_exp_int(depth: int) -> list[int]:
    # clamp to >=1 so the saturated tail stays monotonically nonzero
    return [max(round(math.exp(-d) * 1024), 1) for d in range(depth)]


def gen_exp_frac(frac_bits: int) -> list[int]:
    step = 1.0 / (1 << frac_bits)
    return [round(math.exp(-f * step) * 1024) for f in range(1 << frac_bits)]


def gen_recip(max_sum: int) -> list[int]:
    return [0] + [(1 << 20) // s for s in range(1, max_sum + 1)]


def write_hex(path: str, vals: list[int], width: int) -> None:
    with open(path, "w") as f:
        for v in vals:
            f.write(f"{v:0{width}x}\n")
    print(f"[gen_luts] wrote {len(vals)} entries -> {path}")


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    data = os.path.join(os.path.dirname(here), "data")

    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=3, help="sequence length N")
    parser.add_argument("--depth", type=int, default=16, help="integer exp LUT depth")
    parser.add_argument("--frac-bits", type=int, default=4, help="fractional bits of the exponent")
    parser.add_argument("--out-dir", default=data)
    args = parser.parse_args()

    write_hex(os.path.join(args.out_dir, "exp_int_lut.txt"), gen_exp_int(args.depth), 4)
    write_hex(os.path.join(args.out_dir, "exp_frac_lut.txt"), gen_exp_frac(args.frac_bits), 4)
    write_hex(os.path.join(args.out_dir, "recip_lut.txt"), gen_recip(args.n * 1024), 8)

    return 0


if __name__ == "__main__":
    sys.exit(main())
