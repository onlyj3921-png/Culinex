import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/money.dart';
import '../core/strings.dart';
import '../data/models.dart';
import '../data/queries.dart';
import '../data/repository.dart';

final databaseProvider = Provider<Database>((ref) => throw UnimplementedError('override in main'));
final queriesProvider = Provider<Queries>((ref) => throw UnimplementedError('override in main'));
final repoProvider = Provider<Repo>((ref) => Repo(ref.watch(databaseProvider), ref.watch(queriesProvider)));

/// Bumped after every write so dependent providers reload.
final dataVersionProvider = StateProvider<int>((ref) => 0);
void bump(WidgetRef ref) => ref.read(dataVersionProvider.notifier).state++;

final langProvider = StateProvider<String>((ref) => 'en');
final tProvider = Provider<T>((ref) => T(ref.watch(langProvider)));

final ingredientsProvider = FutureProvider.autoDispose.family<List<Ingredient>, String>((ref, s) {
  ref.watch(dataVersionProvider);
  return ref.watch(repoProvider).ingredients(search: s);
});

final recipesProvider = FutureProvider.autoDispose.family<List<RecipeSummary>, String>((ref, s) {
  ref.watch(dataVersionProvider);
  return ref.watch(repoProvider).recipes(search: s);
});

final salesProvider = FutureProvider<List<SaleRow>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repoProvider).sales();
});

final expensesProvider = FutureProvider<List<ExpenseRow>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repoProvider).expenses();
});

final lowStockProvider = FutureProvider<List<Ingredient>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repoProvider).lowStock();
});

final trackedProvider = FutureProvider<List<Ingredient>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repoProvider).trackedIngredients();
});

final inventoryValueProvider = FutureProvider<double>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repoProvider).inventoryValueSen();
});

enum PeriodKind { day, week, month }

/// Inclusive ISO date range for the current day / Monday-Sunday week / calendar month.
({String from, String to}) currentRange(PeriodKind k, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  switch (k) {
    case PeriodKind.day:
      return (from: isoDate(today), to: isoDate(today));
    case PeriodKind.week:
      final mon = today.subtract(Duration(days: today.weekday - 1));
      return (from: isoDate(mon), to: isoDate(mon.add(const Duration(days: 6))));
    case PeriodKind.month:
      return (from: isoDate(DateTime(today.year, today.month, 1)), to: isoDate(DateTime(today.year, today.month + 1, 0)));
  }
}

/// Range shown in the trend report: last 14 days / 8 weeks / 6 months.
({String from, String to, String fmt}) trendRange(PeriodKind k, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  switch (k) {
    case PeriodKind.day:
      return (from: isoDate(today.subtract(const Duration(days: 13))), to: isoDate(today), fmt: '%Y-%m-%d');
    case PeriodKind.week:
      final mon = today.subtract(Duration(days: today.weekday - 1));
      return (from: isoDate(mon.subtract(const Duration(days: 49))), to: isoDate(mon.add(const Duration(days: 6))), fmt: '%Y-W%W');
    case PeriodKind.month:
      return (from: isoDate(DateTime(today.year, today.month - 5, 1)), to: isoDate(DateTime(today.year, today.month + 1, 0)), fmt: '%Y-%m');
  }
}

final totalsProvider = FutureProvider.family<Totals, PeriodKind>((ref, k) {
  ref.watch(dataVersionProvider);
  final r = currentRange(k);
  return ref.watch(repoProvider).totals(r.from, r.to);
});

final bucketsProvider = FutureProvider.family<List<BucketRow>, PeriodKind>((ref, k) {
  ref.watch(dataVersionProvider);
  final r = trendRange(k);
  return ref.watch(repoProvider).buckets(r.fmt, r.from, r.to);
});

final usageProvider = FutureProvider<List<UsageRow>>((ref) {
  ref.watch(dataVersionProvider);
  final r = currentRange(PeriodKind.month);
  return ref.watch(repoProvider).stockUsage(r.from, r.to);
});

final categoryTotalsProvider = FutureProvider.family<List<({String category, int totalSen})>, PeriodKind>((ref, k) {
  ref.watch(dataVersionProvider);
  final r = currentRange(k);
  return ref.watch(repoProvider).expensesByCategory(r.from, r.to);
});
