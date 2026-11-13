import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/features.dart';
import '../core/money.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import 'widgets.dart';

final _reportKind = StateProvider<PeriodKind>((ref) => PeriodKind.day);

/// All numbers come from stored sales/expense rows through SQL (assets/db/queries.sql).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final kind = ref.watch(_reportKind);
    final buckets = ref.watch(bucketsProvider(kind));
    final totals = ref.watch(totalsProvider(kind));
    final adv = ref.watch(canUseProvider(Feature.advancedReports));
    final stock = ref.watch(canUseProvider(Feature.stockTracking));
    return Scaffold(
      appBar: AppBar(title: Text(t('reports'))),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        SegmentedButton<PeriodKind>(
          segments: [
            ButtonSegment(value: PeriodKind.day, label: Text(t('daily'))),
            ButtonSegment(value: PeriodKind.week, label: Text(t('weekly'))),
            ButtonSegment(value: PeriodKind.month, label: Text(t('monthly'))),
          ],
          selected: {kind},
          onSelectionChanged: (s) => ref.read(_reportKind.notifier).state = s.first,
        ),
        SectionTitle(kind == PeriodKind.day ? t('today') : kind == PeriodKind.week ? t('this_week') : t('this_month')),
        totals.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('${t('error')}: $e'),
          data: (d) => AppCard(
            child: Column(children: [
              ResultTile(t('total_sales'), rm(d.revenueSen / 100)),
              ResultTile(t('total_expenses'), rm(d.expensesSen / 100)),
              const Divider(),
              ResultTile(t('estimated_profit'), rm(d.estimatedProfitSen / 100), big: true),
              ResultTile(t('est_gross_profit'), rm(d.grossProfitSen / 100)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const ProfitDisclaimer(),
        SectionTitle(t('trend')),
        if (!adv)
          const PremiumLock(compact: true)
        else
          buckets.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('${t('error')}: $e'),
            data: (rows) => rows.isEmpty ? Text(t('no_data'), style: const TextStyle(color: Brand.grey)) : AppCard(child: SizedBox(height: 160, child: CustomPaint(painter: _BarPainter(rows), size: Size.infinite))),
          ),
        SectionTitle(t('breakdown')),
        buckets.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (rows) => rows.isEmpty
              ? Text(t('no_data'), style: const TextStyle(color: Brand.grey))
              : AppCard(
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 18,
                      headingTextStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      dataTextStyle: const TextStyle(fontSize: 12, color: Brand.black),
                      columns: [
                        DataColumn(label: Text(t('period'))),
                        DataColumn(label: Text(t('total_sales')), numeric: true),
                        DataColumn(label: Text(t('total_expenses')), numeric: true),
                        DataColumn(label: Text(t('estimated_profit')), numeric: true),
                      ],
                      rows: [
                        for (final b in rows.reversed)
                          DataRow(cells: [
                            DataCell(Text(b.bucket)),
                            DataCell(Text(rm(b.revenueSen / 100))),
                            DataCell(Text(rm(b.expensesSen / 100))),
                            DataCell(Text(rm(b.estimatedProfitSen / 100), style: TextStyle(color: b.estimatedProfitSen < 0 ? Brand.danger : Brand.black, fontWeight: FontWeight.w700))),
                          ]),
                      ],
                    ),
                  ),
                ),
        ),
        SectionTitle(t('stock_reports')),
        if (!stock)
          const PremiumLock(compact: true)
        else
          _StockReport(t: t),
        const SizedBox(height: 8),
        Text(t('week_note'), style: const TextStyle(fontSize: 11, color: Brand.grey)),
        const SizedBox(height: 30),
      ]),
    );
  }
}

class _StockReport extends ConsumerWidget {
  const _StockReport({required this.t});
  final T t;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(inventoryValueProvider).valueOrNull ?? 0;
    final usage = ref.watch(usageProvider).valueOrNull ?? const <UsageRow>[];
    final low = ref.watch(lowStockProvider).valueOrNull ?? const <Ingredient>[];
    return AppCard(
      child: Column(children: [
        ResultTile(t('inventory_value'), rm(value / 100), big: true),
        const Divider(),
        Align(alignment: Alignment.centerLeft, child: Text(t('usage_this_month'), style: const TextStyle(fontWeight: FontWeight.w800))),
        if (usage.isEmpty) Align(alignment: Alignment.centerLeft, child: Text(t('no_usage'), style: const TextStyle(color: Brand.grey))),
        for (final u in usage) ResultTile(u.name, fmtBase(u.usedBase, u.packUnit)),
        const Divider(),
        Align(alignment: Alignment.centerLeft, child: Text(t('low_stock_items'), style: const TextStyle(fontWeight: FontWeight.w800))),
        if (low.isEmpty) Align(alignment: Alignment.centerLeft, child: Text(t('none'), style: const TextStyle(color: Brand.grey))),
        for (final g in low) ResultTile(g.name, fmtBase(g.stockBase, g.packUnit)),
      ]),
    );
  }
}

/// Simple bar chart of estimated profit per bucket (green = profit, red = loss).
class _BarPainter extends CustomPainter {
  _BarPainter(this.rows);
  final List<BucketRow> rows;
  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;
    final vals = rows.map((r) => r.estimatedProfitSen).toList();
    final maxAbs = vals.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
    if (maxAbs == 0) return;
    final mid = size.height / 2;
    final w = size.width / rows.length;
    final axis = Paint()..color = const Color(0xFFCCCCCC);
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), axis);
    for (var i = 0; i < vals.length; i++) {
      final h = (vals[i].abs() / maxAbs) * (mid - 6);
      final p = Paint()..color = vals[i] >= 0 ? Brand.ok : Brand.danger;
      final left = i * w + w * 0.15;
      final rect = vals[i] >= 0 ? Rect.fromLTWH(left, mid - h, w * 0.7, h) : Rect.fromLTWH(left, mid, w * 0.7, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.rows != rows;
}
