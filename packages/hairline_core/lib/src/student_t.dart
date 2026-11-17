// Copyright (c) 2026 Vassel Goleyu. MIT License.

/// Two-sided 95 percent quantile of the standard normal, `z_0.975` (the dof -> infinity limit).
const double normalQuantile975 = 1.959964;

/// `t_0.975,dof` for dof 1..30. Computed by integrating the t density and bisecting
/// (5 decimals) and cross-checked against the NIST/SEMATECH e-Handbook table
/// 1.3.6.7.2 (itl.nist.gov, 3 decimals) in test/student_t_test.dart.
const List<double> _t975 = [
  12.70620, 4.30265, 3.18245, 2.77645, 2.57058, 2.44691, 2.36462, 2.30600, 2.26216, 2.22814, //
  2.20099, 2.17881, 2.16037, 2.14479, 2.13145, 2.11991, 2.10982, 2.10092, 2.09302, 2.08596,
  2.07961, 2.07387, 2.06866, 2.06390, 2.05954, 2.05553, 2.05183, 2.04841, 2.04523, 2.04227,
];

/// Table value for an integer dof in 1..30.
double studentT975(int dof) {
  if (dof < 1 || dof > _t975.length) throw ArgumentError.value(dof, 'dof', 'must be in 1..30');
  return _t975[dof - 1];
}

/// Coverage factor k for 95 percent from effective degrees of freedom [dof].
///
/// 1..30: linear in `1/dof` between table entries (the t quantile is close to linear
/// in `1/dof`, error below 0.001). Above 30: linear in `1/dof` from t(30) to the
/// normal limit at `1/dof = 0` (error below 0.003 up to dof 100, always on the
/// conservative side). Below 1 the factor of dof 1 is used.
double coverageFactor(double dof) {
  if (dof.isNaN) throw ArgumentError.value(dof, 'dof', 'NaN');
  if (dof <= 1) return _t975[0];
  if (dof.isInfinite) return normalQuantile975;
  final lo = dof >= 30 ? 30.0 : dof.floorToDouble();
  final double kLo = _t975[lo.toInt() - 1];
  final double hi = dof >= 30 ? double.infinity : lo + 1;
  final kHi = dof >= 30 ? normalQuantile975 : _t975[hi.toInt() - 1];
  if (dof == lo) return kLo;
  final invLo = 1 / lo, invHi = hi.isInfinite ? 0.0 : 1 / hi;
  final f = (1 / dof - invHi) / (invLo - invHi);
  return kHi + f * (kLo - kHi);
}

/// Welch-Satterthwaite effective dof: `uC^4 / sum(u_i^4 / dof_i)` over the components
/// with finite dof; components with infinite dof (not listed) add nothing. Returns
/// infinity if nothing finite contributes.
double welchSatterthwaite({required double uC, required List<({double u, double dof})> finite}) {
  var denom = 0.0;
  for (final c in finite) {
    final u2 = c.u * c.u;
    denom += u2 * u2 / c.dof;
  }
  if (denom <= 0) return double.infinity;
  return uC * uC * uC * uC / denom;
}
