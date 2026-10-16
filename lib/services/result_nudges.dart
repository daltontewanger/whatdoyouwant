import 'dart:async';

/// When to ask the server to finish a room it closes itself.
///
/// Every nudge is a transaction that tallies each member's ballots, so rather
/// than polling this asks at the moments the room could actually be ready: on
/// [start], just after voting ends, and otherwise only on a slow [fallback] in
/// case the last vote landed while nobody was asking. The room listener shows
/// the result as soon as any member's nudge closes it.
class ResultNudges {
  ResultNudges(
    this._nudge, {
    this.fallback = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<void> Function() _nudge;
  final Duration fallback;
  final DateTime Function() _clock;

  // The server closes a room only once votingEndsAt has passed by its clock,
  // so wait a little longer to allow for this device running ahead.
  static const Duration _grace = Duration(seconds: 1);

  Timer? _fallbackTimer;
  Timer? _endTimer;
  DateTime? _scheduledEnd;
  bool _stopped = false;

  /// Nudges now and then keeps the slow fallback running until [stop].
  void start() {
    if (_stopped) return;
    _send();
    _fallbackTimer ??= Timer.periodic(fallback, (_) => _send());
  }

  /// Nudges once just after [endsAt]. Safe to call on every room update.
  void votingEndsAt(DateTime? endsAt) {
    if (_stopped || endsAt == null || endsAt == _scheduledEnd) return;
    _scheduledEnd = endsAt;
    _endTimer?.cancel();
    final wait = endsAt.difference(_clock()) + _grace;
    _endTimer = Timer(wait.isNegative ? Duration.zero : wait, _send);
  }

  void stop() {
    _stopped = true;
    _fallbackTimer?.cancel();
    _endTimer?.cancel();
  }

  // A failed nudge only delays the result; the next one retries.
  void _send() {
    if (!_stopped) _nudge().catchError((_) {});
  }
}
