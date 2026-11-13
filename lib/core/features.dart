import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum Plan { free, premium }

enum Feature { stockTracking, lowStockAlerts, advancedReports }

/// Which features need Premium. Owner can move items between plans here.
bool featureNeedsPremium(Feature f) => true;

/// Debug-only switch so developers can test Premium screens. Never active in release builds.
final debugPremiumProvider = StateProvider<bool>((ref) => false);

/// IMPORTANT: there is NO billing in this build. In a release build the plan is always Free.
/// When subscriptions are implemented this provider must read a verified entitlement
/// (store purchase + server check) and nothing else.
final planProvider = Provider<Plan>((ref) {
  if (kDebugMode && ref.watch(debugPremiumProvider)) return Plan.premium;
  return Plan.free;
});

final canUseProvider = Provider.family<bool, Feature>((ref, f) {
  final plan = ref.watch(planProvider);
  return !featureNeedsPremium(f) || plan == Plan.premium;
});
