import 'package:culinex_engine/culinex_engine.dart';
import 'package:sqflite/sqflite.dart';

import '../core/money.dart';
import 'models.dart';
import 'queries.dart';

/// All database access. Every money value is stored as integer sen.
class Repo {
  Repo(this.db, this.q);
  final Database db;
  final Queries q;

  // ---------------- ingredients ----------------
  Future<List<Ingredient>> ingredients({String search = ''}) async {
    final rows = await db.query('ingredients',
        where: 'deleted_at IS NULL AND name LIKE ?',
        whereArgs: ['%$search%'],
        orderBy: 'name COLLATE NOCASE');
    return rows.map(Ingredient.fromMap).toList();
  }

  Future<Ingredient?> ingredient(int id) async {
    final rows = await db.query('ingredients', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
    return rows.isEmpty ? null : Ingredient.fromMap(rows.first);
  }

  /// Inserts or updates. Throws a DatabaseException (readable message) on rule violations.
  Future<int> saveIngredient(Ingredient i) async {
    final values = <String, Object?>{
      'name': i.name.trim(),
      'family': i.familyName,
      'pack_unit': i.packUnit,
      'pack_size': i.packSize,
      'pack_price_sen': i.packPriceSen,
      'track_stock': i.trackStock ? 1 : 0,
      'low_stock_base': i.lowStockBase,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (i.id == null) return db.insert('ingredients', values);
    await db.update('ingredients', values, where: 'id = ?', whereArgs: [i.id]);
    return i.id!;
  }

  Future<bool> ingredientUsedInRecipes(int id) async {
    final r = await db.rawQuery('SELECT COUNT(*) c FROM recipe_items ri JOIN recipes r ON r.id=ri.recipe_id WHERE ri.ingredient_id=? AND r.deleted_at IS NULL', [id]);
    return (r.first['c'] as int) > 0;
  }

  Future<void> deleteIngredient(int id) =>
      db.update('ingredients', {'deleted_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);

  Future<List<({int id, String name})>> affectedRecipes(int ingredientId) async {
    final rows = await db.rawQuery(q['affected_recipes'], [ingredientId]);
    return rows.map((r) => (id: r['id'] as int, name: r['name'] as String)).toList();
  }

  // ---------------- recipes ----------------
  Future<List<RecipeSummary>> recipes({String search = ''}) async {
    final rows = await db.rawQuery(q['recipe_list'], ['%$search%']);
    return rows.map((r) {
      final servings = (r['servings'] as num).toDouble();
      final cps = ((r['ingredient_cost_sen'] as num).toDouble() + (r['other_costs_sen'] as int)) / servings;
      final m = (r['target_margin'] as num).toDouble();
      return RecipeSummary(r['recipe_id'] as int, r['name'] as String, cps, m < 1 ? cps / (1 - m) : null, r['own_price_sen'] as int?);
    }).toList();
  }

  Future<RecipeDetail?> recipe(int id) async {
    final rows = await db.query('recipes', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final items = await db.rawQuery(q['recipe_items_detail'], [id]);
    return RecipeDetail(
      Recipe.fromMap(rows.first),
      items
          .map((m) => RecipeLine(
                ingredientId: m['ingredient_id'] as int,
                ingredientName: m['ing_name'] as String,
                packPriceSen: m['pack_price_sen'] as int,
                packSize: (m['pack_size'] as num).toDouble(),
                packUnit: m['pack_unit'] as String,
                qty: (m['qty'] as num).toDouble(),
                qtyUnit: m['qty_unit'] as String,
              ))
          .toList(),
    );
  }

  /// Saves a recipe and replaces its lines atomically. Past sales are unaffected (cost snapshots).
  Future<int> saveRecipe(Recipe r, List<({int ingredientId, double qty, String unit})> items) {
    return db.transaction((txn) async {
      final values = <String, Object?>{
        'name': r.name.trim(),
        'servings': r.servings,
        'target_margin': r.targetMargin,
        'other_costs_sen': r.otherCostsSen,
        'own_price_sen': r.ownPriceSen,
        'notes': r.notes,
        'updated_at': DateTime.now().toIso8601String(),
      };
      int id;
      if (r.id == null) {
        id = await txn.insert('recipes', values);
      } else {
        id = r.id!;
        await txn.update('recipes', values, where: 'id = ?', whereArgs: [id]);
        await txn.delete('recipe_items', where: 'recipe_id = ?', whereArgs: [id]);
      }
      for (final it in items) {
        await txn.insert('recipe_items', {
          'recipe_id': id,
          'ingredient_id': it.ingredientId,
          'qty': it.qty,
          'qty_unit': it.unit,
        });
      }
      return id;
    });
  }

  Future<int?> duplicateRecipe(int id, String copySuffix) async {
    final d = await recipe(id);
    if (d == null) return null;
    final r = d.recipe;
    return saveRecipe(
      Recipe(
          name: '${r.name} $copySuffix',
          servings: r.servings,
          targetMargin: r.targetMargin,
          otherCostsSen: r.otherCostsSen,
          ownPriceSen: r.ownPriceSen,
          notes: r.notes),
      d.lines.map((l) => (ingredientId: l.ingredientId, qty: l.qty, unit: l.qtyUnit)).toList(),
    );
  }

  Future<void> deleteRecipe(int id) =>
      db.update('recipes', {'deleted_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);

  /// Turns Advanced Calculator rows into saved ingredients + a recipe.
  /// Existing ingredients (same name) keep their stored price; returns how many were kept.
  Future<({int recipeId, int keptExisting})> saveCalculatorAsRecipe({
    required String name,
    required List<IngredientLine> lines,
    required double servings,
    required double margin,
    required double otherCosts,
    double? ownPrice,
  }) {
    return db.transaction((txn) async {
      var kept = 0;
      final items = <({int ingredientId, double qty, String unit})>[];
      for (final l in lines) {
        if (evaluateRow(l).status != RowStatus.ok) continue;
        final nm = l.name!.trim();
        final found = await txn.query('ingredients',
            where: 'deleted_at IS NULL AND lower(name) = lower(?)', whereArgs: [nm]);
        int ingId;
        if (found.isNotEmpty) {
          ingId = found.first['id'] as int;
          kept++;
        } else {
          final pu = findUnit(l.packUnit)!;
          ingId = await txn.insert('ingredients', {
            'name': nm,
            'family': pu.family.name,
            'pack_unit': pu.code,
            'pack_size': l.size,
            'pack_price_sen': toSen(l.price!),
          });
        }
        items.add((ingredientId: ingId, qty: l.used!, unit: findUnit(l.usedUnit)!.code));
      }
      final rid = await txn.insert('recipes', {
        'name': name.trim(),
        'servings': servings,
        'target_margin': margin,
        'other_costs_sen': toSen(otherCosts),
        'own_price_sen': ownPrice == null ? null : toSen(ownPrice),
      });
      for (final it in items) {
        await txn.insert('recipe_items', {'recipe_id': rid, 'ingredient_id': it.ingredientId, 'qty': it.qty, 'qty_unit': it.unit});
      }
      return (recipeId: rid, keptExisting: kept);
    });
  }

  // ---------------- sales ----------------
  /// Records a sale. If linked to a recipe, the cost per serving at THIS moment is stored
  /// (snapshot) so later price changes never alter history. Returns false in `costed` if the
  /// recipe could not be costed (profit is then not counted for that sale).
  Future<({int id, bool costed})> recordSale({
    int? recipeId,
    required String itemName,
    required double quantity,
    required int unitPriceSen,
    required String soldOn,
  }) async {
    double? costSen;
    if (recipeId != null) {
      final d = await recipe(recipeId);
      final cps = d?.calc().costPerServing;
      if (cps != null) costSen = cps * 100;
    }
    final id = await db.insert('sales', {
      'recipe_id': recipeId,
      'item_name': itemName.trim(),
      'quantity': quantity,
      'unit_price_sen': unitPriceSen,
      'unit_cost_sen': costSen,
      'sold_on': soldOn,
    });
    return (id: id, costed: recipeId == null || costSen != null);
  }

  Future<List<SaleRow>> sales({int limit = 100}) async {
    final rows = await db.query('sales', where: 'deleted_at IS NULL', orderBy: 'sold_on DESC, id DESC', limit: limit);
    return rows
        .map((m) => SaleRow(m['id'] as int, m['recipe_id'] as int?, m['item_name'] as String, (m['quantity'] as num).toDouble(),
            m['unit_price_sen'] as int, (m['unit_cost_sen'] as num?)?.toDouble(), m['sold_on'] as String))
        .toList();
  }

  /// Voids a sale (soft delete). A database trigger puts tracked stock back.
  Future<void> voidSale(int id) =>
      db.update('sales', {'deleted_at': DateTime.now().toIso8601String()}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);

  // ---------------- expenses ----------------
  Future<int> addExpense({required String category, required int amountSen, required String spentOn, String? note}) =>
      db.insert('expenses', {'category': category, 'amount_sen': amountSen, 'spent_on': spentOn, 'note': note});

  Future<List<ExpenseRow>> expenses({int limit = 200}) async {
    final rows = await db.query('expenses', where: 'deleted_at IS NULL', orderBy: 'spent_on DESC, id DESC', limit: limit);
    return rows
        .map((m) => ExpenseRow(m['id'] as int, m['category'] as String, m['amount_sen'] as int, m['spent_on'] as String, m['note'] as String?))
        .toList();
  }

  Future<void> deleteExpense(int id) =>
      db.update('expenses', {'deleted_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);

  Future<List<({String category, int totalSen})>> expensesByCategory(String from, String to) async {
    final rows = await db.rawQuery(q['expenses_by_category'], [from, to]);
    return rows.map((r) => (category: r['category'] as String, totalSen: (r['total_sen'] as num).toInt())).toList();
  }

  // ---------------- reports ----------------
  Future<Totals> totals(String from, String to) async {
    final r = (await db.rawQuery(q['period_totals'], [from, to])).first;
    double d(String k) => (r[k] as num).toDouble();
    return Totals(d('revenue_sen'), d('cogs_sen'), d('costed_revenue_sen'), d('expenses_sen'));
  }

  /// [fmt] is a strftime format: daily '%Y-%m-%d', weekly '%Y-W%W', monthly '%Y-%m'.
  Future<List<BucketRow>> buckets(String fmt, String from, String to) async {
    final s = await db.rawQuery(q['sales_by_bucket'], [fmt, from, to]);
    final e = await db.rawQuery(q['expenses_by_bucket'], [fmt, from, to]);
    final map = <String, List<double>>{};
    for (final r in s) {
      map[r['bucket'] as String] = [(r['revenue_sen'] as num).toDouble(), (r['gross_profit_sen'] as num?)?.toDouble() ?? 0, 0];
    }
    for (final r in e) {
      final b = map.putIfAbsent(r['bucket'] as String, () => [0, 0, 0]);
      b[2] = (r['expenses_sen'] as num).toDouble();
    }
    final keys = map.keys.toList()..sort();
    return [for (final k in keys) BucketRow(k, map[k]![0], map[k]![1], map[k]![2])];
  }

  // ---------------- stock (Premium in the UI) ----------------
  Future<List<Ingredient>> trackedIngredients() async {
    final rows = await db.query('ingredients', where: 'deleted_at IS NULL AND track_stock = 1', orderBy: 'name COLLATE NOCASE');
    return rows.map(Ingredient.fromMap).toList();
  }

  Future<void> addMovement({required int ingredientId, required String kind, required double qtyBase, String? note, required String movedOn}) =>
      db.insert('stock_movements', {'ingredient_id': ingredientId, 'kind': kind, 'qty_base': qtyBase, 'note': note, 'moved_on': movedOn});

  Future<List<StockMove>> movements(int ingredientId) async {
    final rows = await db.query('stock_movements', where: 'ingredient_id = ?', whereArgs: [ingredientId], orderBy: 'moved_on DESC, id DESC', limit: 200);
    return rows.map((m) => StockMove(m['kind'] as String, (m['qty_base'] as num).toDouble(), m['note'] as String?, m['moved_on'] as String)).toList();
  }

  Future<double> inventoryValueSen() async => ((await db.rawQuery(q['inventory_value'])).first['value_sen'] as num).toDouble();

  Future<List<Ingredient>> lowStock() async => (await db.rawQuery(q['low_stock'])).map((m) => Ingredient(
        id: m['id'] as int,
        name: m['name'] as String,
        packUnit: m['pack_unit'] as String,
        packSize: 1,
        packPriceSen: 0,
        trackStock: true,
        stockBase: (m['stock_base'] as num).toDouble(),
        lowStockBase: (m['low_stock_base'] as num?)?.toDouble(),
      )).toList();

  Future<List<UsageRow>> stockUsage(String from, String to) async =>
      (await db.rawQuery(q['stock_usage'], [from, to])).map((m) => UsageRow(m['name'] as String, m['pack_unit'] as String, (m['used_base'] as num).toDouble())).toList();

  // ---------------- settings ----------------
  Future<String?> meta(String key) async {
    final r = await db.query('app_meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) =>
      db.insert('app_meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
}

/// Readable text for common database rule violations.
String friendlyDbError(Object e) {
  final s = e.toString();
  if (s.contains('unit type')) return 'unit type';
  if (s.contains('CHECK constraint')) return 'check';
  return s;
}

String todayIso() => isoDate(DateTime.now());
