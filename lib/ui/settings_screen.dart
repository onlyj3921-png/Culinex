import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/features.dart';
import '../core/theme.dart';
import '../data/database.dart';
import '../state/providers.dart';
import 'widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(langProvider);
    final plan = ref.watch(planProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('settings'))),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        SectionTitle(t('language')),
        AppCard(
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'ms', label: Text('Bahasa Melayu'))],
            selected: {lang},
            onSelectionChanged: (s) async {
              ref.read(langProvider.notifier).state = s.first;
              await ref.read(repoProvider).setMeta('lang', s.first);
            },
          ),
        ),
        SectionTitle(t('plan')),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plan == Plan.premium ? t('plan_premium_debug') : t('plan_free'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(t('premium_unavailable'), style: const TextStyle(color: Brand.grey)),
            if (kDebugMode)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('debug_premium')),
                value: ref.watch(debugPremiumProvider),
                onChanged: (v) => ref.read(debugPremiumProvider.notifier).state = v,
              ),
          ]),
        ),
        SectionTitle(t('backup')),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('backup_hint'), style: const TextStyle(color: Brand.grey)),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(t('backup_export')),
              onPressed: () async {
                try {
                  await AppDatabase.exportBackup(ref.read(databaseProvider));
                } catch (e) {
                  if (context.mounted) showMsg(context, '${t('error')}: $e');
                }
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.restore),
              label: Text(t('backup_restore')),
              onPressed: () async {
                if (!await confirmDialog(context, ref, t('restore_confirm'))) return;
                final pick = await FilePicker.platform.pickFiles();
                final path = pick?.files.single.path;
                if (path == null) return;
                try {
                  await AppDatabase.restoreBackup(ref.read(databaseProvider), path);
                  if (context.mounted) {
                    await showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (c) => AlertDialog(content: Text(t('restore_done')), actions: [TextButton(onPressed: () => SystemNavigator.pop(), child: Text(t('ok')))]),
                    );
                  }
                } catch (e) {
                  if (context.mounted) showMsg(context, '$e');
                }
              },
            ),
          ]),
        ),
        SectionTitle(t('privacy')),
        AppCard(child: Text(t('privacy_text'), style: const TextStyle(color: Brand.grey))),
        SectionTitle(t('about')),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CULINEX 0.1.0', style: TextStyle(fontWeight: FontWeight.w800)),
            const Text(Brand.tagline, style: TextStyle(color: Brand.grey, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            Text(t('disclaimer_full'), style: const TextStyle(fontSize: 12, color: Brand.grey)),
          ]),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }
}
