import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/deck_loader.dart';

void main() {
  test(
    'a failed deck read is tried again instead of ending the room',
    () async {
      var attempts = 0;
      final loader = DeckLoader<String>((id) async {
        attempts++;
        if (attempts == 1) throw StateError('client is offline');
        return 'cards for $id';
      });
      final loaded = <String>[];
      await loader.load('d1', loaded.add);
      expect(attempts, 1);
      expect(loaded, isEmpty);
      expect(loader.loaded, isFalse);
      await loader.load('d1', loaded.add);
      expect(attempts, 2);
      expect(loaded, ['cards for d1']);
      expect(loader.loaded, isTrue);
      // Decks never change, so a loaded one is never read again.
      await loader.load('d1', loaded.add);
      expect(attempts, 2);
    },
  );

  test('a missing deck is tried again too', () async {
    var attempts = 0;
    final loader = DeckLoader<String>(
      (id) async => ++attempts == 1 ? null : 'cards',
    );
    final loaded = <String>[];
    await loader.load('d1', loaded.add);
    await loader.load('d1', loaded.add);
    expect(attempts, 2);
    expect(loaded, ['cards']);
  });

  test(
    'one read at a time, and none once the cards came another way',
    () async {
      final gate = Completer<String?>();
      var attempts = 0;
      final loader = DeckLoader<String>((id) {
        attempts++;
        return gate.future;
      });
      final loaded = <String>[];
      final first = loader.load('d1', loaded.add);
      await loader.load('d1', loaded.add);
      expect(attempts, 1);
      loader.markLoaded();
      gate.complete('late cards');
      await first;
      expect(
        loaded,
        isEmpty,
        reason: 'the catch-up answer already gave the cards',
      );
      await loader.load('d1', loaded.add);
      expect(attempts, 1);
    },
  );
}
