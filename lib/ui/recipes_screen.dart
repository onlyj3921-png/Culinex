import 'package:culinex_engine/culinex_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/money.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import 'widgets.dart';

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});
  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final list = ref.watch(recipesProvider(_q));
    return Scaffold(
      appBar: AppBar(title: Text(t('nav_recipes'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/recipe/new'),
        icon: const Icon(Icons.add),
        label: Text(t('new_recipe')),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: TextField(
            decoration: deco(t('search'), hint: t('search_recipes')).copyWith(prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('${t('error')}: $e')),
            data: (rows) => rows.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t('no_recipes'), textAlign: TextAlign.center, style: const TextStyle(color: Brand.grey))))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, i) {
                      final r = rows[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => context.push('/recipe/${r.id}'),
                        child: AppCard(
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('${t('cost_per_serving')}: ${rmSen(r.costPerServingSen)}', style: const TextStyle(color: Brand.grey)),
                              ]),
                            ),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(t('suggested_price'), style: const TextStyle(fontSize: 11, color: Brand.grey)),
                              Text(rmSen(r.suggestedSen), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            ]),
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

class _Item {
  Ingredient? ingredient;
  final qty = TextEditingController();
  String? unit;
}

class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({super.key, required this.idParam});
  final String idParam;
  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends ConsumerState<RecipeEditorScreen> {
  final _name = TextEditingController();
  final _servings = TextEditingController(text: '1');
  final _margin = TextEditingController();
  final _other = TextEditingController();
  final _own = TextEditingController();
  final List<_Item> _items = [];
  bool _loaded = false;
  int? get _id => widget.idParam == 'new' ? null : int.tryParse(widget.idParam);

  @override
  void dispose() {
    for (final c in [_name, _servings, _margin, _other, _own]) {
      c.dispose();
    }
    for (final i in _items) {
      i.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _load(List<Ingredient> all) async {
    final id = _id;
    if (id == null) return;
    final d = await ref.read(repoProvider).recipe(id);
    if (d == null || !mounted) return;
    setState(() {
      _name.text = d.recipe.name;
      _servings.text = fmtQty(d.recipe.servings);
      _margin.text = fmtQty(d.recipe.targetMargin * 100);
      _other.text = d.recipe.otherCostsSen == 0 ? '' : (d.recipe.otherCostsSen / 100).toStringAsFixed(2);
      _own.text = d.recipe.ownPriceSen == null ? '' : (d.recipe.ownPriceSen! / 100).toStringAsFixed(2);
      for (final l in d.lines) {
        final it = _Item();
        final matches = all.where((a) => a.id == l.ingredientId);
        it.ingredient = matches.isEmpty ? null : matches.first;
        it.qty.text = fmtQty(l.qty);
        it.unit = l.qtyUnit;
        _items.add(it);
      }
    });
  }

  CalcInput _input() {
    final m = parseNum(_margin.text);
    return CalcInput(
      lines: [
        for (final it in _items)
          if (it.ingredient != null)
            IngredientLine(
              name: it.ingredient!.name,
              price: it.ingredient!.packPriceSen / 100.0,
              size: it.ingredient!.packSize,
              packUnit: it.ingredient!.packUnit,
              used: parseNum(it.qty.text),
              usedUnit: it.unit,
            )
          else
            const IngredientLine(name: 'x'),
      ],
      servings: parseNum(_servings.text),
      margin: m == null ? null : m / 100,
      otherCosts: parseNum(_other.text),
      ownPrice: parseNum(_own.text),
    );
  }

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final input = _input();
    final r = calculate(input);
    if (_name.text.trim().isEmpty) return showMsg(context, t('need_name'));
    if (r.status != InputStatus.ok) return showMsg(context, t(statusKey(r.status)));
    try {
      final id = await ref.read(repoProvider).saveRecipe(
        Recipe(
          id: _id,
          name: _name.text,
          servings: input.servings!,
          targetMargin: input.margin!,
          otherCostsSen: toSen(input.otherCosts ?? 0),
          ownPriceSen: input.ownPrice == null ? null : toSen(input.ownPrice!),
        ),
        [for (final it in _items) (ingredientId: it.ingredient!.id!, qty: parseNum(it.qty.text)!, unit: it.unit!)],
      );
      bump(ref);
      if (!mounted) return;
      showMsg(context, t('saved'));
      if (_id == null) {
        context.pushReplacement('/recipe/$id');
      }
    } catch (e) {
      if (mounted) showMsg(context, '${t('error')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final all = ref.watch(ingredientsProvider('')).valueOrNull ?? const <Ingredient>[];
    if (!_loaded && ref.watch(ingredientsProvider('')).hasValue) {
      _loaded = true; // set before scheduling so the load can never run twice
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(all));
    }
    final input = _input();
    final r = calculate(input);
    String n(Object? v, [String Function(double)? f]) => v is double ? (f ?? rm)(v) : (v is String ? t(_gate(v)) : '—');
    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? t('new_recipe') : t('edit_recipe')),
        actions: [
          if (_id != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                final repo = ref.read(repoProvider);
                if (v == 'dup') {
                  final nid = await repo.duplicateRecipe(_id!, t('copy_suffix'));
                  bump(ref);
                  if (mounted && nid != null) {
                    showMsg(context, t('duplicated'));
                    context.pushReplacement('/recipe/$nid');
                  }
                } else if (v == 'del' && await confirmDialog(context, ref, t('confirm_delete'))) {
                  await repo.deleteRecipe(_id!);
                  bump(ref);
                  if (mounted) context.pop();
                }
              },
              itemBuilder: (c) => [
                PopupMenuItem(value: 'dup', child: Text(t('duplicate'))),
                PopupMenuItem(value: 'del', child: Text(t('delete'))),
              ],
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        TextField(controller: _name, decoration: deco(t('recipe_name')), onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _servings, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('servings')), onChanged: (_) => setState(() {}))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _margin, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('target_margin'), suffix: '%'), onChanged: (_) => setState(() {}))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _other, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('other_costs'), prefix: 'RM '), onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        TextField(controller: _own, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('own_price'), prefix: 'RM '), onChanged: (_) => setState(() {})),
        SectionTitle(t('ingredients')),
        if (all.isEmpty)
          AppCard(
            child: Column(children: [
              Text(t('add_ingredients_first'), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => context.push('/ingredient/new'), child: Text(t('new_ingredient'))),
            ]),
          ),
        for (var i = 0; i < _items.length; i++) ...[
          _itemCard(t, all, i, r.rows.length > i ? r.rows[i] : null),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(onPressed: all.isEmpty ? null : () => setState(() => _items.add(_Item())), icon: const Icon(Icons.add), label: Text(t('add_ingredient'))),
        const SizedBox(height: 12),
        StatusBanner(r.status),
        const SizedBox(height: 10),
        AppCard(
          child: Column(children: [
            ResultTile(t('cost_per_serving'), n(r.cellE6), big: true),
            ResultTile(t('suggested_price'), n(r.cellE7), big: true),
            const Divider(),
            ResultTile(t('ingredient_cost'), n(r.cellE12)),
            ResultTile(t('total_recipe_cost'), n(r.cellE13)),
            ResultTile(t('price_used'), n(r.cellE11)),
            ResultTile(t('profit_per_serving'), n(r.cellE8)),
            ResultTile(t('profit_margin'), n(r.cellE9, pct)),
            ResultTile(t('profit_per_batch'), n(r.cellE10)),
          ]),
        ),
        const SizedBox(height: 10),
        const ProfitDisclaimer(),
        const SizedBox(height: 8),
        HiddenCostWarning(otherCostsZero: r.hiddenCostWarning),
        const SizedBox(height: 14),
        FilledButton(onPressed: _save, child: Text(t('save'))),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _itemCard(T t, List<Ingredient> all, int i, RowResult? row) {
    final it = _items[i];
    return AppCard(
      child: Column(children: [
        Row(children: [
          Expanded(
            child: InputDecorator(
              decoration: deco(t('ingredient')),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  isDense: true,
                  value: all.any((a) => a.id == it.ingredient?.id) ? it.ingredient!.id : null,
                  items: [for (final a in all) DropdownMenuItem<int>(value: a.id!, child: Text(a.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() {
                    it.ingredient = all.firstWhere((a) => a.id == v);
                    it.unit = it.ingredient!.packUnit;
                  }),
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.close), tooltip: t('remove'), onPressed: () => setState(() => _items.removeAt(i).qty.dispose())),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 3, child: TextField(controller: it.qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('amount_used')), onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: UnitPicker(label: t('unit'), value: it.unit, family: it.ingredient?.family, onChanged: (v) => setState(() => it.unit = v))),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              row == null ? '' : (row.status == RowStatus.ok ? rm(row.cost) : t(rowStatusKey(row.status))),
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w800, color: row?.status.isProblem == true ? Brand.danger : Brand.black),
            ),
          ),
        ]),
      ]),
    );
  }
}

String _gate(String v) => v == 'Fix inputs' ? 'gate_fix' : (v == 'Enter servings' ? 'gate_servings' : 'gate_check');
