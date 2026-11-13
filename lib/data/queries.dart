import 'package:flutter/services.dart' show rootBundle;

/// Loads the named SQL queries from assets/db/queries.sql (the same file tools/test_sql.py tests).
class Queries {
  Queries._(this._q);
  final Map<String, String> _q;

  static Future<Queries> load() async {
    final text = await rootBundle.loadString('assets/db/queries.sql');
    final map = <String, String>{};
    for (final block in text.split(RegExp(r'^-- name: ', multiLine: true)).skip(1)) {
      final nl = block.indexOf('\n');
      map[block.substring(0, nl).trim()] = block.substring(nl + 1).trim();
    }
    return Queries._(map);
  }

  String operator [](String name) {
    final s = _q[name];
    if (s == null) throw StateError('Unknown query: $name');
    return s;
  }
}
