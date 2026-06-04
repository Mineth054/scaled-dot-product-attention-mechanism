#!/usr/bin/env python3

import argparse
import os
import sys

import numpy as np


def load_matrix(path: str, rows: int, cols: int) -> np.ndarray:
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            v = int(line, 16)
            if v > 127:
                v -= 256
            vals.append(v)
    return np.array(vals, dtype=float).reshape(rows, cols)


def softmax(x: np.ndarray) -> np.ndarray:
    e = np.exp(x - np.max(x, axis=1, keepdims=True))
    return e / e.sum(axis=1, keepdims=True)


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(here)

    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=3)
    parser.add_argument("--d", type=int, default=4)
    parser.add_argument("--scale", type=int, default=256)
    parser.add_argument("--out", default=os.path.join(repo, "data", "O_expected.txt"))
    args = parser.parse_args()

    data = os.path.join(repo, "data")
    X  = load_matrix(os.path.join(data, "X.txt"),  args.n, args.d)
    WQ = load_matrix(os.path.join(data, "WQ.txt"), args.d, args.d)
    WK = load_matrix(os.path.join(data, "WK.txt"), args.d, args.d)
    WV = load_matrix(os.path.join(data, "WV.txt"), args.d, args.d)

    Q = X @ WQ
    K = X @ WK
    V = X @ WV
    scores = Q @ K.T
    scaled = scores / np.sqrt(args.d)
    A = softmax(scaled)
    O = A @ V
    O_int = np.round(O * args.scale).astype(np.int64)

    with open(args.out, "w") as f:
        for r in range(args.n):
            for c in range(args.d):
                v = int(O_int[r, c]) & 0xFFFFFFFF
                f.write(f"{v:08x}\n")

    print(f"[gen_golden] wrote {args.n * args.d} entries -> {args.out}")
    print("Expected hardware output (scaled by 256):")
    print(O_int)
    return 0


if __name__ == "__main__":
    sys.exit(main())
