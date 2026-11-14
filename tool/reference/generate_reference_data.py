#!/usr/bin/env python3
"""Writes test/domain/reference_data.dart.

The expected values of test/domain/reference_values_test.dart do not come from
the app. This script derives them again from the definitions of the units and
with other software: Python's exact fractions, sympy (roots, matrices) and
mpmath (50-digit square roots, pi, sines).

    pip install sympy mpmath
    python3 tool/reference/generate_reference_data.py

The run is deterministic (fixed seed) and ends with `dart format`, which CI
applies to the file as well: running the script again must not change it.
"""
import random
import shutil
import subprocess
from fractions import Fraction as F
from pathlib import Path

import sympy
from mpmath import mp, mpf

mp.dps = 70
DIGITS = 45
rng = random.Random(20261113)
out = []


def dec(s):
    """Exact value of a decimal literal."""
    return F(s)


def frac(v):
    v = F(v)
    return f'{v.numerator}/{v.denominator}'


def digits(v, n=DIGITS):
    """A real number with n significant digits (never scientific notation with a sign problem)."""
    v = mpf(v) if not isinstance(v, F) else mpf(v.numerator) / mpf(v.denominator)
    return mp.nstr(v, n, strip_zeros=True, min_fixed=-1000, max_fixed=1000)


def q(s):
    return "'" + str(s).replace('\\', '\\\\').replace("'", "\\'") + "'"


# ---------------------------------------------------------------------- units
# Definitions (exact by international agreement or by the SI).
inch = dec('0.0254')                 # international yard and pound agreement, 1959
foot, yard = 12 * inch, 36 * inch
mile = 1760 * yard
lb = dec('0.45359237')               # same agreement
g_n = dec('9.80665')                 # standard acceleration of gravity, CGPM 1901
lbf = lb * g_n
c = F(299792458)                     # SI
julian_year = F(36525, 100) * 86400  # IAU
gal_us = 231 * inch ** 3             # US liquid gallon
btu_it = dec('1055.05585262')        # International Table BTU
mmhg = dec('13595.1') * g_n / 1000   # conventional millimetre of mercury
unit_factors = {
    'length': {'nm': F(1, 10**9), 'um': F(1, 10**6), 'mm': F(1, 1000), 'cm': F(1, 100), 'm': 1, 'km': 1000,
               'in': inch, 'ft': foot, 'yd': yard, 'mi': mile, 'nmi': 1852, 'au': 149597870700, 'ly': c * julian_year},
    'mass': {'ug': F(1, 10**9), 'mg': F(1, 10**6), 'g': F(1, 1000), 'kg': 1, 't': 1000, 'ct': F(2, 10000),
             'oz': lb / 16, 'lb': lb, 'st': 14 * lb, 'ton_us': 2000 * lb, 'ton_uk': 2240 * lb},
    'temperature': {'c': 1, 'f': F(5, 9), 'k': 1, 'r': F(5, 9)},
    'area': {'mm2': F(1, 10**6), 'cm2': F(1, 10**4), 'm2': 1, 'ha': 10**4, 'km2': 10**6,
             'in2': inch**2, 'ft2': foot**2, 'yd2': yard**2, 'acre': 43560 * foot**2, 'mi2': mile**2},
    'volume': {'ml': F(1, 10**6), 'l': F(1, 1000), 'm3': 1, 'tsp': gal_us / 768, 'tbsp': gal_us / 256,
               'floz': gal_us / 128, 'cup': gal_us / 16, 'pt': gal_us / 8, 'qt': gal_us / 4, 'gal': gal_us,
               'gal_uk': dec('0.00454609'), 'in3': inch**3, 'ft3': foot**3},
    'speed': {'mps': 1, 'kmh': F(1000, 3600), 'mph': mile / 3600, 'kn': F(1852, 3600), 'fps': foot, 'c': c},
    'time': {'ns': F(1, 10**9), 'us': F(1, 10**6), 'ms': F(1, 1000), 's': 1, 'min': 60, 'h': 3600, 'd': 86400,
             'wk': 604800, 'mo': julian_year / 12, 'yr': julian_year},
    'data': {'bit': F(1, 8), 'b': 1, 'kb': 1000, 'kib': 1024, 'mb': 1000**2, 'mib': 1024**2, 'gb': 1000**3,
             'gib': 1024**3, 'tb': 1000**4, 'tib': 1024**4},
    'pressure': {'pa': 1, 'kpa': 1000, 'mpa': 10**6, 'mbar': 100, 'bar': 10**5, 'atm': 101325,
                 'torr': F(101325, 760), 'mmhg': mmhg, 'inhg': mmhg * dec('25.4'), 'psi': lbf / inch**2},
    'energy': {'ev': dec('1.602176634e-19'), 'erg': F(1, 10**7), 'j': 1, 'kj': 1000, 'cal': dec('4.184'),
               'kcal': 4184, 'wh': 3600, 'kwh': 3600000, 'btu': btu_it, 'ftlbf': foot * lbf},
    'power': {'mw': F(1, 1000), 'w': 1, 'kw': 1000, 'megaw': 10**6, 'hp': 550 * foot * lbf, 'ps': 75 * g_n,
              'btuh': btu_it / 3600, 'ftlbfs': foot * lbf},
}
unit_offsets = {'c': dec('273.15'), 'f': dec('459.67'), 'k': 0, 'r': 0}
# Angles: the size of the unit in degrees.
angle_factors = {'deg': mpf(1), 'rad': 180 / mp.pi, 'grad': mpf('0.9'), 'turn': mpf(360), 'arcmin': mpf(1) / 60,
                 'arcsec': mpf(1) / 3600, 'mrad': mpf('0.18') / mp.pi}

out.append('/// Size of every unit in base units, derived from the definition of the unit.')
out.append('const Map<String, Map<String, String>> referenceUnitFactors = <String, Map<String, String>>{')
for cat, units in unit_factors.items():
    out.append(f"  {q(cat)}: <String, String>{{{', '.join(f'{q(u)}: {q(frac(v))}' for u, v in units.items())}}},")
out.append('};\n')
out.append('/// What is added to a temperature before it is scaled into kelvin.')
out.append(f"const Map<String, String> referenceTemperatureOffsets = <String, String>{{{', '.join(f'{q(u)}: {q(frac(v))}' for u, v in unit_offsets.items())}}};\n")
out.append('/// Size of every angle unit in degrees.')
out.append(f"const Map<String, String> referenceAngleFactors = <String, String>{{{', '.join(f'{q(u)}: {q(digits(v))}' for u, v in angle_factors.items())}}};\n")

# Facts as they are printed in standards and textbooks: (category, value, from, to, expected).
facts = [
    ('length', '1', 'in', 'cm', '2.54'), ('length', '1', 'ft', 'cm', '30.48'), ('length', '1', 'yd', 'm', '0.9144'),
    ('length', '1', 'mi', 'km', '1.609344'), ('length', '1', 'mi', 'ft', '5280'), ('length', '1', 'nmi', 'km', '1.852'),
    ('length', '1', 'au', 'km', '149597870.7'), ('length', '1', 'ly', 'km', '9460730472580.8'),
    ('mass', '1', 'lb', 'g', '453.59237'), ('mass', '1', 'oz', 'g', '28.349523125'), ('mass', '1', 'lb', 'oz', '16'),
    ('mass', '1', 'st', 'lb', '14'), ('mass', '1', 'ton_us', 'lb', '2000'), ('mass', '1', 'ton_uk', 'lb', '2240'),
    ('mass', '5', 'ct', 'g', '1'), ('mass', '1', 't', 'kg', '1000'),
    ('temperature', '100', 'c', 'f', '212'), ('temperature', '0', 'c', 'f', '32'), ('temperature', '-40', 'c', 'f', '-40'),
    ('temperature', '0', 'k', 'c', '-273.15'), ('temperature', '0', 'k', 'f', '-459.67'),
    ('temperature', '100', 'c', 'k', '373.15'), ('temperature', '0', 'c', 'r', '491.67'),
    ('temperature', '98.6', 'f', 'c', '37'),
    ('area', '1', 'ha', 'm2', '10000'), ('area', '1', 'acre', 'ft2', '43560'), ('area', '1', 'mi2', 'acre', '640'),
    ('area', '1', 'km2', 'ha', '100'), ('area', '1', 'ft2', 'in2', '144'), ('area', '1', 'yd2', 'ft2', '9'),
    ('volume', '1', 'gal', 'l', '3.785411784'), ('volume', '1', 'gal', 'in3', '231'), ('volume', '1', 'gal', 'floz', '128'),
    ('volume', '1', 'gal', 'qt', '4'), ('volume', '1', 'qt', 'pt', '2'), ('volume', '1', 'pt', 'cup', '2'),
    ('volume', '1', 'cup', 'floz', '8'), ('volume', '1', 'floz', 'tbsp', '2'), ('volume', '1', 'tbsp', 'tsp', '3'),
    ('volume', '1', 'gal_uk', 'l', '4.54609'), ('volume', '1', 'ft3', 'in3', '1728'), ('volume', '1', 'm3', 'l', '1000'),
    ('speed', '36', 'kmh', 'mps', '10'), ('speed', '60', 'mph', 'fps', '88'), ('speed', '1', 'kn', 'kmh', '1.852'),
    ('speed', '1', 'mph', 'kmh', '1.609344'), ('speed', '1', 'c', 'kmh', '1079252848.8'),
    ('time', '1', 'd', 's', '86400'), ('time', '1', 'wk', 'h', '168'), ('time', '1', 'yr', 'd', '365.25'),
    ('time', '1', 'yr', 'mo', '12'), ('time', '1', 'h', 'min', '60'),
    ('data', '1', 'b', 'bit', '8'), ('data', '1', 'kb', 'b', '1000'), ('data', '1', 'mb', 'kb', '1000'),
    ('data', '1', 'gb', 'mb', '1000'), ('data', '1', 'tb', 'gb', '1000'), ('data', '1', 'kib', 'b', '1024'),
    ('data', '1', 'mib', 'kib', '1024'), ('data', '1', 'gib', 'mib', '1024'), ('data', '1', 'tib', 'gib', '1024'),
    ('data', '1', 'mib', 'b', '1048576'), ('data', '1', 'mib', 'mb', '1.048576'), ('data', '1', 'mb', 'kib', '976.5625'),
    ('pressure', '1', 'atm', 'kpa', '101.325'), ('pressure', '1', 'atm', 'torr', '760'), ('pressure', '1', 'bar', 'mbar', '1000'),
    ('pressure', '1', 'inhg', 'mmhg', '25.4'), ('pressure', '1', 'atm', 'bar', '1.01325'),
    ('energy', '1', 'kwh', 'kj', '3600'), ('energy', '1', 'kcal', 'cal', '1000'), ('energy', '1', 'cal', 'j', '4.184'),
    ('energy', '1', 'wh', 'j', '3600'), ('energy', '1', 'j', 'erg', '10000000'),
    ('power', '1', 'hp', 'ftlbfs', '550'), ('power', '1', 'kw', 'w', '1000'), ('power', '1', 'ps', 'w', '735.49875'),
    ('power', '1', 'megaw', 'kw', '1000'),
]
out.append('/// Conversions as standards and textbooks state them: (category, value, from, to, expected).')
out.append('const List<(String, String, String, String, String)> referenceConversions = <(String, String, String, String, String)>[')
for cat, value, a, b, expected in facts:
    # The facts and the derived factors have to agree with each other, too.
    got = (dec(value) + (unit_offsets[a] if cat == 'temperature' else 0)) * F(unit_factors[cat][a]) / F(unit_factors[cat][b]) \
        - (unit_offsets[b] if cat == 'temperature' else 0)
    assert got == dec(expected), (cat, value, a, b, expected, got)
    out.append(f'  ({q(cat)}, {q(value)}, {q(a)}, {q(b)}, {q(expected)}),')
out.append('];\n')

# Results that are not round numbers: (category, value, from, to, expected to 45 digits).
rounded = [('length', '1', 'm', 'ft'), ('length', '1', 'km', 'mi'), ('length', '1', 'ly', 'au'), ('length', '1', 'nmi', 'mi'),
           ('mass', '1', 'kg', 'lb'), ('mass', '1', 'g', 'oz'), ('temperature', '37', 'c', 'f'), ('temperature', '300', 'k', 'f'),
           ('area', '1', 'm2', 'ft2'), ('area', '1', 'ha', 'acre'), ('volume', '1', 'l', 'gal'), ('volume', '1', 'gal_uk', 'gal'),
           ('volume', '1', 'l', 'floz'), ('speed', '100', 'kmh', 'mph'), ('speed', '1', 'mps', 'kn'), ('time', '1', 'mo', 'd'),
           ('data', '1', 'gb', 'gib'), ('data', '1', 'tb', 'tib'), ('pressure', '1', 'atm', 'psi'), ('pressure', '1', 'atm', 'mmhg'),
           ('pressure', '1', 'atm', 'inhg'), ('pressure', '1', 'psi', 'kpa'), ('energy', '1', 'kwh', 'kcal'),
           ('energy', '1', 'btu', 'kj'), ('energy', '1', 'ev', 'j'), ('energy', '1', 'ftlbf', 'j'), ('power', '1', 'hp', 'w'),
           ('power', '1', 'hp', 'ps'), ('power', '1', 'kw', 'btuh'), ('power', '1', 'kw', 'hp')]
out.append('/// Conversions that do not come out round: (category, value, from, to, expected).')
out.append('const List<(String, String, String, String, String)> referenceRoundedConversions = <(String, String, String, String, String)>[')
for cat, value, a, b in rounded:
    got = (dec(value) + (unit_offsets[a] if cat == 'temperature' else 0)) * F(unit_factors[cat][a]) / F(unit_factors[cat][b]) \
        - (unit_offsets[b] if cat == 'temperature' else 0)
    out.append(f'  ({q(cat)}, {q(value)}, {q(a)}, {q(b)}, {q(digits(got))}),')
for value, a, b in [('180', 'deg', 'rad'), ('1', 'rad', 'deg'), ('1', 'turn', 'rad'), ('100', 'grad', 'deg'), ('1', 'deg', 'arcsec'),
                    ('1', 'mrad', 'arcmin'), ('1', 'rad', 'grad')]:
    out.append(f"  ('angle', {q(value)}, {q(a)}, {q(b)}, {q(digits(mpf(value) * angle_factors[a] / angle_factors[b]))}),")
out.append('];\n')

# ------------------------------------------------------------------ constants
h, e, k, n_a, c0 = mpf('6.62607015e-34'), mpf('1.602176634e-19'), mpf('1.380649e-23'), mpf('6.02214076e23'), mpf(299792458)
constants = {
    # Defined exactly by the SI (2019) or by convention.
    'c_0': '299792458', 'h': '6.62607015e-34', 'q_e': '1.602176634e-19', 'k_B': '1.380649e-23', 'N_A': '6.02214076e23',
    'g_0': '9.80665', 'atm': '101325', 'eV': '1.602176634e-19',
    # Follow from the exact ones.
    'ħ': digits(h / (2 * mp.pi), 60), 'R': digits(n_a * k, 60), 'F': digits(n_a * e, 60),
    'σ': digits(2 * mp.pi**5 * k**4 / (15 * h**3 * c0**2), 60), 'V_m': digits(n_a * k * mpf('273.15') / 101325, 60),
    # Measured: 2022 CODATA recommended values as published on physics.nist.gov/cuu/Constants.
    'G': '6.67430e-11', 'm_e': '9.1093837139e-31', 'm_p': '1.67262192595e-27', 'm_n': '1.67492750056e-27',
    'm_u': '1.66053906892e-27', 'ε_0': '8.8541878188e-12', 'μ_0': '1.25663706127e-6', 'α': '7.2973525643e-3',
    'R_∞': '10973731.568157', 'a_0': '5.29177210544e-11', 'μ_B': '9.2740100657e-24',
}
out.append('/// Physical constants in SI units: exact definitions, values that follow from them (60 digits) and the')
out.append('/// 2022 CODATA recommended values.')
out.append('const Map<String, String> referenceConstants = <String, String>{')
for s, v in constants.items():
    out.append(f'  {q(s)}: {q(v)},')
out.append('};\n')

# ---------------------------------------------------------------- polynomials
x = sympy.symbols('x')


def roots_of(coefficients):
    poly = sympy.Poly(sum(sympy.Rational(cf.numerator, cf.denominator) * x**(len(coefficients) - 1 - i)
                          for i, cf in enumerate(coefficients)), x)
    result = []
    for r in poly.all_roots():
        re, im = sympy.N(r, 60).as_real_imag()
        result.append((digits(mpf(str(re))), digits(mpf(str(im)))))
    return result


polys = [
    # quadratics
    [2, 5, -3], [1, 0, -2], [1, 2, 5], [1, -2, 1], [6, 1, -2], [1, 0, 0], [1, 0, 1], [4, -12, 9], [1, -1, -1],
    [F(1, 2), F(-5, 4), F(3, 10)], [3, 0, -27], [1, -1000001, 1000000], [7, -3, 11], [-2, 8, -8], [5, 5, 5],
    [1, 100000, 1], [F(1, 3), F(1, 7), F(-2, 5)], [1, -3, F(9, 4)],
    # cubics
    [1, -6, 11, -6], [1, 0, 0, -8], [1, -3, 3, -1], [1, 0, -3, 1], [1, -4, 5, -2], [2, -3, -11, 6], [1, 0, 0, 0],
    [1, 0, 1, 0], [1, 1, 1, 1], [8, -36, 54, -27], [1, 0, -7, 6], [1, -1, 1, -1], [3, -5, 2, 7],
    [F(1, 2), F(-3, 4), F(1, 8), F(1, 16)], [1, 0, 0, 1], [1, -6, 12, -8], [1, 2, -5, -6], [1, -3, -144, 432],
    [1, 0, -15, -4], [10, -7, 0, 1],
    # linear
    [3, -7], [F(-2, 5), F(1, 3)],
]
for _ in range(10):
    polys.append([rng.choice([-5, -4, -3, -2, -1, 1, 2, 3, 4, 5])] + [rng.randint(-12, 12) for _ in range(2)])
for _ in range(12):
    polys.append([rng.choice([-5, -4, -3, -2, -1, 1, 2, 3, 4, 5])] + [rng.randint(-12, 12) for _ in range(3)])
out.append('/// Polynomial equations: (coefficients from the highest power down, roots as (real, imaginary)).')
out.append('const List<(List<String>, List<(String, String)>)> referencePolynomials = <(List<String>, List<(String, String)>)>[')
for coefficients in polys:
    coefficients = [F(v) for v in coefficients]
    rs = ', '.join(f'({q(re)}, {q(im)})' for re, im in roots_of(coefficients))
    out.append(f"  (<String>[{', '.join(q(frac(v)) for v in coefficients)}], <(String, String)>[{rs}]),")
out.append('];\n')

# ------------------------------------------------------------------- matrices


def rand_matrix(rows, cols, decimals=False):
    def entry():
        v = F(rng.randint(-9, 9))
        return v + F(rng.choice([0, 25, 5, 75]), 100) if decimals else v
    return [[entry() for _ in range(cols)] for _ in range(rows)]


def lit(m):
    return '<List<String>>[' + ', '.join('<String>[' + ', '.join(q(frac(v)) for v in row) + ']' for row in m) + ']'


def smat(m):
    return sympy.Matrix([[sympy.Rational(v.numerator, v.denominator) for v in row] for row in m])


def unsmat(m):
    return [[F(int(v.p), int(v.q)) for v in m.row(r)] for r in range(m.rows)]


squares = [[[F(2), F(1)], [F(5), F(3)]], [[F(1), F(2)], [F(2), F(4)]],
           [[F(1), F(2), F(3)], [F(4), F(5), F(6)], [F(7), F(8), F(9)]],
           [[F(2), F(0), F(0), F(0)], [F(0), F(3), F(0), F(0)], [F(0), F(0), F(5), F(0)], [F(0), F(0), F(0), F(7)]],
           [[F(1, 2), F(1, 3)], [F(1, 4), F(1, 5)]], [[F(0), F(1)], [F(1), F(0)]], [[F(4)]],
           [[F(1), F(1), F(1), F(1)], [F(1), F(2), F(4), F(8)], [F(1), F(3), F(9), F(27)], [F(1), F(4), F(16), F(64)]]]
for n in (2, 2, 3, 3, 3, 4, 4, 4):
    squares.append(rand_matrix(n, n))
for n in (2, 3, 4):
    squares.append(rand_matrix(n, n, decimals=True))
out.append('/// Square matrices: (A, B, determinant of A, trace, rank, inverse or null, transpose, A + B, A − B, A × B).')
out.append('const List<(List<List<String>>, List<List<String>>, String, String, int, List<List<String>>?, '
           'List<List<String>>, List<List<String>>, List<List<String>>, List<List<String>>)> referenceMatrices = [')
for a in squares:
    n = len(a)
    b = rand_matrix(n, n)
    sa, sb = smat(a), smat(b)
    det = sa.det()
    inverse = lit(unsmat(sa.inv())) if det != 0 else 'null'
    out.append(f'  ({lit(a)}, {lit(b)}, {q(frac(F(int(det.p), int(det.q))))}, {q(frac(F(int(sa.trace().p), int(sa.trace().q))))}, '
               f'{sa.rank()}, {inverse}, {lit(unsmat(sa.T))}, {lit(unsmat(sa + sb))}, {lit(unsmat(sa - sb))}, {lit(unsmat(sa * sb))}),')
out.append('];\n')
rects = [(2, 3, 3, 2), (3, 2, 2, 4), (1, 4, 4, 1), (4, 1, 1, 3), (3, 4, 4, 2)]
out.append('/// Rectangular matrices: (A, B, A × B, transpose of A, rank of A).')
out.append('const List<(List<List<String>>, List<List<String>>, List<List<String>>, List<List<String>>, int)> '
           'referenceRectangular = [')
for r1, c1, r2, c2 in rects:
    a, b = rand_matrix(r1, c1), rand_matrix(r2, c2)
    sa, sb = smat(a), smat(b)
    out.append(f'  ({lit(a)}, {lit(b)}, {lit(unsmat(sa * sb))}, {lit(unsmat(sa.T))}, {sa.rank()}),')
out.append('];\n')

# ----------------------------------------------------------------- statistics


def median(values):
    n = len(values)
    return values[n // 2] if n % 2 else (values[n // 2 - 1] + values[n // 2]) / 2


def sqrt(v):
    return mp.sqrt(mpf(v.numerator) / mpf(v.denominator))


def one_var(values):
    n = len(values)
    total, squares_ = sum(values), sum(v * v for v in values)
    mean = total / n
    pop_var = sum((v - mean) ** 2 for v in values) / n
    sample_var = sum((v - mean) ** 2 for v in values) / (n - 1) if n > 1 else None
    s = sorted(values)
    half = n // 2
    # Quartiles as the medians of the lower and the upper half; with an odd
    # count the median itself belongs to neither half (TI and Casio do the same).
    q1, q3 = (s[0], s[0]) if n == 1 else (median(s[:half]), median(s[n - half:]))
    return [str(n), frac(total), frac(squares_), frac(mean), frac(pop_var), digits(sqrt(pop_var)),
            'null' if sample_var is None else frac(sample_var), 'null' if sample_var is None else digits(sqrt(sample_var)),
            frac(s[0]), frac(s[-1]), frac(median(s)), frac(q1), frac(q3)]


data_sets = [['2', '4', '4', '4', '5', '5', '7', '9'], ['1', '2', '3', '4', '5', '6', '7'], ['3.5'],
             ['-2.5', '0', '2.5'], ['10', '10', '10', '10'], ['1.1', '2.2', '3.3', '4.4', '5.5', '6.6'],
             ['100', '-100'], ['0.001', '0.002', '0.004', '0.008', '0.016'],
             ['12', '15', '11', '19', '23', '8', '14', '17', '21', '9', '16']]
for size in (5, 8, 13, 20):
    data_sets.append([str(F(rng.randint(-5000, 5000), 100)).replace('/', '÷') for _ in range(size)])
data_sets = [[str(float(F(v.replace('÷', '/')))) if '÷' in v else v for v in d] for d in data_sets]
out.append('/// One-variable statistics: (data, [n, Σx, Σx², mean, σ², σ, s², s, min, max, median, Q1, Q3]).')
out.append('const List<(List<String>, List<String>)> referenceStatistics = <(List<String>, List<String>)>[')
for d in data_sets:
    values = [dec(v) for v in d]
    out.append(f"  (<String>[{', '.join(q(v) for v in d)}], <String>[{', '.join(q(v) for v in one_var(values))}]),")
out.append('];\n')

pairs = [(['1', '2', '3', '4'], ['3', '5', '7', '9']), (['1', '2', '3', '4', '5'], ['2.2', '4.1', '6.2', '7.9', '10.1']),
         (['0', '1', '2', '3'], ['5', '3', '1', '-1']), (['1', '2', '3', '4', '5', '6'], ['1', '4', '9', '16', '25', '36']),
         (['-3', '-1', '0', '2', '5'], ['7.5', '2', '0.5', '-4', '-11.25'])]
for size in (6, 10):
    xs = [str(rng.randint(-20, 20) / 2) for _ in range(size)]
    ys = [str(rng.randint(-300, 300) / 10) for _ in range(size)]
    pairs.append((xs, ys))
out.append('/// Linear regression y = a + b x: (x, y, [Σxy, covariance, slope b, intercept a, r]).')
out.append('const List<(List<String>, List<String>, List<String>)> referenceRegressions = <(List<String>, List<String>, List<String>)>[')
for xs, ys in pairs:
    vx, vy = [dec(v) for v in xs], [dec(v) for v in ys]
    n = len(vx)
    mx, my = sum(vx) / n, sum(vy) / n
    sxx, syy = sum((v - mx) ** 2 for v in vx), sum((v - my) ** 2 for v in vy)
    sxy = sum((a - mx) * (b - my) for a, b in zip(vx, vy))
    slope = sxy / sxx
    r = (mpf(sxy.numerator) / mpf(sxy.denominator)) / (sqrt(sxx) * sqrt(syy))
    row = [frac(sum(a * b for a, b in zip(vx, vy))), frac(sxy / n), frac(slope), frac(my - slope * mx), digits(r)]
    out.append(f"  (<String>[{', '.join(q(v) for v in xs)}], <String>[{', '.join(q(v) for v in ys)}], "
               f"<String>[{', '.join(q(v) for v in row)}]),")
out.append('];\n')

# --------------------------------------------------------------------- Base-N


def wrap(value, bits):
    return value & ((1 << bits) - 1)


def signed(word, bits):
    return word - (1 << bits) if word >> (bits - 1) else word


def trunc_div(a, b):
    quotient = abs(a) // abs(b)
    return quotient if (a < 0) == (b < 0) else -quotient


ops = ['+', '−', '×', '÷', 'mod', 'and', 'or', 'xor', '<<', '>>']
out.append('/// Base-N: (word size, signed, hexadecimal expression, result word in hexadecimal, result read as a number).')
out.append('const List<(int, bool, String, String, String)> referenceBaseN = <(int, bool, String, String, String)>[')
for bits in (8, 16, 32, 64):
    for is_signed in (True, False):
        for op in ops:
            a, b = rng.getrandbits(bits), rng.getrandbits(bits)
            if op in ('<<', '>>'):
                b = rng.randint(0, bits - 1)
            if op in ('÷', 'mod') and b == 0:
                b = 3
            na, nb = (signed(a, bits), signed(b, bits)) if is_signed else (a, b)
            if op == '+':
                value = na + nb
            elif op == '−':
                value = na - nb
            elif op == '×':
                value = na * nb
            elif op == '÷':
                value = trunc_div(na, nb)
            elif op == 'mod':
                value = na - nb * trunc_div(na, nb)
            elif op == 'and':
                value = a & b
            elif op == 'or':
                value = a | b
            elif op == 'xor':
                value = a ^ b
            elif op == '<<':
                value = a << b
            else:
                value = (na >> b) if is_signed else (a >> b)
            word = wrap(value, bits)
            number = signed(word, bits) if is_signed else word
            out.append(f"  ({bits}, {'true' if is_signed else 'false'}, {q(f'{a:X} {op} {b:X}')}, {q(f'{word:X}')}, {q(number)}),")
        a = rng.getrandbits(bits)
        word = wrap(~a, bits)
        out.append(f"  ({bits}, {'true' if is_signed else 'false'}, {q(f'not {a:X}')}, {q(f'{word:X}')}, "
                   f"{q(signed(word, bits) if is_signed else word)}),")
out.append('];\n')
out.append('/// The same word in the four bases: (word size, hexadecimal, decimal when unsigned, decimal when signed, octal, binary).')
out.append('const List<(int, String, String, String, String, String)> referenceBases = <(int, String, String, String, String, String)>[')
for bits in (8, 16, 32, 64):
    for word in [0, 1, (1 << bits) - 1, 1 << (bits - 1), (1 << (bits - 1)) - 1] + [rng.getrandbits(bits) for _ in range(3)]:
        out.append(f"  ({bits}, {q(f'{word:X}')}, {q(word)}, {q(signed(word, bits))}, {q(f'{word:o}')}, {q(f'{word:b}')}),")
out.append('];\n')

# ---------------------------------------------------------------------- table
tables = [
    ('x^2-3x+2', 'deg', '-2', '2', '0.5', lambda v: v * v - 3 * v + 2),
    ('sin(x)', 'deg', '0', '90', '15', lambda v: mp.sin(v * mp.pi / 180)),
    ('cos(x)', 'rad', '0', '3', '0.5', lambda v: mp.cos(v)),
    ('√(x)+1/(x+1)', 'deg', '0', '5', '1', lambda v: mp.sqrt(v) + 1 / (v + 1)),
    ('ln(x)', 'deg', '1', '10', '3', lambda v: mp.log(v)),
    ('2^x', 'deg', '-3', '3', '1', lambda v: mpf(2) ** v),
    ('e^(-x^2)', 'deg', '-1', '1', '0.25', lambda v: mp.exp(-v * v)),
]
out.append('/// f(x) tables: (function, angle unit, start, end, step, values of f).')
out.append('const List<(String, String, String, String, String, List<String>)> referenceTables = <(String, String, String, String, String, List<String>)>[')
for text, unit, start, end, step, f in tables:
    values, v = [], dec(start)
    while v <= dec(end):
        values.append(digits(f(mpf(v.numerator) / mpf(v.denominator)), 30))
        v += dec(step)
    out.append(f"  ({q(text)}, {q(unit)}, {q(start)}, {q(end)}, {q(step)}, <String>[{', '.join(q(s) for s in values)}]),")
out.append('];')

header = '''// GENERATED by tool/reference/generate_reference_data.py - do not edit by hand.
//
// Expected values for reference_values_test.dart. None of them was produced by
// the app: unit factors are derived from the definitions of the units, the
// physical constants are the published ones, everything else was computed with
// Python's exact fractions, sympy and mpmath.
// ignore_for_file: lines_longer_than_80_chars
library;

'''
target = Path(__file__).resolve().parents[2] / 'test' / 'domain' / 'reference_data.dart'
target.write_text(header + '\n'.join(out) + '\n', encoding='utf-8')
dart = shutil.which('dart')
if dart:
    subprocess.run([dart, 'format', str(target)], check=True, cwd=target.parents[2], stdout=subprocess.DEVNULL)
    print(f'{target}: written and formatted')
else:
    print(f'{target}: written; now run `dart format {target.relative_to(target.parents[2])}`')
