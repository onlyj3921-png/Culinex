/// Unit families. Weight, volume and pieces can never be mixed.
enum UnitFamily { mass, volume, count }

class UnitDef {
  const UnitDef(this.code, this.family, this.factor);
  final String code;
  final UnitFamily family;

  /// Multiplier to the family's base unit (g, ml, pcs).
  final double factor;
}

const List<UnitDef> kUnits = [
  UnitDef('g', UnitFamily.mass, 1),
  UnitDef('kg', UnitFamily.mass, 1000),
  UnitDef('ml', UnitFamily.volume, 1),
  UnitDef('L', UnitFamily.volume, 1000),
  UnitDef('pcs', UnitFamily.count, 1),
];

/// Case-insensitive lookup, no trimming (same as the V1.2 spreadsheet MATCH).
UnitDef? findUnit(String? code) {
  if (code == null) return null;
  final c = code.toLowerCase();
  for (final u in kUnits) {
    if (u.code.toLowerCase() == c) return u;
  }
  return null;
}
