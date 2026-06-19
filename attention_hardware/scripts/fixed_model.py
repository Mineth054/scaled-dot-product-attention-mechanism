#!/usr/bin/env python3
"""Bit-accurate fixed-point model of the attention RTL.

Mirrors every quantization step of the hardware exactly (same LUT contents,
same rounding, same bit slices), so RTL output can be checked for *exact*
equality. The fp32 reference in validate.py answers "how far is the hardware
from real attention"; this model answers "does the RTL implement the intended
fixed-point algorithm bit-for-bit".
"""

import math

import numpy as np

FRAC = 4          # fractional bits of S_scaled (Q27.4)
RSHIFT = 8        # extra precision bits in the 1/sqrt(D) reciprocal
LUT_DEPTH = 16    # integer exp LUT entries

EXP_INT = [max(round(math.exp(-i) * 1024), 1) for i in range(LUT_DEPTH)]
EXP_FRAC = [round(math.exp(-f / (1 << FRAC)) * 1024) for f in range(1 << FRAC)]


def recip_sqrt(d: int) -> int:
    """round(2^(RSHIFT+FRAC) / sqrt(d)) via integer-only math.

    Mirrors the elaboration-time constant function in src/scale_unit.v.
    """
    target = (1 << (2 * (RSHIFT + FRAC))) // d
    r = 0
    while (r + 1) * (r + 1) <= target:
        r += 1
    if r * r + r < target:
        r += 1
    return r


def attention_fixed(X, WQ, WK, WV):
    """Run the exact fixed-point pipeline. Inputs are int arrays.

    Returns (O, A, S_scaled) where O is the integer output (x256 scale),
    A the Q.8 attention weights, S_scaled the Q27.4 scaled scores.
    """
    X = np.asarray(X, dtype=object)
    WQ = np.asarray(WQ, dtype=object)
    WK = np.asarray(WK, dtype=object)
    WV = np.asarray(WV, dtype=object)
    n, d = X.shape

    Q = X @ WQ
    K = X @ WK
    V = X @ WV
    S = Q @ K.T

    # scale_unit: (S * RECIP + 2^(RSHIFT-1)) >>> RSHIFT
    # Python's >> on negative ints floors, matching Verilog >>>.
    recip = recip_sqrt(d)
    S_scaled = (S * recip + (1 << (RSHIFT - 1))) >> RSHIFT

    A = np.zeros((n, n), dtype=object)
    for i in range(n):
        row = S_scaled[i]
        m = max(row)
        exps = []
        for s in row:
            nd = int(m - s)                      # always >= 0
            ii = min(nd >> FRAC, LUT_DEPTH - 1)  # clamp like lut_index
            ff = nd & ((1 << FRAC) - 1)
            exps.append((EXP_INT[ii] * EXP_FRAC[ff] + (1 << 9)) >> 10)
        row_sum = sum(exps)
        rcp = (1 << 20) // row_sum
        for j, e in enumerate(exps):
            A[i][j] = (e * rcp + (1 << 11)) >> 12

    O = A @ V
    return (np.array(O.tolist(), dtype=np.int64),
            np.array(A.tolist(), dtype=np.int64),
            np.array(S_scaled.tolist(), dtype=np.int64))


def attention_fp32(X, WQ, WK, WV):
    """fp32 reference; returns the real-valued output O."""
    X = np.asarray(X, dtype=float)
    Q = X @ np.asarray(WQ, dtype=float)
    K = X @ np.asarray(WK, dtype=float)
    V = X @ np.asarray(WV, dtype=float)
    scores = Q @ K.T / math.sqrt(X.shape[1])
    e = np.exp(scores - scores.max(axis=1, keepdims=True))
    A = e / e.sum(axis=1, keepdims=True)
    return A @ V
