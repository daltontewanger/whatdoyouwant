import 'dart:async';

import 'package:flutter/foundation.dart';

/// Sends uncaught app errors to the backend's error log. Each distinct error
/// is sent once, a session sends only a few, and a failed send is dropped:
/// reporting must never be the thing that breaks the app.
class ErrorReporter {
  ErrorReporter(this._send, {required this.build, this.maxReports = 5});

  final Future<void> Function(Map<String, Object> report) _send;
  final int build;
  final int maxReports;
  final _seen = <String>{};

  /// Catches framework errors and errors that escape every handler.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, fatal: true);
      // Leave the error to the platform's default handling as well.
      return false;
    };
  }

  /// Returns whether the error was sent on to the backend.
  Future<bool> report(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    final message = _clip(error.toString(), 1000);
    final trace = _clip(stack?.toString() ?? '', 6000);
    if (message.isEmpty || _seen.length >= maxReports) return false;
    // The same error from the same place counts once.
    if (!_seen.add('$message\n${trace.split('\n').take(3).join('\n')}')) {
      return false;
    }
    try {
      await _send({
        'message': message,
        if (trace.isNotEmpty) 'stack': trace,
        'build': build,
        'fatal': fatal,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);
}
