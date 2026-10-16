import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/result_nudges.dart';

void main() {
  // testWidgets runs in fake time, so timers advance with tester.pump.
  testWidgets('nudges on start, after voting ends, then only on the fallback', (
    tester,
  ) async {
    var sent = 0;
    final now = DateTime(2026, 10, 7, 12);
    final nudges = ResultNudges(() async => sent++, clock: () => now);

    nudges.start();
    expect(sent, 1);

    nudges.votingEndsAt(now.add(const Duration(seconds: 20)));
    // Repeated room updates carry the same end time and schedule nothing new.
    nudges.votingEndsAt(now.add(const Duration(seconds: 20)));
    await tester.pump(const Duration(seconds: 20));
    expect(sent, 1, reason: 'waits past the end time for clock skew');
    await tester.pump(const Duration(seconds: 1));
    expect(sent, 2);

    await tester.pump(const Duration(seconds: 39));
    expect(sent, 3, reason: 'one-minute fallback');
    nudges.stop();
    await tester.pump(const Duration(minutes: 5));
    expect(sent, 3);
  });

  testWidgets('an end time already past nudges straight away', (tester) async {
    var sent = 0;
    final now = DateTime(2026, 10, 7, 12);
    final nudges = ResultNudges(() async => sent++, clock: () => now);
    nudges.votingEndsAt(now.subtract(const Duration(minutes: 1)));
    await tester.pump(const Duration(milliseconds: 1));
    expect(sent, 1);
    nudges.stop();
  });

  testWidgets('a failed nudge is swallowed and the next one still runs', (
    tester,
  ) async {
    var attempts = 0;
    final nudges = ResultNudges(() async {
      attempts++;
      throw Exception('offline');
    }, fallback: const Duration(seconds: 10))..start();
    await tester.pump(const Duration(seconds: 10));
    expect(attempts, 2);
    nudges.stop();
  });
}
