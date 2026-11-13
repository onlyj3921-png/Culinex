import 'dart:io';

import 'package:culinex/core/money.dart';
import 'package:culinex/data/database.dart';
import 'package:culinex/state/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money helpers', () {
    test('rm formats ringgit', () {
      expect(rm(1234.5), 'RM 1,234.50');
      expect(rm(-5), '-RM 5.00');
      expect(rm(0), 'RM 0.00');
      expect(rm(null), '—');
      expect(rmSen(692), 'RM 6.92');
    });
    test('pct', () {
      expect(pct(0.65), '65.0%');
      expect(pct(null), '—');
    });
    test('parseNum', () {
      expect(parseNum('1,234.50'), 1234.5);
      expect(parseNum(' 8 '), 8);
      expect(parseNum(''), isNull);
      expect(parseNum('RM8'), isNull);
      expect(parseNum('abc'), isNull);
      expect(parseNum('Infinity'), isNull);
    });
    test('fmtQty and fmtBase', () {
      expect(fmtQty(2.5), '2.5');
      expect(fmtQty(10), '10');
      expect(fmtQty(0.5), '0.5');
      expect(fmtBase(1500, 'g'), '1.5 kg');
      expect(fmtBase(250, 'kg'), '250 g');
      expect(fmtBase(2000, 'ml'), '2 L');
      expect(fmtBase(12, 'pcs'), '12 pcs');
    });
    test('isoDate pads', () => expect(isoDate(DateTime(2026, 3, 5)), '2026-03-05'));
  });

  group('period ranges (Thursday 12 Nov 2026)', () {
    final now = DateTime(2026, 11, 12);
    test('day', () => expect(currentRange(PeriodKind.day, now), (from: '2026-11-12', to: '2026-11-12')));
    test('week is Monday to Sunday', () => expect(currentRange(PeriodKind.week, now), (from: '2026-11-09', to: '2026-11-15')));
    test('month', () => expect(currentRange(PeriodKind.month, now), (from: '2026-11-01', to: '2026-11-30')));
    test('trend day = last 14 days', () {
      final r = trendRange(PeriodKind.day, now);
      expect((r.from, r.to, r.fmt), ('2026-10-30', '2026-11-12', '%Y-%m-%d'));
    });
    test('trend week = 8 weeks', () {
      final r = trendRange(PeriodKind.week, now);
      expect((r.from, r.to, r.fmt), ('2026-09-21', '2026-11-15', '%Y-W%W'));
    });
    test('trend month = 6 months', () {
      final r = trendRange(PeriodKind.month, now);
      expect((r.from, r.to, r.fmt), ('2026-06-01', '2026-11-30', '%Y-%m'));
    });
    test('month range handles December/January', () {
      expect(currentRange(PeriodKind.month, DateTime(2026, 12, 31)), (from: '2026-12-01', to: '2026-12-31'));
      expect(trendRange(PeriodKind.month, DateTime(2027, 2, 10)).from, '2026-09-01');
    });
  });

  group('database schema file', () {
    test('splits into 24 non-empty statements (same split as the Python SQL tests)', () {
      final sql = File('assets/db/schema.sql').readAsStringSync();
      final parts = AppDatabase.splitStatements(sql);
      expect(parts.length, 24);
      expect(parts.every((s) => s.isNotEmpty), isTrue);
      expect(parts.first.contains('CREATE TABLE app_meta'), isTrue);
    });
  });
}
