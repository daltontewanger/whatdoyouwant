import 'dart:async';

/// While a guest waits in a room's lobby, asks the server every few seconds
/// whether the room has started. The question goes over its own request, so
/// when a phone's network or browser stalls the live connection, the server's
/// answer still gets through and [onBehind] can restart that connection.
/// Whoever owns this calls [stop] once the live listener shows the start.
class LobbyBackstop {
  LobbyBackstop({
    required this.status,
    required this.onBehind,
    this.every = const Duration(seconds: 5),
  });

  /// The room's status according to the server.
  final Future<String> Function() status;

  /// Called when the server says the room has left the lobby but [stop] has
  /// not been called yet, meaning the live listener is behind.
  final Future<void> Function() onBehind;
  final Duration every;

  Timer? _timer;
  bool _checking = false;

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
      final current = await status();
      // The live listener may have caught up while the question was out.
      if (running && current != 'lobby') await onBehind();
    } catch (_) {
      // A failed check is retried on the next tick; the listener still runs.
    } finally {
      _checking = false;
    }
  }
}
