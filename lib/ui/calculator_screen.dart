import 'package:culinex_engine/culinex_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/money.dart';
import '../core/simple_cost.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import 'widgets.dart';

/// Works fully offline. Nothing is saved unless the user taps "Save as recipe".
class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});
  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _Line {
  final name = TextEditingController();
  final price = TextEditingController();
  final size = TextEditingController();
  final used = TextEditingController();
  String? packUnit;
  String? usedUnit;
  void dispose() {
    name.dispose();
    price.dispose();
    size.dispose();
    used.dispose();
  }

  IngredientLine toEngine() => IngredientLine(
        name: name.text,
        price: parseNum(price.text),
        size: parseNum(size.text),
        packUnit: packUnit,
        used: parseNum(used.text),
        usedUnit: usedUnit,
      );
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  // shared settings
  final _servings = TextEditingController();
  final _margin = TextEditingController(); // percent, e.g. 65
  final _other = TextEditingController();
  final _own = TextEditingController();
  // simple tab
  final _simpleIng = TextEditingController();
  // advanced tab
  final List<_Line> _lines = [_Line()];

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_servings, _margin, _other, _own, _simpleIng]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  CalcInput _input(bool simple) {
    final m = parseNum(_margin.text);
    final lines = simple
        ? [
            IngredientLine(
              name: 'ingredients',
              price: parseNum(_simpleIng.text),
              size: 1,
              packUnit: 'pcs',
              used: 1,
              usedUnit: 'pcs',
            )
          ]
        : _lines.map((l) => l.toEngine()).toList();
    return CalcInput(
      lines: lines,
      servings: parseNum(_servings.text),
      margin: m == null ? null : m / 100,
      otherCosts: parseNum(_other.text),
      ownPrice: parseNum(_own.text),
    );
  }

  void _loadExample() {
    const rows = [
      ('Ground chicken', '8', '1000', 'g', '1500', 'g'),
      ('Burger buns', '4', '12', 'pcs', '10', 'pcs'),
      ('Cheese slices', '5', '20', 'pcs', '10', 'pcs'),
      ('Lettuce', '2', '500', 'g', '250', 'g'),
      ('Tomatoes', '3', '1000', 'g', '400', 'g'),
      ('Burger sauce', '6', '1000', 'ml', '200', 'ml'),
    ];
    setState(() {
      for (final l in _lines) {
        l.dispose();
      }
      _lines
        ..clear()
        ..addAll(rows.map((r) {
          final l = _Line();
          l.name.text = r.$1;
          l.price.text = r.$2;
          l.size.text = r.$3;
          l.packUnit = r.$4;
          l.used.text = r.$5;
          l.usedUnit = r.$6;
          return l;
        }));
      _servings.text = '10';
      _margin.text = '65';
      _other.text = '3';
      _own.clear();
    });
  }

  void _clearAll() => setState(() {
        for (final l in _lines) {
          l.dispose();
        }
        _lines
          ..clear()
          ..add(_Line());
        for (final c in [_servings, _margin, _other, _own, _simpleIng]) {
          c.clear();
        }
      });

  Future<void> _saveRecipe(CalcResult r) async {
    final t = ref.read(tProvider);
    final nameC = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('save_as_recipe')),
        content: TextField(controller: nameC, autofocus: true, decoration: deco(t('recipe_name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, nameC.text), child: Text(t('save'))),
        ],
      ),
    );
    // controller intentionally not disposed here: the dialog's exit animation may still use it
    if (name == null || name.trim().isEmpty || !mounted) return;
    final input = _input(false);
    try {
      final res = await ref.read(repoProvider).saveCalculatorAsRecipe(
            name: name,
            lines: input.lines,
            servings: input.servings!,
            margin: input.margin!,
            otherCosts: input.otherCosts ?? 0,
            ownPrice: input.ownPrice,
          );
      bump(ref);
      if (!mounted) return;
      showMsg(context, res.keptExisting > 0 ? t('saved_kept').replaceAll('{n}', '${res.keptExisting}') : t('saved'));
    } catch (e) {
      if (mounted) showMsg(context, '${t('error')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('nav_calc')),
        actions: [IconButton(tooltip: t('clear'), onPressed: _clearAll, icon: const Icon(Icons.refresh))],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Brand.gold,
          labelColor: Brand.gold,
          unselectedLabelColor: Colors.white70,
          tabs: [Tab(text: t('calc_simple')), Tab(text: t('calc_advanced'))],
          onTap: (_) => setState(() {}),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(t('offline_note'), style: const TextStyle(fontSize: 12, color: Brand.grey)),
          const SizedBox(height: 10),
          if (_tabs.index == 0) _simpleBody(t) else _advancedBody(t),
          const SizedBox(height: 12),
          _settingsCard(t),
          const SizedBox(height: 12),
          _resultsCard(t),
        ],
      ),
    );
  }

  Widget _simpleBody(T t) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('simple_hint'), style: const TextStyle(color: Brand.grey)),
          const SizedBox(height: 10),
          TextField(
            controller: _simpleIng,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: deco(t('total_ingredient_cost'), prefix: 'RM '),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      );

  Widget _advancedBody(T t) {
    final input = _input(false);
    final result = calculate(input);
    return Column(children: [
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: _loadExample, icon: const Icon(Icons.science_outlined), label: Text(t('load_example')))),
      ]),
      const SizedBox(height: 10),
      for (var i = 0; i < _lines.length; i++) ...[
        _lineCard(t, i, result.rows.length > i ? result.rows[i] : null),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        onPressed: () => setState(() => _lines.add(_Line())),
        icon: const Icon(Icons.add),
        label: Text(t('add_ingredient')),
      ),
    ]);
  }

  Widget _lineCard(T t, int i, RowResult? row) {
    final l = _lines[i];
    final fam = findUnit(l.packUnit)?.family;
    return AppCard(
      child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: l.name, decoration: deco(t('ingredient')), onChanged: (_) => setState(() {}))),
          if (_lines.length > 1)
            IconButton(
              tooltip: t('remove'),
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _lines.removeAt(i).dispose();
              }),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
                controller: l.price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: deco(t('pkg_price'), prefix: 'RM '),
                onChanged: (_) => setState(() {})),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
                controller: l.size,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: deco(t('pkg_size')),
                onChanged: (_) => setState(() {})),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: UnitPicker(
                label: t('unit'),
                value: l.packUnit,
                onChanged: (v) => setState(() {
                      l.packUnit = v;
                      // keep the used unit in the same unit family, otherwise the hidden value would
                      // silently cause "Unit mismatch" while the picker shows blank
                      if (l.usedUnit == null || findUnit(l.usedUnit)?.family != findUnit(v)?.family) l.usedUnit = v;
                    })),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
                controller: l.used,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: deco(t('amount_used')),
                onChanged: (_) => setState(() {})),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: UnitPicker(label: t('used_unit'), value: l.usedUnit, family: fam, onChanged: (v) => setState(() => l.usedUnit = v))),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              row == null || row.status == RowStatus.blank
                  ? ''
                  : row.status == RowStatus.ok
                      ? rm(row.cost)
                      : t(rowStatusKey(row.status)),
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w800, color: row?.status.isProblem == true ? Brand.danger : Brand.black),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _settingsCard(T t) => AppCard(
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                  controller: _servings,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: deco(t('servings')),
                  onChanged: (_) => setState(() {})),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                  controller: _margin,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: deco(t('target_margin'), suffix: '%'),
                  onChanged: (_) => setState(() {})),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
              controller: _other,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: deco(t('other_costs'), prefix: 'RM '),
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          TextField(
              controller: _own,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: deco(t('own_price'), prefix: 'RM '),
              onChanged: (_) => setState(() {})),
        ]),
      );

  Widget _simpleCostBanner(T t, SimpleCostState state) {
    final invalid = state == SimpleCostState.invalid;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: invalid ? const Color(0xFFFDE7E4) : const Color(0xFFEDEBE5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        invalid ? t('simple_cost_invalid') : t('simple_enter_cost'),
        style: TextStyle(fontWeight: FontWeight.w700, color: invalid ? Brand.danger : Brand.black),
      ),
    );
  }

  Widget _resultsCard(T t) {
    final simple = _tabs.index == 0;
    // Simple mode feeds the engine one hidden row built from the cost field. While that field is empty or not a
    // number, show a prompt and "—" instead of the engine's "incomplete row" state (no visible row exists to fix).
    final costState = simple ? classifySimpleCost(_simpleIng.text) : SimpleCostState.valid;
    final costBlocked = costState != SimpleCostState.valid;
    final r = calculate(_input(simple));
    String show(Object? v, [String Function(double)? f]) =>
        costBlocked ? '—' : (v is double ? (f ?? rm)(v) : (v is String ? t(_gateKey(v)) : '—'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      costBlocked ? _simpleCostBanner(t, costState) : StatusBanner(r.status),
      const SizedBox(height: 10),
      AppCard(
        child: Column(children: [
          ResultTile(t('cost_per_serving'), show(r.cellE6), big: true),
          ResultTile(t('suggested_price'), show(r.cellE7), big: true),
          const Divider(),
          ResultTile(t('ingredient_cost'), show(r.cellE12)),
          ResultTile(t('total_recipe_cost'), show(r.cellE13)),
          ResultTile(t('price_used'), show(r.cellE11)),
          ResultTile(t('profit_per_serving'), show(r.cellE8)),
          ResultTile(t('profit_margin'), show(r.cellE9, pct)),
          ResultTile(t('profit_per_batch'), show(r.cellE10)),
        ]),
      ),
      const SizedBox(height: 10),
      const ProfitDisclaimer(),
      const SizedBox(height: 8),
      HiddenCostWarning(otherCostsZero: r.hiddenCostWarning),
      if (!simple) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: r.status == InputStatus.ok ? () => _saveRecipe(r) : null,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(t('save_as_recipe')),
        ),
      ],
    ]);
  }
}

String _gateKey(String v) {
  switch (v) {
    case 'Fix inputs':
      return 'gate_fix';
    case 'Enter servings':
      return 'gate_servings';
    default:
      return 'gate_check';
  }
}
