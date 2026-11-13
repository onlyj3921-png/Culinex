import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/theme.dart';
import 'data/database.dart';
import 'data/queries.dart';
import 'data/repository.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

/// Opens the database. If that fails (damaged file, newer database than this app, no space),
/// a recovery screen is shown instead of a blank crash.
Future<void> _start() async {
  try {
    final db = await AppDatabase.open();
    final queries = await Queries.load();
    final repo = Repo(db, queries);
    final saved = await repo.meta('lang');
    final device = ui.PlatformDispatcher.instance.locale.languageCode;
    final lang = saved ?? (device == 'ms' ? 'ms' : 'en');
    runApp(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        queriesProvider.overrideWithValue(queries),
        langProvider.overrideWith((ref) => lang),
      ],
      child: const CulinexApp(),
    ));
  } catch (e) {
    runApp(_StartupError(error: e, onRetry: _start));
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});
  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        appBar: AppBar(title: const Text('CULINEX')),
        body: Builder(
          builder: (context) => ListView(padding: const EdgeInsets.all(20), children: [
            const Icon(Icons.error_outline, size: 40, color: Brand.danger),
            const SizedBox(height: 12),
            const Text('The app could not open its data file. / Aplikasi tidak dapat membuka fail data.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Text('$error', style: const TextStyle(color: Brand.grey, fontSize: 12)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again / Cuba lagi')),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    content: const Text(
                        'The damaged data file will be moved aside (not deleted) and the app will start empty. You can restore a backup afterwards in Settings. Continue?\n\nFail data rosak akan diketepikan (tidak dipadam) dan aplikasi bermula kosong. Anda boleh memulihkan sandaran dalam Tetapan.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel / Batal')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue / Teruskan')),
                    ],
                  ),
                );
                if (ok == true) {
                  await AppDatabase.moveAside();
                  await onRetry();
                }
              },
              child: const Text('Move data aside and start fresh / Ketepikan data dan mula semula'),
            ),
          ]),
        ),
      ),
    );
  }
}
