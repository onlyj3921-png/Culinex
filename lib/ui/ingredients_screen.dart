import 'package:culinex_engine/culinex_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/features.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import 'widgets.dart';

class IngredientsScreen extends ConsumerStatefulWidget {
  const IngredientsScreen({super.key});
  @override
  ConsumerState<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends ConsumerState<IngredientsScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final list = ref.watch(ingredientsProvider(_q));
    return Scaffold(
      appBar: AppBar(title: Text(t('ingredients'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/ingredient/new'),
        icon: const Icon(Icons.add),
        label: Text(t('new_ingredient')),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: TextField(decoration: deco(t('search')).copyWith(prefixIcon: const Icon(Icons.search)), onChanged: (v) => setState(() => _q = v.trim())),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('${t('error')}: $e')),
            data: (rows) => rows.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t('no_ingredients'), textAlign: TextAlign.center, style: const TextStyle(color: Brand.grey))))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, i) {
                      final g = rows[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => context.push('/ingredient/${g.id}'),
                        child: AppCard(
                          child: Row(children: [
                            Expanded(child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                            Text('${rmSen(g.packPriceSen)} / ${fmtQty(g.packSize)} ${g.packUnit}', style: const TextStyle(color: Brand.grey)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

class IngredientEditorScreen extends ConsumerStatefulWidget {
  const IngredientEditorScreen({super.key, required this.idParam});
  final String idParam;
  @override
  ConsumerState<IngredientEditorScreen> createState() => _IngredientEditorState();
}

class _IngredientEditorState extends ConsumerState<IngredientEditorScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _size = TextEditingController();
  final _low = TextEditingController();
  String? _unit;
  bool _track = false;
  bool _loaded = false;
  Ingredient? _orig;
  int? get _id => widget.idParam == 'new' ? null : int.tryParse(widget.idParam);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final id = _id;
    if (id != null) {
      final g = await ref.read(repoProvider).ingredient(id);
      if (g != null && mounted) {
        setState(() {
          _orig = g;
          _name.text = g.name;
          _price.text = (g.packPriceSen / 100).toStringAsFixed(2);
          _size.text = fmtQty(g.packSize);
          _unit = g.packUnit;
          _track = g.trackStock;
          final f = findUnit(g.packUnit)!.factor;
          _low.text = g.lowStockBase == null ? '' : fmtQty(g.lowStockBase! / f);
        });
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _size, _low]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final price = parseNum(_price.text);
    final size = parseNum(_size.text);
    if (_name.text.trim().isEmpty) return showMsg(context, t('need_name'));
    if (price == null || price < 0) return showMsg(context, t('err_price'));
    if (size == null || size <= 0) return showMsg(context, t('err_size'));
    if (_unit == null) return showMsg(context, t('err_unit'));
    final low = parseNum(_low.text);
    final factor = findUnit(_unit)!.factor;
    final repo = ref.read(repoProvider);
    try {
      final id = await repo.saveIngredient(Ingredient(
        id: _id,
        name: _name.text,
        packUnit: _unit!,
        packSize: size,
        packPriceSen: toSen(price),
        trackStock: _track,
        lowStockBase: low == null ? null : low * factor,
      ));
      final changed = _orig != null && (_orig!.packPriceSen != toSen(price) || _orig!.packSize != size || _orig!.packUnit != _unit);
      final affected = changed ? await repo.affectedRecipes(id) : const <({int id, String name})>[];
      bump(ref);
      if (!mounted) return;
      if (affected.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(t('affected_title')),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('affected_body')),
              const SizedBox(height: 8),
              for (final a in affected) Text('• ${a.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(t('ok')))],
          ),
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showMsg(context, e.toString().contains('unit type') ? t('err_family_locked') : '${t('error')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final canTrack = ref.watch(canUseProvider(Feature.stockTracking));
    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? t('new_ingredient') : t('edit_ingredient')),
        actions: [
          if (_id != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final repo = ref.read(repoProvider);
                final used = await repo.ingredientUsedInRecipes(_id!);
                if (!context.mounted) return;
                if (used) return showMsg(context, t('err_in_use'));
                if (await confirmDialog(context, ref, t('confirm_delete'))) {
                  await repo.deleteIngredient(_id!);
                  bump(ref);
                  if (context.mounted) context.pop();
                }
              },
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 48), children: [
              TextField(controller: _name, decoration: deco(t('ingredient'))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('pkg_price'), prefix: 'RM '))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: TextField(controller: _size, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('pkg_size')))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: UnitPicker(label: t('unit'), value: _unit, onChanged: (v) => setState(() => _unit = v))),
              ]),
              const SizedBox(height: 8),
              Text(t('price_update_hint'), style: const TextStyle(fontSize: 12, color: Brand.grey)),
              SectionTitle(t('stock')),
              AppCard(
                child: Column(children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('track_stock')),
                    subtitle: canTrack ? null : Text(t('premium_feature')),
                    secondary: canTrack ? null : const Icon(Icons.lock_outline, color: Brand.gold),
                    value: _track,
                    onChanged: canTrack ? (v) => setState(() => _track = v) : null,
                  ),
                  if (_track && canTrack)
                    TextField(controller: _low, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('low_stock_level'), suffix: _unit ?? '')),
                ]),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _save, child: Text(t('save'))),
            ]),
    );
  }
}
