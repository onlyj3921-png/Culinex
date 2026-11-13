import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/features.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import 'widgets.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final stockOk = ref.watch(canUseProvider(Feature.stockTracking));
    Widget item(IconData i, String label, String path, {bool lock = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push(path),
            child: AppCard(
              child: Row(children: [
                Icon(i, color: Brand.gold),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
                Icon(lock ? Icons.lock_outline : Icons.chevron_right, color: Brand.grey),
              ]),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(t('nav_more'))),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        item(Icons.eco_outlined, t('ingredients'), '/ingredients'),
        item(Icons.inventory_2_outlined, t('stock'), '/stock', lock: !stockOk),
        item(Icons.receipt_long, t('expenses'), '/expenses'),
        item(Icons.bar_chart, t('reports'), '/reports'),
        item(Icons.settings_outlined, t('settings'), '/settings'),
      ]),
    );
  }
}
