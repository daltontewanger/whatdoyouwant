import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/services/callable_room_backend.dart';
import 'package:whatdoyouwant/services/legacy_room_backend.dart';

Restaurant place(String id, double distance) =>
    Restaurant(id: id, name: id, address: '', distance: distance);

final deck = [place('far', 3), place('near', 1), place('mid', 2)];

void main() {
  group('legacy results (production behaviour)', () {
    test('the most-liked restaurant wins with its like count', () {
      final results =
          legacyResults(
            {
              'a': {'far': true, 'near': false},
              'b': {'far': true, 'mid': true},
            },
            deck,
            3,
          )!;
      expect(results.winnerId, 'far');
      expect(results.winnerLikes, 2);
      expect(results.participants, 3);
    });

    test('a tie goes to the closest of the tied restaurants', () {
      final results =
          legacyResults(
            {
              'a': {'far': true},
              'b': {'mid': true},
            },
            deck,
            2,
          )!;
      expect(results.winnerId, 'mid');
      expect(results.winnerLikes, 1);
    });

    test('no likes at all picks the closest restaurant with zero votes', () {
      final results =
          legacyResults(
            {
              'a': {'far': false},
            },
            deck,
            1,
          )!;
      expect(results.winnerId, 'near');
      expect(results.winnerLikes, 0);
    });

    test('a single top choice missing from the deck yields no result', () {
      expect(
        legacyResults(
          {
            'a': {'gone': true},
          },
          deck,
          1,
        ),
        isNull,
      );
    });

    test('tied choices all missing from the deck fall back to the closest', () {
      final results =
          legacyResults(
            {
              'a': {'gone1': true},
              'b': {'gone2': true},
            },
            deck,
            2,
          )!;
      expect(results.winnerId, 'near');
      expect(results.winnerLikes, 1);
    });
  });

  group('legacy room state', () {
    Map<String, dynamic> room({Map<String, dynamic> stats = const {}}) => {
      'creator': 'host',
      'status': 'voting',
      'participants': {'host': true, 'guest': true},
      'restaurants': [for (final r in deck) r.toJson()],
      'votes': {
        'host': {'far': true, 'near': true, 'mid': false},
        'guest': {'far': true},
      },
      'stats': stats,
    };

    test('falls back to counting finished voters when stats are missing', () {
      final state = legacyRoomState('ABC123', room(), 'guest');
      expect(state.joinCode, 'ABC123');
      expect(state.memberCount, 2);
      expect(state.restaurants.map((r) => r.id), ['far', 'near', 'mid']);
      expect(state.myVoteCount, 1);
      expect(state.resultsReady, isFalse);
      expect(state.remainingVoters, 1);
      expect(state.everyoneDone, isFalse);
    });

    test('is ready once every participant has voted on everything', () {
      final data =
          room()
            ..['votes'] = {
              'host': {'far': true, 'near': true, 'mid': false},
              'guest': {'far': true, 'near': false, 'mid': false},
            };
      final state = legacyRoomState('ABC123', data, 'host');
      expect(state.resultsReady, isTrue);
      expect(state.everyoneDone, isTrue);
      expect(state.results!.winnerId, 'far');
    });
  });

  group('callable mapping', () {
    test(
      'typed join codes are normalised and look-alike characters rejected',
      () {
        expect(joinRequestFor(' ab3-k7x '), {'joinCode': 'AB3K7X'});
        expect(joinRequestFor('AB3K7X'), {'joinCode': 'AB3K7X'});
        expect(joinRequestFor('O0I1L5'), isNull);
        expect(joinRequestFor('ABC'), isNull);
      },
    );

    test('the long room ID reconnects instead of joining', () {
      expect(joinRequestFor('5a535286384ff134d226bceb'), {
        'roomId': '5A535286384FF134D226BCEB',
      });
    });

    test('candidates become restaurants with their fictional details', () {
      final r = candidateRestaurant('fixture-pizza', {
        'title': 'Demo Pizza',
        'address': '1 Example Street',
        'distanceMiles': 0.25,
        'order': 0,
      });
      expect(
        (r.id, r.name, r.address, r.distance),
        ('fixture-pizza', 'Demo Pizza', '1 Example Street', 0.25),
      );
    });

    test('server results keep winner, backup and totals', () {
      final results =
          callableResults({
            'likes': {'a': 2, 'b': 1},
            'winner': 'a',
            'backup': 'b',
            'voters': 2,
          }, 3)!;
      expect(results.winnerId, 'a');
      expect(results.backupId, 'b');
      expect(results.winnerLikes, 2);
      expect(results.participants, 3);
      expect(callableResults(null, 3), isNull);
    });
  });
}
