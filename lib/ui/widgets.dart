import 'package:culinex_engine/culinex_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../state/providers.dart';

InputDecoration deco(String label, {String? hint, String? prefix, String? suffix, String? error}) => InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      suffixText: suffix,
      errorText: error,
      filled: true,
      fillColor: Brand.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(
        color: color ?? Brand.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE6E2D8)),
        ),
        child: Padding(padding: padding, child: child),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: Brand.grey)),
      );
}

class ResultTile extends StatelessWidget {
  const ResultTile(this.label, this.value, {super.key, this.big = false});
  final String label;
  final String value;
  final bool big;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: big ? FontWeight.w700 : FontWeight.w500))),
          Text(value, style: TextStyle(fontSize: big ? 20 : 15, fontWeight: FontWeight.w800, color: big ? Brand.black : Brand.grey)),
        ]),
      );
}

String statusKey(InputStatus s) {
  switch (s) {
    case InputStatus.ok:
      return 'st_ok';
    case InputStatus.negative:
      return 'st_negative';
    case InputStatus.unitMismatch:
      return 'st_unit_mismatch';
    case InputStatus.checkUnit:
      return 'st_check_unit';
    case InputStatus.incomplete:
      return 'st_incomplete';
    case InputStatus.invalidRow:
      return 'st_invalid_row';
    case InputStatus.noServings:
      return 'st_no_servings';
    case InputStatus.badMargin:
      return 'st_bad_margin';
    case InputStatus.badOwnPrice:
      return 'st_bad_own';
  }
}

String rowStatusKey(RowStatus s) {
  switch (s) {
    case RowStatus.incomplete:
      return 'row_incomplete';
    case RowStatus.checkNumbers:
      return 'row_check_numbers';
    case RowStatus.checkUnit:
      return 'row_check_unit';
    case RowStatus.unitMismatch:
      return 'row_unit_mismatch';
    case RowStatus.blank:
    case RowStatus.ok:
      return 'row_ok';
  }
}

class StatusBanner extends ConsumerWidget {
  const StatusBanner(this.status, {super.key});
  final InputStatus status;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final ok = status == InputStatus.ok;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE5F2EC) : const Color(0xFFFDE7E4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(t(statusKey(status)), style: TextStyle(fontWeight: FontWeight.w700, color: ok ? Brand.ok : Brand.danger)),
    );
  }
}

/// Always visible next to profit figures.
class ProfitDisclaimer extends ConsumerWidget {
  const ProfitDisclaimer({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Brand.goldSoft, borderRadius: BorderRadius.circular(10)),
      child: Text(t('disclaimer_profit'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6B4E00))),
    );
  }
}

class HiddenCostWarning extends ConsumerWidget {
  const HiddenCostWarning({super.key, required this.otherCostsZero});
  final bool otherCostsZero;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: otherCostsZero ? const Color(0xFFFDE7E4) : Brand.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(t(otherCostsZero ? 'warn_other_zero' : 'remind_other'),
          style: TextStyle(fontSize: 12, color: otherCostsZero ? Brand.danger : Brand.grey, fontWeight: otherCostsZero ? FontWeight.w700 : FontWeight.w400)),
    );
  }
}

class PremiumLock extends ConsumerWidget {
  const PremiumLock({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final body = Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.lock_outline, size: 36, color: Brand.gold),
      const SizedBox(height: 8),
      Text(t('premium_feature'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 6),
      Text(t('premium_unavailable'), textAlign: TextAlign.center, style: const TextStyle(color: Brand.grey)),
    ]);
    return compact ? AppCard(child: Center(child: body)) : Center(child: Padding(padding: const EdgeInsets.all(24), child: body));
  }
}

class UnitPicker extends StatelessWidget {
  const UnitPicker({super.key, required this.label, required this.value, required this.onChanged, this.family});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final UnitFamily? family;
  @override
  Widget build(BuildContext context) {
    final units = kUnits.where((u) => family == null || u.family == family).toList();
    final v = units.any((u) => u.code == value) ? value : null;
    return InputDecorator(
      decoration: deco(label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: v,
          isExpanded: true,
          isDense: true,
          items: [for (final u in units) DropdownMenuItem(value: u.code, child: Text(u.code))],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

void showMsg(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirmDialog(BuildContext context, WidgetRef ref, String message) async {
  final t = ref.read(tProvider);
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t('confirm'))),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> pickDate(BuildContext context, String initialIso) async {
  final init = DateTime.tryParse(initialIso) ?? DateTime.now();
  final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2020), lastDate: DateTime(2100));
  if (d == null) return null;
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
