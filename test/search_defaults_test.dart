import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';

class FakeAccountSettings implements AccountSettings {
  @override
  String? verifiedUid;
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
    expect(
      (await DeviceSearchDefaults().load(), DeviceSearchDefaults().zip),
      (thaiKm, null),
    );
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

    test('offline, the device copy is used', () async {
      await store().save(thaiKm);
      account
        ..verifiedUid = 'host'
        ..offline = true;
      expect(await store().load(), thaiKm);
    });
  });
}
