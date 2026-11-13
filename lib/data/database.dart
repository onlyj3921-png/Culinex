import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

/// Separator line used in assets/db/schema.sql between statements.
const String kStatementSeparator = '-- @@';
const int kSchemaVersion = 1;

class AppDatabase {
  static const fileName = 'culinex.db';

  static Future<String> path() async => p.join(await getDatabasesPath(), fileName);

  static List<String> splitStatements(String sql) => sql
      .split(kStatementSeparator)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static Future<Database> open() async {
    final schema = await rootBundle.loadString('assets/db/schema.sql');
    return openDatabase(
      await path(),
      version: kSchemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        for (final s in splitStatements(schema)) {
          await db.execute(s);
        }
      },
    );
  }

  static Future<void> _deleteSidecars(String live) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$live$suffix');
      if (await f.exists()) await f.delete();
    }
  }

  /// BACKUP: writes a consistent single-file snapshot (VACUUM INTO, falls back to a file copy on old
  /// SQLite versions) and opens the share sheet. Needs no internet. Returns the backup file path.
  static Future<String> exportBackup(Database db) async {
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final out = p.join(tmp.path, 'culinex_backup_$stamp.db');
    final f = File(out);
    if (await f.exists()) await f.delete();
    var ok = false;
    try {
      await db.execute("VACUUM INTO '${out.replaceAll("'", "''")}'");
      ok = await f.exists() && await f.length() > 0;
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      if (await f.exists()) await f.delete();
      try {
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {/* not in WAL mode; fine */}
      await File(await path()).copy(out);
    }
    await Share.shareXFiles([XFile(out)], text: 'CULINEX backup $stamp');
    return out;
  }

  /// RECOVERY: validates a chosen backup, keeps a safety copy of current data, then replaces it.
  /// The app must be restarted afterwards. Throws a readable message on any problem.
  static Future<void> restoreBackup(Database current, String backupPath) async {
    final probe = await openDatabase(backupPath, readOnly: true);
    try {
      final integrity = await probe.rawQuery('PRAGMA integrity_check');
      if (integrity.first.values.first != 'ok') throw 'Backup file is damaged.';
      final tables = await probe.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
          "('app_meta','ingredients','recipes','recipe_items','sales','expenses','stock_movements')");
      if (tables.length < 7) throw 'This is not a CULINEX backup.';
      final ver = await probe.rawQuery("SELECT value FROM app_meta WHERE key='schema_version'");
      if (ver.isEmpty) throw 'This is not a CULINEX backup.';
      if (int.parse(ver.first['value'] as String) > kSchemaVersion) {
        throw 'Backup is from a newer CULINEX version. Update the app first.';
      }
    } finally {
      await probe.close();
    }
    final live = await path();
    await current.close();
    await _deleteSidecars(live); // stale -wal/-journal files must never be applied to the restored file
    final safety = '$live.before_restore';
    await File(live).copy(safety);
    try {
      await File(backupPath).copy(live);
    } catch (e) {
      await File(safety).copy(live); // put the previous data back
      rethrow;
    }
  }

  /// Startup recovery: moves an unreadable database aside (kept on disk, never deleted) so the app can start fresh.
  static Future<String> moveAside() async {
    final live = await path();
    await _deleteSidecars(live);
    final dest = '$live.corrupt-${DateTime.now().millisecondsSinceEpoch}';
    final f = File(live);
    if (await f.exists()) await f.rename(dest);
    return dest;
  }
}
