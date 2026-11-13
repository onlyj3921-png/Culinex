import 'package:culinex_engine/culinex_engine.dart';

class Ingredient {
  Ingredient({
    this.id,
    required this.name,
    required this.packUnit,
    required this.packSize,
    required this.packPriceSen,
    this.trackStock = false,
    this.stockBase = 0,
    this.lowStockBase,
  });
  final int? id;
  final String name;
  final String packUnit;
  final double packSize;
  final int packPriceSen;
  final bool trackStock;
  final double stockBase;
  final double? lowStockBase;

  UnitFamily get family => findUnit(packUnit)!.family;
  String get familyName => family.name;

  bool get isLow => trackStock && lowStockBase != null && stockBase <= lowStockBase!;

  factory Ingredient.fromMap(Map<String, Object?> m) => Ingredient(
        id: m['id'] as int,
        name: m['name'] as String,
        packUnit: m['pack_unit'] as String,
        packSize: (m['pack_size'] as num).toDouble(),
        packPriceSen: m['pack_price_sen'] as int,
        trackStock: (m['track_stock'] as int) == 1,
        stockBase: (m['stock_base'] as num).toDouble(),
        lowStockBase: (m['low_stock_base'] as num?)?.toDouble(),
      );
}

class Recipe {
  Recipe({
    this.id,
    required this.name,
    required this.servings,
    required this.targetMargin,
    this.otherCostsSen = 0,
    this.ownPriceSen,
    this.notes,
  });
  final int? id;
  final String name;
  final double servings;
  final double targetMargin;
  final int otherCostsSen;
  final int? ownPriceSen;
  final String? notes;

  factory Recipe.fromMap(Map<String, Object?> m) => Recipe(
        id: m['id'] as int,
        name: m['name'] as String,
        servings: (m['servings'] as num).toDouble(),
        targetMargin: (m['target_margin'] as num).toDouble(),
        otherCostsSen: m['other_costs_sen'] as int,
        ownPriceSen: m['own_price_sen'] as int?,
        notes: m['notes'] as String?,
      );
}

/// One recipe line together with the ingredient's CURRENT purchase price.
class RecipeLine {
  RecipeLine({
    required this.ingredientId,
    required this.ingredientName,
    required this.packPriceSen,
    required this.packSize,
    required this.packUnit,
    required this.qty,
    required this.qtyUnit,
  });
  final int ingredientId;
  final String ingredientName;
  final int packPriceSen;
  final double packSize;
  final String packUnit;
  final double qty;
  final String qtyUnit;

  IngredientLine toEngine() => IngredientLine(
        name: ingredientName,
        price: packPriceSen / 100.0,
        size: packSize,
        packUnit: packUnit,
        used: qty,
        usedUnit: qtyUnit,
      );
}

class RecipeDetail {
  RecipeDetail(this.recipe, this.lines);
  final Recipe recipe;
  final List<RecipeLine> lines;

  /// Cost is always computed from CURRENT ingredient prices through the verified engine.
  CalcResult calc() => calculate(CalcInput(
        lines: lines.map((l) => l.toEngine()).toList(),
        servings: recipe.servings,
        margin: recipe.targetMargin,
        otherCosts: recipe.otherCostsSen / 100.0,
        ownPrice: recipe.ownPriceSen == null ? null : recipe.ownPriceSen! / 100.0,
      ));
}

class RecipeSummary {
  RecipeSummary(this.id, this.name, this.costPerServingSen, this.suggestedSen, this.ownPriceSen);
  final int id;
  final String name;
  final double costPerServingSen;
  final double? suggestedSen;
  final int? ownPriceSen;
}

class SaleRow {
  SaleRow(this.id, this.recipeId, this.itemName, this.quantity, this.unitPriceSen, this.unitCostSen, this.soldOn);
  final int id;
  final int? recipeId;
  final String itemName;
  final double quantity;
  final int unitPriceSen;
  final double? unitCostSen;
  final String soldOn;
  double get revenueSen => quantity * unitPriceSen;
  double? get profitSen => unitCostSen == null ? null : quantity * (unitPriceSen - unitCostSen!);
}

class ExpenseRow {
  ExpenseRow(this.id, this.category, this.amountSen, this.spentOn, this.note);
  final int id;
  final String category;
  final int amountSen;
  final String spentOn;
  final String? note;
}

class Totals {
  Totals(this.revenueSen, this.cogsSen, this.costedRevenueSen, this.expensesSen);
  final double revenueSen;
  final double cogsSen;
  final double costedRevenueSen;
  final double expensesSen;

  /// Estimated profit = sales - expenses (cash view). NOT net profit.
  double get estimatedProfitSen => revenueSen - expensesSen;

  /// Estimated gross profit from recipe-linked sales only: revenue - recipe cost.
  double get grossProfitSen => costedRevenueSen - cogsSen;
}

class BucketRow {
  BucketRow(this.bucket, this.revenueSen, this.grossProfitSen, this.expensesSen);
  final String bucket;
  final double revenueSen;
  final double grossProfitSen;
  final double expensesSen;
  double get estimatedProfitSen => revenueSen - expensesSen;
}

class StockMove {
  StockMove(this.kind, this.qtyBase, this.note, this.movedOn);
  final String kind;
  final double qtyBase;
  final String? note;
  final String movedOn;
}

class UsageRow {
  UsageRow(this.name, this.packUnit, this.usedBase);
  final String name;
  final String packUnit;
  final double usedBase;
}

const kExpenseCategories = [
  'ingredients',
  'packaging',
  'utilities',
  'labour',
  'rent',
  'delivery',
  'marketing',
  'equipment',
  'other',
];
