import 'units.dart';

/// Per-row status. Mirrors the V1.2 spreadsheet column G text.
enum RowStatus { blank, ok, incomplete, checkNumbers, checkUnit, unitMismatch }

extension RowStatusText on RowStatus {
  String get sheetText {
    switch (this) {
      case RowStatus.incomplete:
        return 'Incomplete';
      case RowStatus.checkNumbers:
        return 'Check numbers';
      case RowStatus.checkUnit:
        return 'Check unit';
      case RowStatus.unitMismatch:
        return 'Unit mismatch';
      case RowStatus.blank:
      case RowStatus.ok:
        return '';
    }
  }

  bool get isProblem => this != RowStatus.blank && this != RowStatus.ok;
}

/// Overall input status. Same priority order as the V1.2 "Input Check" cell.
enum InputStatus {
  ok,
  negative,
  unitMismatch,
  checkUnit,
  incomplete,
  invalidRow,
  noServings,
  badMargin,
  badOwnPrice,
}

class IngredientLine {
  const IngredientLine({
    this.name,
    this.price,
    this.size,
    this.packUnit,
    this.used,
    this.usedUnit,
  });
  final String? name;

  /// Package price in RM.
  final double? price;
  final double? size;
  final String? packUnit;
  final double? used;
  final String? usedUnit;
}

class RowResult {
  const RowResult(this.status, this.cost);
  final RowStatus status;
  final double? cost;
}

bool _blankText(String? s) => s == null || s.trim().isEmpty;
bool _finite(double v) => v.isFinite;

/// Cost of one ingredient row (V1.2 column G).
RowResult evaluateRow(IngredientLine l) {
  if (_blankText(l.name) &&
      l.price == null &&
      l.size == null &&
      _blankText(l.packUnit) &&
      l.used == null &&
      _blankText(l.usedUnit)) {
    return const RowResult(RowStatus.blank, null);
  }
  if (l.price == null ||
      l.size == null ||
      _blankText(l.packUnit) ||
      l.used == null ||
      _blankText(l.usedUnit)) {
    return const RowResult(RowStatus.incomplete, null);
  }
  final price = l.price!, size = l.size!, used = l.used!;
  if (!_finite(price) ||
      !_finite(size) ||
      !_finite(used) ||
      price < 0 ||
      size <= 0 ||
      used < 0) {
    return const RowResult(RowStatus.checkNumbers, null);
  }
  final pu = findUnit(l.packUnit);
  final uu = findUnit(l.usedUnit);
  if (pu == null || uu == null) return const RowResult(RowStatus.checkUnit, null);
  if (pu.family != uu.family) {
    return const RowResult(RowStatus.unitMismatch, null);
  }
  return RowResult(RowStatus.ok, price * used * uu.factor / (size * pu.factor));
}

class CalcInput {
  const CalcInput({
    this.lines = const [],
    this.servings,
    this.margin,
    this.otherCosts,
    this.ownPrice,
  });
  final List<IngredientLine> lines;
  final double? servings;

  /// Target margin as a fraction: 0.65 = 65%.
  final double? margin;

  /// Other costs per batch, RM.
  final double? otherCosts;
  final double? ownPrice;
}

class CalcResult {
  const CalcResult({
    required this.rows,
    required this.ingredientCost,
    required this.totalCost,
    required this.costPerServing,
    required this.suggestedPrice,
    required this.ownPrice,
    required this.profitPerServing,
    required this.margin,
    required this.batchProfit,
    required this.status,
    required this.hiddenCostWarning,
    required this.blocked,
  });

  final List<RowResult> rows;

  /// Null when any row has a problem (totals are paused, never partially summed).
  final double? ingredientCost;
  final double? totalCost;
  final double? costPerServing;
  final double? suggestedPrice;
  final double? ownPrice;
  final double? profitPerServing;
  final double? margin;
  final double? batchProfit;
  final InputStatus status;

  /// True when Other Costs is zero or empty (profit is probably overstated).
  final bool hiddenCostWarning;
  final bool blocked;

  /// Price used = own price if entered, otherwise the suggested price.
  double? get priceUsed => ownPrice ?? suggestedPrice;

  // ---- Sheet-equivalent cell values (used by golden tests) ----
  // Each returns a double, a String message, or null for a blank cell.
  Object? get cellE12 => blocked ? 'Fix inputs' : ingredientCost;
  Object? get cellE13 => totalCost ?? 'Fix inputs';
  Object? get cellE6 {
    if (totalCost == null) return 'Fix inputs';
    return costPerServing ?? 'Enter servings';
  }

  Object? get cellE7 => suggestedPrice ?? 'Check inputs';
  Object? get cellE11 => ownPrice ?? suggestedPrice ?? 'Check inputs';
  Object? get cellE8 => profitPerServing;
  Object? get cellE9 => margin;
  Object? get cellE10 => batchProfit;
}

/// The V1.2 calculation, step for step.
CalcResult calculate(CalcInput i) {
  final rows = i.lines.map(evaluateRow).toList();
  final blocked = rows.any((r) => r.status.isProblem);
  double? ingredientCost;
  if (!blocked) {
    ingredientCost = 0;
    for (final r in rows) {
      if (r.cost != null) ingredientCost = ingredientCost! + r.cost!;
    }
  }
  final other = i.otherCosts ?? 0;
  final double? total = ingredientCost == null ? null : ingredientCost + other;

  final servings = i.servings ?? 0;
  double? cps;
  if (total != null && servings > 0) cps = total / servings;

  final m = i.margin;
  double? suggested;
  if (cps != null && m != null && m >= 0 && m < 1) suggested = cps / (1 - m);

  final own = i.ownPrice;
  final double? priceUsed = own ?? suggested;

  double? profit;
  if (priceUsed != null && cps != null) profit = priceUsed - cps;

  double? margin;
  if (profit != null && priceUsed! > 0) margin = profit / priceUsed;

  double? batch;
  if (profit != null && i.servings != null) batch = profit * i.servings!;

  // Input status, same priority as the spreadsheet.
  bool neg = other < 0;
  for (final l in i.lines) {
    if ((l.price ?? 0) < 0 || (l.size ?? 0) < 0 || (l.used ?? 0) < 0) neg = true;
  }
  InputStatus status;
  if (neg) {
    status = InputStatus.negative;
  } else if (rows.any((r) => r.status == RowStatus.unitMismatch)) {
    status = InputStatus.unitMismatch;
  } else if (rows.any((r) => r.status == RowStatus.checkUnit)) {
    status = InputStatus.checkUnit;
  } else if (rows.any((r) => r.status == RowStatus.incomplete)) {
    status = InputStatus.incomplete;
  } else if (rows.any((r) => r.status == RowStatus.checkNumbers)) {
    status = InputStatus.invalidRow;
  } else if (servings <= 0) {
    status = InputStatus.noServings;
  } else if (m == null || m < 0 || m >= 1) {
    status = InputStatus.badMargin;
  } else if (own != null && own <= 0) {
    status = InputStatus.badOwnPrice;
  } else {
    status = InputStatus.ok;
  }

  return CalcResult(
    rows: rows,
    ingredientCost: ingredientCost,
    totalCost: total,
    costPerServing: cps,
    suggestedPrice: suggested,
    ownPrice: own,
    profitPerServing: profit,
    margin: margin,
    batchProfit: batch,
    status: status,
    hiddenCostWarning: other <= 0,
    blocked: blocked,
  );
}

/// RM -> integer sen (half away from zero, tolerant of binary float error).
int toSen(double rm) {
  final v = rm * 100;
  return (v >= 0 ? v + 1e-9 : v - 1e-9).round();
}

double fromSen(num sen) => sen / 100.0;
