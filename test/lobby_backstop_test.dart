import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/lobby_backstop.dart';

// Short real intervals: each test waits a few ticks, never seconds.
const tick = Duration(milliseconds: 20);
Future<void> ticks(int count) => Future.delayed(tick * count + tick ~/ 2);

void main() {
  test(
    'asks on every tick and reconnects while the server is ahead of the listener',
    () async {
      var status = 'lobby';
      var asked = 0;
      var reconnects = 0;
      final backstop = LobbyBackstop(
        status: () async {
          asked++;
          return status;
        },
        onBehind: () async => reconnects++,
        every: tick,
      )..start();

      await ticks(2);
      expect(asked, greaterThanOrEqualTo(2));
      expect(reconnects, 0, reason: 'nothing to catch up on in the lobby');

      status = 'voting';
      await ticks(1);
      expect(reconnects, greaterThanOrEqualTo(1));

      // The listener caught up, so its owner stops the checks.
      backstop.stop();
      final settled = asked;
      await ticks(3);
      expect(asked, settled, reason: 'no more questions once stopped');
    },
  );

  test(
    'a failed question is retried; an answer after stop changes nothing',
    () async {
      var fail = true;
      var reconnects = 0;
      late LobbyBackstop backstop;
      backstop = LobbyBackstop(
        status: () async {
          if (fail) throw StateError('offline');
          // The listener caught up while this question was out.
          backstop.stop();
          return 'voting';
        },
        onBehind: () async => reconnects++,
        every: tick,
      )..start();

      await ticks(1);
      expect(backstop.running, isTrue, reason: 'a failed check is retried');
      fail = false;
      await ticks(2);
      expect(reconnects, 0);
      expect(backstop.running, isFalse);
    },
  );
}
