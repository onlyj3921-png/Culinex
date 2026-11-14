import 'money.dart';

/// State of the Simple calculator's "Total ingredient cost" field.
///
/// Simple mode feeds the engine one hidden row built from this field. While the field is empty or not a number
/// the screen shows a prompt instead of calculating (there is no visible ingredient row the user could fix).
enum SimpleCostState { empty, invalid, valid }

SimpleCostState classifySimpleCost(String text) {
  if (text.trim().isEmpty) return SimpleCostState.empty;
  return parseNum(text) == null ? SimpleCostState.invalid : SimpleCostState.valid;
}
