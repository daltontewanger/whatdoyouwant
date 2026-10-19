import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/error_reporter.dart';

void main() {
  test('sends each distinct error once, up to the session limit', () async {
    final sent = <Map<String, Object>>[];
    final reporter = ErrorReporter(
      (report) async => sent.add(report),
      build: 12,
      maxReports: 2,
    );
    final stack = StackTrace.fromString(
      '#0 main (app.dart:1)\n#1 run (app.dart:2)',
    );

    expect(await reporter.report(StateError('first'), stack), isTrue);
    expect(await reporter.report(StateError('first'), stack), isFalse);
    expect(
      await reporter.report(StateError('second'), null, fatal: true),
      isTrue,
    );
    expect(await reporter.report(StateError('third'), stack), isFalse);

    expect(sent, hasLength(2));
    expect(sent.first, {
      'message': 'Bad state: first',
      'stack': stack.toString(),
      'build': 12,
      'fatal': false,
    });
    expect(sent.last.containsKey('stack'), isFalse);
    expect(sent.last['fatal'], isTrue);
  });

  test('a failed send is swallowed and long text is clipped', () async {
    final reporter = ErrorReporter(
      (report) async => throw Exception('offline'),
      build: 1,
    );
    expect(await reporter.report(Exception('x'), null), isFalse);

    Map<String, Object>? sent;
    final clipping = ErrorReporter((report) async => sent = report, build: 1);
    await clipping.report('y' * 5000, StackTrace.fromString('z' * 9000));
    expect((sent!['message'] as String).length, 1000);
    expect((sent!['stack'] as String).length, 6000);
  });
}
