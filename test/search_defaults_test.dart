import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';

class FakeAccountSettings implements AccountSettings {
  @override
  String? verifiedUid;
  @override
  bool isGuest = true;
  final signIns = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => signIns.stream;
  final stored = <String, Map<String, dynamic>>{};
  final writes = <(String, Map<String, Object>)>[];
  bool offline = false;

  @override
  Future<Map<String, dynamic>?> read(String uid) async {
    if (offline) throw StateError('offline');
    return stored[uid];
  }

  @override
  Future<void> write(String uid, Map<String, Object> fields) async {
    writes.add((uid, fields));
    stored[uid] = fields;
  }
}

const thaiKm = SearchPreferences(
  unit: DistanceUnit.km,
  radius: 10,
  deckSize: 25,
  includedCuisineIds: ['thai'],
  openNowPreferred: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved values no longer offered fall back instead of failing', () {
    final read = SearchPreferences.fromJson({
      'unit': 'ft',
      'radius': 7,
      'deckSize': 25,
      'includedCuisineIds': ['thai', 'thai', 'tacos', 'pizza'],
      'excludedCuisineIds': ['pizza', 'seafood', 3],
      'openNowPreferred': 'yes',
    });
    expect(
      read,
      const SearchPreferences(
        deckSize: 25,
        includedCuisineIds: ['thai', 'pizza'],
        excludedCuisineIds: ['seafood'],
      ),
    );
    expect(SearchPreferences.fromJson(thaiKm.toJson()), thaiKm);
    expect(SearchPreferences.fromJson(null), const SearchPreferences());
  });

  test('a ZIP code lasts only while the app runs', () async {
    final device = DeviceSearchDefaults();
    final defaults = AccountSearchDefaults(
      device: device,
      account: FakeAccountSettings()..verifiedUid = 'uid-1',
    );
    await defaults.load();
    defaults.zip = '67202';
    await defaults.save(thaiKm);
    await defaults.load();
    expect(defaults.zip, '67202', reason: 'reloading keeps it in this session');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().map(prefs.get).join(), isNot(contains('67202')));
    expect(
      (defaults.account as FakeAccountSettings).writes.toString(),
      isNot(contains('67202')),
    );
    final restarted = AccountSearchDefaults(
      device: DeviceSearchDefaults(),
      account: FakeAccountSettings()..verifiedUid = 'uid-1',
    );
    expect(await restarted.load(), thaiKm);
    expect(restarted.zip, isNull);
  });

  test('distances read in the person\'s unit', () {
    expect(distanceText(0.25, DistanceUnit.mi), '0.25 mi');
    expect(distanceText(3, DistanceUnit.km), '4.8 km');
    expect(distanceText(12, DistanceUnit.mi), '12 mi');
  });

  group('account defaults', () {
    late FakeAccountSettings account;
    AccountSearchDefaults store() =>
        AccountSearchDefaults(device: DeviceSearchDefaults(), account: account);

    setUp(() => account = FakeAccountSettings());

    test(
      'guests and unverified accounts keep them on the device only',
      () async {
        await store().save(thaiKm);
        await pumpEventQueue();
        expect(account.writes, isEmpty);
        expect(
          await store().load(),
          thaiKm,
          reason: 'read back from the device',
        );
      },
    );

    test(
      'a verified account saves to both and loads its own on a new device',
      () async {
        account.verifiedUid = 'host';
        await store().save(thaiKm);
        await pumpEventQueue();
        expect(account.writes.single.$1, 'host');
        expect(SearchPreferences.fromJson(account.writes.single.$2), thaiKm);

        SharedPreferences.setMockInitialValues({});
        final fresh = store();
        expect(await fresh.load(), thaiKm);
        expect(fresh.current, thaiKm);
      },
    );

    test(
      'signing up carries the guest\'s device defaults into the account',
      () async {
        await store().save(thaiKm);
        account.verifiedUid = 'new-account';
        await store().load();
        await pumpEventQueue();
        expect(account.writes.map((w) => w.$1), ['new-account']);
        expect(
          SearchPreferences.fromJson(account.stored['new-account']),
          thaiKm,
        );
      },
    );

    test('nothing is written for an account until a choice was made', () async {
      account.verifiedUid = 'host';
      expect(await store().load(), const SearchPreferences());
      await pumpEventQueue();
      expect(account.writes, isEmpty);
    });

    test("offline, the account's device copy is used", () async {
      account.verifiedUid = 'host';
      await store().save(thaiKm);
      account.offline = true;
      expect(await store().load(), thaiKm);
    });

    test(
      "one account's setup never shows for the next account on this device",
      () async {
        account
          ..verifiedUid = 'gmail'
          ..isGuest = false;
        await store().save(thaiKm);
        await pumpEventQueue();
        // Signed out: a guest gets the defaults, not the account's setup.
        account
          ..verifiedUid = null
          ..isGuest = true;
        expect(await store().load(), const SearchPreferences());
        // A brand-new account starts from the defaults too, and nothing of the
        // first account's is copied into it.
        account
          ..verifiedUid = 'new-email'
          ..isGuest = false;
        expect(await store().load(), const SearchPreferences());
        await pumpEventQueue();
        expect(account.writes.map((w) => w.$1), ['gmail']);
        // Back on the first account, its own setup returns.
        account.verifiedUid = 'gmail';
        expect(await store().load(), thaiKm);
      },
    );

    test('signing in or out reloads on its own', () async {
      account.stored['host'] = thaiKm.toJson();
      final defaults = store();
      await defaults.load();
      expect(defaults.current, const SearchPreferences());
      account
        ..verifiedUid = 'host'
        ..isGuest = false;
      account.signIns.add(null);
      await pumpEventQueue();
      expect(defaults.current, thaiKm);
      account
        ..verifiedUid = null
        ..isGuest = true;
      account.signIns.add(null);
      await pumpEventQueue();
      expect(defaults.current, const SearchPreferences());
      defaults.dispose();
    });

    test(
      'the old shared copy goes to whoever is signed in when the update arrives',
      () async {
        SharedPreferences.setMockInitialValues({
          'searchDefaults':
              '{"unit":"km","radius":10,"deckSize":25,"includedCuisineIds":["thai"],"excludedCuisineIds":[],"openNowPreferred":true}',
        });
        account
          ..verifiedUid = 'host'
          ..isGuest = false;
        expect(await store().load(), thaiKm);
        account
          ..verifiedUid = null
          ..isGuest = true;
        expect(
          await store().load(),
          const SearchPreferences(),
          reason: "not the guest's",
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('searchDefaults'), isFalse);

        SharedPreferences.setMockInitialValues({
          'searchDefaults': '{"radius":3}',
        });
        expect(
          (await store().load()).radius,
          3,
          reason: 'a guest keeps their own',
        );
      },
    );
  });
}
