import 'package:culinex_engine/culinex_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final list = ref.watch(expensesProvider);
    final day = ref.watch(totalsProvider(PeriodKind.day)).valueOrNull;
    final week = ref.watch(totalsProvider(PeriodKind.week)).valueOrNull;
    final month = ref.watch(totalsProvider(PeriodKind.month)).valueOrNull;
    final cats = ref.watch(categoryTotalsProvider(PeriodKind.month)).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(t('expenses'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: Text(t('add_expense')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 90), children: [
        AppCard(
          child: Column(children: [
            ResultTile(t('today'), rm((day?.expensesSen ?? 0) / 100)),
            ResultTile(t('this_week'), rm((week?.expensesSen ?? 0) / 100)),
            ResultTile(t('this_month'), rm((month?.expensesSen ?? 0) / 100), big: true),
          ]),
        ),
        if (cats.isNotEmpty) ...[
          SectionTitle(t('by_category')),
          AppCard(child: Column(children: [for (final c in cats) ResultTile(t('cat_${c.category}'), rmSen(c.totalSen))])),
        ],
        SectionTitle(t('history')),
        list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('${t('error')}: $e'),
          data: (rows) => rows.isEmpty
              ? Text(t('no_expenses'), style: const TextStyle(color: Brand.grey))
              : Column(children: [
                  for (final e in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t('cat_${e.category}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${e.spentOn}${e.note == null || e.note!.isEmpty ? '' : ' · ${e.note}'}', style: const TextStyle(color: Brand.grey, fontSize: 12)),
                            ]),
                          ),
                          Text(rmSen(e.amountSen), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirmDialog(context, ref, t('confirm_delete'))) {
                                await ref.read(repoProvider).deleteExpense(e.id);
                                bump(ref);
                              }
                            },
                          ),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: const _ExpenseForm()),
      );
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm();
  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  String _cat = 'ingredients';
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _date = todayIso();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final a = parseNum(_amount.text);
    if (a == null || toSen(a) <= 0) return showMsg(context, t('err_amount'));
    try {
      await ref.read(repoProvider).addExpense(category: _cat, amountSen: toSen(a), spentOn: _date, note: _note.text.trim().isEmpty ? null : _note.text.trim());
      bump(ref);
      if (!mounted) return;
      showMsg(context, t('saved'));
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
        Text(t('add_expense'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: deco(t('category')),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              value: _cat,
              items: [for (final c in kExpenseCategories) DropdownMenuItem(value: c, child: Text(t('cat_$c')))],
              onChanged: (v) => setState(() => _cat = v ?? _cat),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco(t('amount'), prefix: 'RM ')),
        const SizedBox(height: 10),
        TextField(controller: _note, decoration: deco(t('note'))),
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
