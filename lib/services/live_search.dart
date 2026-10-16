import 'package:cloud_functions/cloud_functions.dart';

/// The person's live searches for this week, as the server counts them.
class LiveSearchAllowance {
  const LiveSearchAllowance({
    required this.weeklyCap,
    required this.used,
    required this.remaining,
    required this.resetsAt,
    required this.paused,
  });

  final int weeklyCap;
  final int used;
  final int remaining;
  final DateTime resetsAt;

  /// Live search is switched off for everyone (kill switch or budget).
  final bool paused;

  /// Null for guests and unverified accounts, who cannot search at all.
  static LiveSearchAllowance? fromCallable(Map<String, dynamic> raw) {
    if (raw['eligible'] != true) return null;
    return LiveSearchAllowance(
      weeklyCap: (raw['weeklyCap'] as num).toInt(),
      used: (raw['used'] as num).toInt(),
      remaining: (raw['remaining'] as num).toInt(),
      resetsAt: DateTime.parse(raw['resetsAt'] as String),
      paused: raw['paused'] == true,
    );
  }
}

/// The reason a room callable attached to its error, such as `weekly-cap`.
String? callableReason(Object error) {
  if (error is! FirebaseFunctionsException) return null;
  final details = error.details;
  if (details is Map && details['reason'] is String) {
    return details['reason'] as String;
  }
  return null;
}

/// When the weekly allowance comes back, in the person's own time zone. Weeks
/// reset Monday 00:00 UTC, which is Sunday evening across the US.
String resetTimeText(DateTime resetsAt) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final local = resetsAt.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minutes =
      local.minute == 0 ? '' : ':${local.minute.toString().padLeft(2, '0')}';
  final half = local.hour < 12 ? 'AM' : 'PM';
  return '${days[local.weekday - 1]} at $hour$minutes $half';
}

/// Plain wording for the live-search limits, or null when [error] is not one.
String? liveSearchErrorMessage(Object error) {
  switch (callableReason(error)) {
    case 'weekly-cap':
      final details = (error as FirebaseFunctionsException).details as Map;
      final resetsAt = DateTime.tryParse('${details['resetsAt']}');
      return resetsAt == null
          ? "You've used this week's live searches. More arrive next week."
          : "You've used this week's live searches. More arrive ${resetTimeText(resetsAt)}.";
    case 'live-search-paused':
      return 'Live restaurant search is paused for now. Try again later.';
    case 'in-progress':
      return 'This search is already running. Give it a moment.';
  }
  return null;
}
