import numpy as np
import os
import sys

os.chdir(os.path.dirname(os.path.abspath(__file__)))

def load_matrix(filename, rows, cols, signed=True):
    vals = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                v = int(line, 16)
                if signed and v > 127:
                    v -= 256
                vals.append(v)
    return np.array(vals, dtype=float).reshape(rows, cols)

X  = load_matrix("data/X.txt",  3, 4)
WQ = load_matrix("data/WQ.txt", 4, 4)
WK = load_matrix("data/WK.txt", 4, 4)
WV = load_matrix("data/WV.txt", 4, 4)

def softmax(x):
    e_x = np.exp(x - np.max(x, axis=1, keepdims=True))
    return e_x / e_x.sum(axis=1, keepdims=True)

Q = X @ WQ
K = X @ WK
V = X @ WV

d_k = Q.shape[1]
scores = Q @ K.T
scaled = scores / np.sqrt(d_k)
A = softmax(scaled)
O_expected = A @ V

print("=== Python Golden Model Output ===")
print(np.round(O_expected, 4))

O_hardware = []
with open("data/output.txt", 'r') as f:
    for line in f:
        line = line.strip()
        if line:
            row = [int(x)/256.0 for x in line.split()]
            O_hardware.append(row)

O_hardware = np.array(O_hardware)

print("\n=== Hardware Output ===")
print(np.round(O_hardware, 4))

diff = np.abs(O_expected - O_hardware)
max_error = np.max(diff)
avg_error = np.mean(diff)

print("\n=== Comparison ===")
print(f"Max error:  {max_error:.4f}")
print(f"Avg error:  {avg_error:.4f}")

# A carries +/-1 LSB (1/256) quantization error per attention weight, so
# the output error budget is proportional to the output scale: a fixed
# absolute floor plus a percentage of max|O_expected|.
THRESHOLD_ABS = 0.02
THRESHOLD_PCT = 0.02
tol = THRESHOLD_ABS + THRESHOLD_PCT * np.max(np.abs(O_expected))
passed = max_error <= tol
if passed:
    print(f"\n PASS - max error {max_error:.4f} within tol {tol:.4f} "
          f"({THRESHOLD_ABS} + {THRESHOLD_PCT*100:.0f}% of max|O|)")
else:
    print(f"\n FAIL - max error {max_error:.4f} exceeds tol {tol:.4f}")

print("\n=== Per Element Error ===")
N, D = O_expected.shape
for r in range(N):
    for c in range(D):
        exp = O_expected[r][c]
        got = O_hardware[r][c]
        err = abs(exp - got)
        status = "PASS" if err <= tol else "FAIL"
        print(f"O[{r}][{c}]: expected={exp:.4f}  got={got:.4f}  "
              f"err={err:.4f}  {status}")

sys.exit(0 if passed else 1)
