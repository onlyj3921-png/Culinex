import 'package:culinex_engine/culinex_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets.dart';

class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final sales = ref.watch(salesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('nav_sales'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: Text(t('record_sale')),
      ),
      body: sales.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${t('error')}: $e')),
        data: (rows) => rows.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t('no_sales'), textAlign: TextAlign.center, style: const TextStyle(color: Brand.grey))))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (c, i) {
                  final s = rows[i];
                  return AppCard(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.itemName, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${s.soldOn} · ${fmtQty(s.quantity)} × ${rmSen(s.unitPriceSen)}', style: const TextStyle(color: Brand.grey, fontSize: 12)),
                          if (s.profitSen != null) Text('${t('est_gross_profit')}: ${rmSen(s.profitSen)}', style: const TextStyle(color: Brand.ok, fontSize: 12)),
                        ]),
                      ),
                      Text(rmSen(s.revenueSen), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      IconButton(
                        tooltip: t('void_sale'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmDialog(context, ref, t('confirm_void'))) {
                            await ref.read(repoProvider).voidSale(s.id);
                            bump(ref);
                          }
                        },
                      ),
                    ]),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final recipes = await ref.read(repoProvider).recipes();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: _SaleForm(recipes: recipes),
      ),
    );
  }
}

class _SaleForm extends ConsumerStatefulWidget {
  const _SaleForm({required this.recipes});
  final List<RecipeSummary> recipes;
  @override
  ConsumerState<_SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends ConsumerState<_SaleForm> {
  RecipeSummary? _recipe;
  final _item = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();
  String _date = todayIso();

  @override
  void dispose() {
    _item.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final qty = parseNum(_qty.text);
    final price = parseNum(_price.text);
    final name = _recipe?.name ?? _item.text.trim();
    if (name.isEmpty) return showMsg(context, t('need_name'));
    if (qty == null || qty <= 0) return showMsg(context, t('err_qty'));
    if (price == null || price < 0) return showMsg(context, t('err_price'));
    try {
      final res = await ref.read(repoProvider).recordSale(
            recipeId: _recipe?.id,
            itemName: name,
            quantity: qty,
            unitPriceSen: toSen(price),
            soldOn: _date,
          );
      bump(ref);
      if (!mounted) return;
      showMsg(context, res.costed ? t('saved') : t('saved_no_cost'));
      Navigator.pop(context);
    } catch (e) {
      showMsg(context, '${t('error')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('record_sale'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: deco(t('linked_recipe')),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              isDense: true,
              value: _recipe?.id,
              hint: Text(t('none_free_item')),
              items: [for (final r in widget.recipes) DropdownMenuItem(value: r.id, child: Text(r.name))],
              onChanged: (v) => setState(() {
                _recipe = widget.recipes.firstWhere((r) => r.id == v);
                final p = _recipe!.ownPriceSen != null ? _recipe!.ownPriceSen!.toDouble() : _recipe!.suggestedSen;
                if (p != null) _price.text = (p / 100).toStringAsFixed(2);
              }),
            ),
          ),
        ),
        if (_recipe != null)
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() => _recipe = null), child: Text(t('clear')))),
        if (_recipe == null) ...[
          const SizedBox(height: 10),
          TextField(controller: _item, decoration: deco(t('item_name'))),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('quantity')))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('unit_price'), prefix: 'RM '))),
        ]),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(_date),
          onPressed: () async {
            final d = await pickDate(context, _date);
            if (d != null) setState(() => _date = d);
          },
        ),
        const SizedBox(height: 14),
        FilledButton(onPressed: _save, child: Text(t('save'))),
      ]),
    ),
    );
  }
}
