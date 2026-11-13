import 'package:intl/intl.dart';

final NumberFormat _n = NumberFormat('#,##0.00');

/// Formats RM, e.g. RM 1,234.50 ; negatives as -RM 5.00
String rm(num? v) {
  if (v == null) return '—';
  final s = _n.format(v.abs());
  return v < 0 ? '-RM $s' : 'RM $s';
}

String rmSen(num? sen) => sen == null ? '—' : rm(sen / 100.0);

String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

/// Parses a typed number. Accepts "1,234.50". Returns null when empty or invalid.
double? parseNum(String s) {
  final t = s.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || !v.isFinite) return null;
  return v;
}

String fmtQty(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Shows a base-unit stock amount in a friendly unit (g -> kg, ml -> L).
String fmtBase(double base, String packUnit) {
  switch (packUnit) {
    case 'g':
    case 'kg':
      return base.abs() >= 1000 ? '${fmtQty(base / 1000)} kg' : '${fmtQty(base)} g';
    case 'ml':
    case 'L':
      return base.abs() >= 1000 ? '${fmtQty(base / 1000)} L' : '${fmtQty(base)} ml';
    default:
      return '${fmtQty(base)} pcs';
  }
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
