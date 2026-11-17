// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

/// Immutable 2D point (sheet mm or image px, depending on context).
final class Pt {
  const Pt(this.x, this.y);

  final double x;
  final double y;

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double k) => Pt(x * k, y * k);

  double get norm => sqrt(x * x + y * y);
  double distanceTo(Pt o) => (this - o).norm;
  bool get isFinite => x.isFinite && y.isFinite;

  @override
  bool operator ==(Object other) => other is Pt && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Pt($x, $y)';
}
