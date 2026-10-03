import 'dart:math' as math;

/// Round to [decimals] (half away from zero). Tolerates binary noise, so
/// `roundTo(1.005, 2) == 1.01` and `roundTo(2.675, 2) == 2.68`.
double roundTo(double v, int decimals) {
  if (!v.isFinite) return v;
  final f = math.pow(10, decimals).toDouble();
  final scaled = v.abs() * f;
  if (!scaled.isFinite || scaled >= 1e15) return v;
  final cleaned = double.parse(scaled.toStringAsPrecision(15));
  final r = cleaned.roundToDouble() / f;
  return v < 0 ? -r : r;
}

/// Integer-looking values print without decimals; otherwise up to
/// [maxDecimals] decimals with trailing zeros removed. -0 prints as 0.
String fmtNum(double v, {int maxDecimals = 3}) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? '∞' : '-∞';
  final d = maxDecimals < 0 ? 0 : maxDecimals;
  final r = roundTo(v, d);
  if (r == 0) return '0'; // also catches -0.0
  if (r.abs() >= 1e15) return r.toString();
  if (r == r.roundToDouble()) return r.toInt().toString();
  var s = r.toStringAsFixed(d > 20 ? 20 : d);
  if (s.contains('.')) {
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  if (s == '-0') return '0';
  return s;
}
