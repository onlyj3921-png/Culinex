import 'package:culinex/core/simple_cost.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifySimpleCost (Simple calculator cost field)', () {
    test('empty or blank text is empty', () {
      for (final s in ['', ' ', '   ']) {
        expect(classifySimpleCost(s), SimpleCostState.empty, reason: "'$s'");
      }
    });

    test('text that is not a number is invalid', () {
      for (final s in ['abc', 'RM5', '5RM', '1.2.3', '-', 'Infinity', 'NaN']) {
        expect(classifySimpleCost(s), SimpleCostState.invalid, reason: "'$s'");
      }
    });

    test('numbers are valid, including 0, thousands separators and surrounding spaces', () {
      for (final s in ['5', '24.50', '1,234.50', ' 8 ', '0', '0.5']) {
        expect(classifySimpleCost(s), SimpleCostState.valid, reason: "'$s'");
      }
    });

    test('a negative number is still passed to the engine (which reports the negative value)', () {
      expect(classifySimpleCost('-5'), SimpleCostState.valid);
    });
  });
}
