import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/callable_room_backend.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';

void main() {
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

    test('a stored deck becomes restaurants in deck order, in miles', () {
      final cards = deckRestaurants({
        'candidateIds': ['c1', 'c2'],
        'candidates': [
          {
            'id': 'c1',
            'order': 0,
            'name': 'Demo Pizza',
            'address': '1 Example Street',
            'distanceMeters': 1609,
            'latitude': 38.5,
            'longitude': -98.5,
            'phone': '+15550100001',
            'website': 'https://example.com',
          },
          {'id': 'c2', 'order': 1, 'name': 'Demo Kitchen', 'address': null},
        ],
      });
      expect(
        [for (final r in cards) (r.id, r.name, r.address)],
        [('c1', 'Demo Pizza', '1 Example Street'), ('c2', 'Demo Kitchen', '')],
      );
      expect(cards[0].distance, closeTo(1.0, 0.001));
      expect(cards[1].distance, 0);
      expect(
        (cards[0].latitude, cards[0].longitude, cards[0].phone),
        (38.5, -98.5, '+15550100001'),
      );
      expect((cards[1].latitude, cards[1].website), (null, null));
    });

    test('a ZIP code search sends the ZIP code and no location', () {
      expect(
        startSearchFor(null, const SearchPreferences(), zip: '67202')['origin'],
        {'zip': '67202'},
      );
    });

    test('the start search rounds the location and sends offered values', () {
      expect(
        startSearchFor(
          (lat: 38.123456, lng: -98.987654),
          const SearchPreferences(
            unit: DistanceUnit.km,
            radius: 10,
            deckSize: 15,
            includedCuisineIds: ['thai'],
            excludedCuisineIds: ['pizza'],
            openNowPreferred: true,
          ),
        ),
        {
          'origin': {'lat': 38.123, 'lng': -98.988},
          'radius': {'value': 10, 'unit': 'km'},
          'deckSize': 15,
          'includedCuisineIds': ['thai'],
          'excludedCuisineIds': ['pizza'],
          'openNowPreferred': true,
        },
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
      expect(results.winnerCard, isNull);
      expect(callableResults(null, 3), isNull);
      final kept =
          callableResults({
            'likes': {'a': 2},
            'winner': 'a',
            'winnerCard': {
              'id': 'a',
              'name': 'Demo Pizza',
              'address': '1 Example Street',
              'distanceMeters': 3218.688,
              'latitude': 38.5,
              'longitude': -98.5,
              'phone': null,
              'website': 'https://example.com',
            },
          }, 2)!;
      expect(
        (kept.winnerCard!.name, kept.winnerCard!.distance),
        ('Demo Pizza', 2.0),
      );
      expect(kept.winnerCard!.website, 'https://example.com');
    });
  });
}
