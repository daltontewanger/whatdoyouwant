import 'dart:async';

/// How far along a room is; a room only ever moves forward.
int roomStage(String? status) => switch (status) {
  'voting' => 1,
  'closed' => 2,
  _ => 0,
};

/// While someone is waiting on the room to move on (a guest in the lobby, or
/// anyone who has voted on every card), asks the server every few seconds
/// how the room stands. The question goes over its own request, so when a
/// phone's browser or network stalls the live connection, the answer still
/// gets through.
///
/// When the server is ahead of what the listener has shown, [onAhead] gets
/// the server's view straight away, so the screen moves on without waiting.
/// [reconnect] is also asked to restart the live connection so later changes
/// flow again, but at most once per [reconnectGap]: restarting every few
/// seconds would cut off a slow reconnect before it could finish.
class RoomBackstop {
  RoomBackstop({
    required this.ask,
    required this.shown,
    required this.onAhead,
    required this.reconnect,
    this.every = const Duration(seconds: 5),
    this.reconnectGap = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The room as the server sees it: at least a `status`.
  final Future<Map<String, dynamic>> Function() ask;

  /// The status the live listener has shown so far, or null before its
  /// first snapshot.
  final String? Function() shown;
  final void Function(Map<String, dynamic> view) onAhead;
  final Future<void> Function() reconnect;
  final Duration every;
  final Duration reconnectGap;
  final DateTime Function() _clock;

  Timer? _timer;
  bool _checking = false;
  DateTime? _reconnectedAt;

  bool get running => _timer != null;

  void start() => _timer ??= Timer.periodic(every, (_) => _check());

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final view = await ask();
      final mine = shown();
      // The listener may have caught up while the question was out. Before
      // it has shown anything at all, any answer is news.
      if (!running ||
          (mine != null &&
              roomStage(view['status'] as String?) <= roomStage(mine))) {
        return;
      }
      onAhead(view);
      final now = _clock();
      final last = _reconnectedAt;
      if (last == null || now.difference(last) >= reconnectGap) {
        _reconnectedAt = now;
        await reconnect();
      }
    } catch (_) {
      // A failed check is retried on the next tick; the listener still runs.
    } finally {
      _checking = false;
    }
  }
}
