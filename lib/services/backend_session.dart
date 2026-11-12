import 'dart:async';

/// Connects the app to the backend the first time something needs it, rather
/// than when the app opens: App Check first, then a guest account when nobody
/// is signed in. A visit that never hosts, joins, picks or signs in then costs
/// nothing beyond loading the page: no App Check check, no account, no calls.
class BackendSession {
  BackendSession({
    required Future<void> Function() protect,
    required Future<void> Function() signIn,
    required bool Function() signedIn,
  }) : _protect = protect,
       _signIn = signIn,
       _signedIn = signedIn;

  final Future<void> Function() _protect;
  final Future<void> Function() _signIn;
  final bool Function() _signedIn;
  final _started = Completer<void>();
  Future<void>? _protecting;
  Future<void>? _signingIn;

  /// Whether the backend has been reached for a real reason yet.
  bool get isStarted => _started.isCompleted;

  /// Completes once the session first starts; work that should happen only
  /// for people who use the app (the update check, queued counts) waits here.
  Future<void> get whenStarted => _started.future;

  /// App Check only: enough to sign in or create an account. A failure is
  /// retried on the next call.
  Future<void> protect() =>
      _protecting ??= _protect().catchError((Object error) {
        _protecting = null;
        throw error;
      });

  /// App Check and a signed-in session, starting a guest one if needed.
  /// Checked on every call, so signing out and back in works.
  Future<void> ready() async {
    await protect();
    if (!_signedIn()) {
      await (_signingIn ??= _signIn().whenComplete(() => _signingIn = null));
    }
    if (!_started.isCompleted) _started.complete();
  }
}

/// Usage counts made before the session started wait here and go once it
/// does, so a visit that never uses the app sends none. Bounded, so a page
/// left open cannot build up a pile.
class WaitingCounts {
  WaitingCounts(this._session, this._send, {this.limit = 20});

  final BackendSession _session;
  final Future<void> Function(String name) _send;
  final int limit;
  final _waiting = <String>[];

  /// Sends now when the session has started, otherwise keeps it for later.
  Future<void> count(String name) async {
    if (_session.isStarted) return _send(name);
    if (_waiting.length >= limit) return;
    _waiting.add(name);
    if (_waiting.length > 1) return;
    unawaited(
      _session.whenStarted.then((_) async {
        final queued = [..._waiting];
        _waiting.clear();
        for (final name in queued) {
          await _send(name).catchError((_) {});
        }
      }),
    );
  }
}
