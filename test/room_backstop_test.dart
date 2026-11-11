import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/room_backstop.dart';

// Short real intervals: each test waits a few ticks, never seconds.
const tick = Duration(milliseconds: 20);
Future<void> ticks(int count) => Future.delayed(tick * count + tick ~/ 2);

void main() {
  test(
    'hands over the server view as soon as it is ahead of the listener',
    () async {
      var server = 'lobby';
      String? listener = 'lobby';
      var asked = 0;
      final views = <String>[];
      final backstop = RoomBackstop(
        ask: () async {
          asked++;
          return {'status': server};
        },
        shown: () => listener,
        onAhead: (view) => views.add(view['status'] as String),
        reconnect: () async {},
        every: tick,
      )..start();

      await ticks(2);
      expect(asked, greaterThanOrEqualTo(2));
      expect(views, isEmpty, reason: 'nothing to catch up on in the lobby');

      server = 'voting';
      await ticks(1);
      expect(views, contains('voting'));

      // The screen now shows voting, so the same answer is no longer ahead.
      listener = 'voting';
      final seen = views.length;
      await ticks(2);
      expect(views.length, seen);

      backstop.stop();
      final settled = asked;
      await ticks(3);
      expect(asked, settled, reason: 'no more questions once stopped');
    },
  );

  test('restarts the live connection at most once per gap', () async {
    var reconnects = 0;
    var now = DateTime(2026, 11, 11, 12);
    final backstop = RoomBackstop(
      ask: () async => {'status': 'voting'},
      // The listener never catches up in this test.
      shown: () => 'lobby',
      onAhead: (_) {},
      reconnect: () async => reconnects++,
      every: tick,
      reconnectGap: const Duration(seconds: 30),
      clock: () => now,
    )..start();

    await ticks(4);
    expect(reconnects, 1, reason: 'a slow reconnect is left to finish');

    now = now.add(const Duration(seconds: 31));
    await ticks(2);
    expect(reconnects, 2);
    backstop.stop();
  });

  test(
    'a failed question is retried; an answer after stop changes nothing',
    () async {
      var fail = true;
      var ahead = 0;
      late RoomBackstop backstop;
      backstop = RoomBackstop(
        ask: () async {
          if (fail) throw StateError('offline');
          // The listener caught up while this question was out.
          backstop.stop();
          return {'status': 'voting'};
        },
        shown: () => 'lobby',
        onAhead: (_) => ahead++,
        reconnect: () async {},
        every: tick,
      )..start();

      await ticks(1);
      expect(backstop.running, isTrue, reason: 'a failed check is retried');
      fail = false;
      await ticks(2);
      expect(ahead, 0);
      expect(backstop.running, isFalse);
    },
  );

  test('before the listener shows anything, any answer is news', () async {
    final views = <String>[];
    final backstop = RoomBackstop(
      ask: () async => {'status': 'lobby'},
      shown: () => null,
      onAhead: (view) => views.add(view['status'] as String),
      reconnect: () async {},
      every: tick,
    )..start();
    await ticks(1);
    expect(views, contains('lobby'));
    backstop.stop();
  });

  test('rooms only move forward', () {
    expect(roomStage('lobby'), lessThan(roomStage('voting')));
    expect(roomStage('voting'), lessThan(roomStage('closed')));
    expect(roomStage(null), roomStage('lobby'));
  });
}
