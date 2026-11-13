import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/features.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets.dart';

/// PREMIUM. Locked in release builds until real subscriptions exist.
class StockScreen extends ConsumerWidget {
  const StockScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    if (!ref.watch(canUseProvider(Feature.stockTracking))) {
      return Scaffold(appBar: AppBar(title: Text(t('stock'))), body: const PremiumLock());
    }
    final tracked = ref.watch(trackedProvider);
    final value = ref.watch(inventoryValueProvider).valueOrNull ?? 0;
    final usage = ref.watch(usageProvider).valueOrNull ?? const <UsageRow>[];
    return Scaffold(
      appBar: AppBar(title: Text(t('stock'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _track(context, ref),
        icon: const Icon(Icons.add),
        label: Text(t('track_ingredient')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 90), children: [
        AppCard(child: ResultTile(t('inventory_value'), rm(value / 100), big: true)),
        SectionTitle(t('stock_levels')),
        tracked.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('${t('error')}: $e'),
          data: (rows) => rows.isEmpty
              ? Text(t('no_tracked'), style: const TextStyle(color: Brand.grey))
              : Column(children: [
                  for (final g in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _actions(context, ref, g),
                        child: AppCard(
                          child: Row(children: [
                            Expanded(child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                            if (g.isLow)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFFFDE7E4), borderRadius: BorderRadius.circular(8)),
                                child: Text(t('low'), style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w700, fontSize: 12)),
                              ),
                            Text(fmtBase(g.stockBase, g.packUnit), style: const TextStyle(fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      ),
                    ),
                ]),
        ),
        SectionTitle(t('usage_this_month')),
        if (usage.isEmpty)
          Text(t('no_usage'), style: const TextStyle(color: Brand.grey))
        else
          AppCard(
            child: Column(children: [for (final u in usage) ResultTile(u.name, fmtBase(u.usedBase, u.packUnit))]),
          ),
        const SizedBox(height: 8),
        Text(t('stock_note'), style: const TextStyle(fontSize: 12, color: Brand.grey)),
      ]),
    );
  }

  Future<void> _track(BuildContext context, WidgetRef ref) async {
    final t = ref.read(tProvider);
    final repo = ref.read(repoProvider);
    final all = (await repo.ingredients()).where((g) => !g.trackStock).toList();
    if (!context.mounted) return;
    if (all.isEmpty) return showMsg(context, t('nothing_to_track'));
    final picked = await showModalBottomSheet<Ingredient>(
      context: context,
      builder: (c) => ListView(children: [for (final g in all) ListTile(title: Text(g.name), onTap: () => Navigator.pop(c, g))]),
    );
    if (picked == null) return;
    await repo.saveIngredient(Ingredient(
      id: picked.id,
      name: picked.name,
      packUnit: picked.packUnit,
      packSize: picked.packSize,
      packPriceSen: picked.packPriceSen,
      trackStock: true,
      lowStockBase: picked.lowStockBase,
    ));
    bump(ref);
  }

  Future<void> _actions(BuildContext context, WidgetRef ref, Ingredient g) async {
    final t = ref.read(tProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.add_box_outlined), title: Text(t('stock_in')), onTap: () => Navigator.pop(c, 'in')),
          ListTile(leading: const Icon(Icons.indeterminate_check_box_outlined), title: Text(t('stock_out')), onTap: () => Navigator.pop(c, 'out')),
          ListTile(leading: const Icon(Icons.tune), title: Text(t('stock_adjust')), onTap: () => Navigator.pop(c, 'adj')),
          ListTile(leading: const Icon(Icons.history), title: Text(t('stock_history')), onTap: () => Navigator.pop(c, 'hist')),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'hist') return _history(context, ref, g);
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${g.name} · ${t(choice == 'in' ? 'stock_in' : choice == 'out' ? 'stock_out' : 'stock_adjust')}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (choice == 'adj') Text('${t('stock_now')}: ${fmtBase(g.stockBase, g.packUnit)}'),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: deco(choice == 'adj' ? t('count_now') : t('quantity'), suffix: g.packUnit == 'kg' || g.packUnit == 'g' ? 'g' : (g.packUnit == 'pcs' ? 'pcs' : 'ml')),
          ),
          const SizedBox(height: 6),
          Text(t('base_unit_hint'), style: const TextStyle(fontSize: 12, color: Brand.grey)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('save'))),
        ],
      ),
    );
    final v = parseNum(c.text); // controller not disposed: the dialog may still be animating out
    if (ok != true || v == null || v < 0 || !context.mounted) return;
    final repo = ref.read(repoProvider);
    try {
      if (choice == 'in') {
        if (v == 0) return;
        await repo.addMovement(ingredientId: g.id!, kind: 'stock_in', qtyBase: v, movedOn: todayIso());
      } else if (choice == 'out') {
        if (v == 0) return;
        await repo.addMovement(ingredientId: g.id!, kind: 'stock_out', qtyBase: -v, movedOn: todayIso());
      } else {
        final delta = v - g.stockBase;
        if (delta == 0) return;
        await repo.addMovement(ingredientId: g.id!, kind: 'adjustment', qtyBase: delta, note: 'count', movedOn: todayIso());
      }
      bump(ref);
    } catch (e) {
      if (context.mounted) showMsg(context, '${t('error')}: $e');
    }
  }

  Future<void> _history(BuildContext context, WidgetRef ref, Ingredient g) async {
    final t = ref.read(tProvider);
    final rows = await ref.read(repoProvider).movements(g.id!);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.all(14), children: [
          Text('${g.name} · ${t('stock_history')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (rows.isEmpty) Text(t('no_usage')),
          for (final m in rows)
            ListTile(
              dense: true,
              title: Text(t('kind_${m.kind}')),
              subtitle: Text('${m.movedOn}${m.note == null ? '' : ' · ${m.note}'}'),
              trailing: Text('${m.qtyBase >= 0 ? '+' : ''}${fmtBase(m.qtyBase, g.packUnit)}', style: TextStyle(fontWeight: FontWeight.w800, color: m.qtyBase >= 0 ? Brand.ok : Brand.danger)),
            ),
        ]),
      ),
    );
  }
}
