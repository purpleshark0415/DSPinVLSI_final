import numpy as np

# =====================================================================
# 1. 硬體參數與 17-bit 2補數溢位處理 (Q6.11)
# =====================================================================
TOTAL_BITS = 17
FRAC_BITS = 11
INT_BITS = 6
STAGES = 10
S_FRAC_BITS = 14
ITERATIONS = 7

MAX_VAL = (1 << (TOTAL_BITS - 1)) - 1
MIN_VAL = -(1 << (TOTAL_BITS - 1))
MASK = (1 << TOTAL_BITS) - 1


def to_int18(val):
    val = int(val) & MASK
    if val > MAX_VAL:
        val -= (1 << TOTAL_BITS)
    return val


def shift_and_round(val, shift_amt):
    if shift_amt <= 0:
        return val << (-shift_amt)
    rounding_add = 1 << (shift_amt - 1)
    return (val + rounding_add) >> shift_amt


def get_scaling_factor_csd(stages, s_frac_bits):
    ideal_K = np.prod([1.0 / np.sqrt(1 + 2 ** (-2 * i)) for i in range(stages)])
    n_val = int(np.round(ideal_K * (2 ** s_frac_bits)))
    csd = []
    temp_n = n_val
    while temp_n > 0:
        if temp_n % 2 == 0:
            csd.append(0)
            temp_n //= 2
        else:
            lookahead = (temp_n // 2) % 2
            if lookahead == 1:
                csd.append(-1)
                temp_n = (temp_n // 2) + 1
            else:
                csd.append(1)
                temp_n //= 2
    ideal = ideal_K
    csd_value = sum(b * (2 ** (i - s_frac_bits)) for i, b in enumerate(csd))
    return csd, sum(1 for b in csd if b != 0) - 1, csd_value / ideal


def apply_csd_int18(val, csd_array, s_frac_bits):
    result = 0
    for i, bit in enumerate(csd_array):
        if bit != 0:
            shift_amt = s_frac_bits - i
            shifted_val = shift_and_round(val, shift_amt)
            if bit == 1:
                result = to_int18(result + shifted_val)
            elif bit == -1:
                result = to_int18(result - shifted_val)
    return result


def cordic_vectoring_int18(x, y, stages, csd_array, s_frac_bits):
    x = to_int18(x)
    y = to_int18(y)
    d_list = []
    for i in range(stages):
        d = 1 if y < 0 else -1
        d_list.append(d)
        x_shifted = shift_and_round(x, i)
        y_shifted = shift_and_round(y, i)
        if d == 1:
            x_next = to_int18(x - y_shifted)
            y_next = to_int18(y + x_shifted)
        else:
            x_next = to_int18(x + y_shifted)
            y_next = to_int18(y - x_shifted)
        x, y = x_next, y_next
    x_scaled = apply_csd_int18(x, csd_array, s_frac_bits)
    y_scaled = apply_csd_int18(y, csd_array, s_frac_bits)
    return x_scaled, y_scaled, d_list


def cordic_rotation_int18(x, y, d_list, csd_array, s_frac_bits):
    x = to_int18(x)
    y = to_int18(y)
    for i, d in enumerate(d_list):
        x_shifted = shift_and_round(x, i)
        y_shifted = shift_and_round(y, i)
        if d == 1:
            x_next = to_int18(x - y_shifted)
            y_next = to_int18(y + x_shifted)
        else:
            x_next = to_int18(x + y_shifted)
            y_next = to_int18(y - x_shifted)
        x, y = x_next, y_next
    x_scaled = apply_csd_int18(x, csd_array, s_frac_bits)
    y_scaled = apply_csd_int18(y, csd_array, s_frac_bits)
    return x_scaled, y_scaled


def systolic_iteration_int18(T, U, stages, csd_array, s_frac_bits):
    R = np.zeros((3, 3), dtype=int)
    for i in range(3):
        for j in range(3):
            R[i, j] = T[i, j]

    R[0, 0], R[1, 0], d1 = cordic_vectoring_int18(
        R[0, 0], R[1, 0], stages, csd_array, s_frac_bits
    )
    for j in range(1, 3):
        R[0, j], R[1, j] = cordic_rotation_int18(
            R[0, j], R[1, j], d1, csd_array, s_frac_bits
        )

    R[0, 0], R[2, 0], d2 = cordic_vectoring_int18(
        R[0, 0], R[2, 0], stages, csd_array, s_frac_bits
    )
    for j in range(1, 3):
        R[0, j], R[2, j] = cordic_rotation_int18(
            R[0, j], R[2, j], d2, csd_array, s_frac_bits
        )

    R[1, 1], R[2, 1], d3 = cordic_vectoring_int18(
        R[1, 1], R[2, 1], stages, csd_array, s_frac_bits
    )
    for j in range(2, 3):
        R[1, j], R[2, j] = cordic_rotation_int18(
            R[1, j], R[2, j], d3, csd_array, s_frac_bits
        )

    R[1, 0] = R[2, 0] = R[2, 1] = 0

    T_next_T = np.zeros((3, 3), dtype=int)
    U_next_T = np.zeros((3, 3), dtype=int)
    for i in range(3):
        for j in range(3):
            T_next_T[i, j] = R[j, i]
            U_next_T[i, j] = U[j, i]

    for j in range(3):
        T_next_T[0, j], T_next_T[1, j] = cordic_rotation_int18(
            T_next_T[0, j], T_next_T[1, j], d1, csd_array, s_frac_bits
        )
        U_next_T[0, j], U_next_T[1, j] = cordic_rotation_int18(
            U_next_T[0, j], U_next_T[1, j], d1, csd_array, s_frac_bits
        )

    for j in range(3):
        T_next_T[0, j], T_next_T[2, j] = cordic_rotation_int18(
            T_next_T[0, j], T_next_T[2, j], d2, csd_array, s_frac_bits
        )
        U_next_T[0, j], U_next_T[2, j] = cordic_rotation_int18(
            U_next_T[0, j], U_next_T[2, j], d2, csd_array, s_frac_bits
        )

    for j in range(3):
        T_next_T[1, j], T_next_T[2, j] = cordic_rotation_int18(
            T_next_T[1, j], T_next_T[2, j], d3, csd_array, s_frac_bits
        )
        U_next_T[1, j], U_next_T[2, j] = cordic_rotation_int18(
            U_next_T[1, j], U_next_T[2, j], d3, csd_array, s_frac_bits
        )

    T_out = np.zeros((3, 3), dtype=int)
    U_out = np.zeros((3, 3), dtype=int)
    for i in range(3):
        for j in range(3):
            T_out[i, j] = T_next_T[j, i]
            U_out[i, j] = U_next_T[j, i]

    T_out[0, 1] = T_out[1, 0]
    T_out[0, 2] = T_out[2, 0]
    T_out[1, 2] = T_out[2, 1]
    return T_out, U_out


csd_array, num_adders, _ = get_scaling_factor_csd(STAGES, S_FRAC_BITS)

# Matrix 8 @ Q6.12 — from 00_TESTBED/input.txt after regeneration
A_int = np.array(
    [
        [1990, 1890, -3112],
        [1890, 4725, 5324],
        [-3112, 5324, 28281],
    ],
    dtype=int,
)

FIX_ONE = 1 << FRAC_BITS
T_int = A_int.copy()
U_int = np.zeros((3, 3), dtype=int)
U_int[0, 0] = FIX_ONE
U_int[1, 1] = FIX_ONE
U_int[2, 2] = FIX_ONE

for _ in range(ITERATIONS):
    T_int, U_int = systolic_iteration_int18(
        T_int, U_int, STAGES, csd_array, S_FRAC_BITS
    )

print("=== Python Bit-True Output (Q6.11) ===")
print(f"Eigenvalues: {T_int[0, 0]}, {T_int[1, 1]}, {T_int[2, 2]}")
print("Eigenvectors (rows):")
print(f"Row 0: {U_int[0, 0]}, {U_int[0, 1]}, {U_int[0, 2]}")
print(f"Row 1: {U_int[1, 0]}, {U_int[1, 1]}, {U_int[1, 2]}")
print(f"Row 2: {U_int[2, 0]}, {U_int[2, 1]}, {U_int[2, 2]}")
print("Eigenvectors (RTL columns):")
for col in range(3):
    print(
        f"Col {col}: {U_int[0, col]}, {U_int[1, col]}, {U_int[2, col]}"
    )
