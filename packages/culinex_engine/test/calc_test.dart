import 'dart:convert';
import 'dart:io';

import 'package:culinex_engine/culinex_engine.dart';
import 'package:test/test.dart';

double? _d(dynamic v) => v == null ? null : (v as num).toDouble();

CalcInput _input(Map<String, dynamic> j) {
  final rows = (j['rows'] as List).cast<Map<String, dynamic>>();
  // rows are listed by sheet row number; blank rows are omitted (they are no-ops).
  return CalcInput(
    lines: [
      for (final r in rows)
        IngredientLine(
          name: r['name'] as String?,
          price: _d(r['price']),
          size: _d(r['size']),
          packUnit: r['packUnit'] as String?,
          used: _d(r['used']),
          usedUnit: r['usedUnit'] as String?,
        ),
    ],
    servings: _d(j['servings']),
    margin: _d(j['margin']),
    otherCosts: _d(j['other']),
    ownPrice: _d(j['own']),
  );
}

void _expectCell(String label, Object? actual, dynamic expected) {
  if (expected == null) {
    expect(actual, isNull, reason: '$label should be blank');
  } else if (expected is String) {
    expect(actual, expected, reason: label);
  } else {
    expect(actual, isA<double>(), reason: '$label should be a number');
    final e = (expected as num).toDouble();
    expect(((actual as double) - e).abs() <= 1e-9 * (e.abs() < 1 ? 1 : e.abs()), isTrue,
        reason: '$label: got $actual expected $e');
  }
}

void main() {
  final golden = jsonDecode(File('test/golden/calc_vectors.json').readAsStringSync())
      as Map<String, dynamic>;
  final vectors = (golden['vectors'] as List).cast<Map<String, dynamic>>();

  group('golden vectors (values read from the V1.2 workbook)', () {
    for (final v in vectors) {
      test(v['id'] as String, () {
        final input = _input(v['input'] as Map<String, dynamic>);
        final r = calculate(input);
        final e = v['expected'] as Map<String, dynamic>;
        _expectCell('E12', r.cellE12, e['E12']);
        _expectCell('E13', r.cellE13, e['E13']);
        _expectCell('E6', r.cellE6, e['E6']);
        _expectCell('E7', r.cellE7, e['E7']);
        _expectCell('E11', r.cellE11, e['E11']);
        _expectCell('E8', r.cellE8, e['E8']);
        _expectCell('E9', r.cellE9, e['E9']);
        _expectCell('E10', r.cellE10, e['E10']);
        expect(r.status.name, e['statusCode']);
        final rowText = (e['rowText'] as List).cast<String>();
        final rowCost = (e['rowCost'] as List);
        for (var k = 0; k < r.rows.length; k++) {
          expect(r.rows[k].status.sheetText, rowText[k], reason: 'row $k status');
          if (rowCost[k] != null) {
            expect(r.rows[k].cost, isNotNull);
            final rc = (rowCost[k] as num).toDouble();
            expect((r.rows[k].cost! - rc).abs() <= 1e-9 * (rc.abs() < 1 ? 1 : rc.abs()), isTrue,
                reason: 'row $k cost');
          }
        }
      });
    }
  });

  group('unit and money helpers', () {
    test('unit lookup is case-insensitive and not trimmed', () {
      expect(findUnit('KG')?.factor, 1000);
      expect(findUnit('l')?.family, UnitFamily.volume);
      expect(findUnit(' g'), isNull);
      expect(findUnit('oz'), isNull);
    });
    test('toSen rounds half away from zero', () {
      expect(toSen(8.5), 850);
      expect(toSen(0.285), 29);
      expect(toSen(-0.285), -29);
      expect(toSen(2.4233333), 242);
    });
    test('hidden cost warning when other costs are zero or empty', () {
      expect(calculate(const CalcInput(servings: 1, margin: 0.5)).hiddenCostWarning, isTrue);
      expect(calculate(const CalcInput(servings: 1, margin: 0.5, otherCosts: 1)).hiddenCostWarning, isFalse);
    });
  });
}
