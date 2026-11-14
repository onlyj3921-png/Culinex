import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/features.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import 'widgets.dart';

final _dashPeriod = StateProvider<PeriodKind>((ref) => PeriodKind.day);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final kind = ref.watch(_dashPeriod);
    final totals = ref.watch(totalsProvider(kind));
    final canStock = ref.watch(canUseProvider(Feature.lowStockAlerts));
    final low = canStock ? (ref.watch(lowStockProvider).valueOrNull ?? const <Ingredient>[]) : const <Ingredient>[];
    return Scaffold(
      appBar: AppBar(title: const Text('CULINEX')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text(Brand.tagline, style: TextStyle(color: Brand.grey, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        SegmentedButton<PeriodKind>(
          segments: [
            ButtonSegment(value: PeriodKind.day, label: Text(t('today'))),
            ButtonSegment(value: PeriodKind.week, label: Text(t('this_week'))),
            ButtonSegment(value: PeriodKind.month, label: Text(t('this_month'))),
          ],
          selected: {kind},
          onSelectionChanged: (s) => ref.read(_dashPeriod.notifier).state = s.first,
        ),
        const SizedBox(height: 12),
        totals.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
          error: (e, _) => Text('${t('error')}: $e'),
          data: (d) => Column(children: [
            AppCard(
              child: Column(children: [
                ResultTile(t('total_sales'), rm(d.revenueSen / 100)),
                ResultTile(t('total_expenses'), rm(d.expensesSen / 100)),
                const Divider(),
                ResultTile(t('estimated_profit'), rm(d.estimatedProfitSen / 100), big: true),
                ResultTile(t('est_gross_profit'), rm(d.grossProfitSen / 100)),
              ]),
            ),
            const SizedBox(height: 8),
            Text(t('dash_note'), style: const TextStyle(fontSize: 12, color: Brand.grey)),
          ]),
        ),
        const SizedBox(height: 10),
        const ProfitDisclaimer(),
        if (low.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: InkWell(
              onTap: () => context.push('/stock'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFDE7E4), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.warning_amber, color: Brand.danger),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t('low_stock_banner').replaceAll('{n}', '${low.length}'), style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.danger))),
                ]),
              ),
            ),
          ),
        SectionTitle(t('quick_access')),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            _tile(context, Icons.calculate, t('nav_calc'), '/calculator', go: true),
            _tile(context, Icons.menu_book, t('nav_recipes'), '/recipes', go: true),
            _tile(context, Icons.eco_outlined, t('ingredients'), '/ingredients'),
            _tile(context, Icons.point_of_sale, t('nav_sales'), '/sales', go: true),
            _tile(context, Icons.receipt_long, t('expenses'), '/expenses'),
            _tile(context, Icons.bar_chart, t('reports'), '/reports'),
            _tile(context, Icons.inventory_2_outlined, t('stock'), '/stock', lock: !ref.watch(canUseProvider(Feature.stockTracking))),
          ],
        ),
      ]),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, String path, {bool go = false, bool lock = false}) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => go ? context.go(path) : context.push(path),
        child: AppCard(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(lock ? Icons.lock_outline : icon, color: Brand.gold, size: 28),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
