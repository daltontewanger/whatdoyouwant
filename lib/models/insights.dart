/// The owner's usage totals: plain daily counts with no people, rooms,
/// places or locations in them, and what they add up to.
library;

/// A day as the server names it, `YYYY-MM-DD` in UTC.
String insightsDay(DateTime day) {
  final utc = DateTime.utc(day.year, day.month, day.day);
  return utc.toIso8601String().substring(0, 10);
}

class InsightsReport {
  const InsightsReport({
    required this.days,
    required this.months,
    this.liveEnabled,
    this.weeklyCap,
    this.monthlyCallStop,
  });

  /// Each day's totals by counter name.
  final Map<String, Map<String, int>> days;

  /// Provider calls and live decks by month (`YYYY-MM`), from the ledger.
  final Map<String, ({int providerCalls, int decks})> months;

  final bool? liveEnabled;
  final int? weeklyCap;
  final int? monthlyCallStop;

  factory InsightsReport.fromCallable(Map<String, dynamic> raw) {
    int whole(Object? value) => value is num ? value.round() : 0;
    final days = <String, Map<String, int>>{};
    if (raw['days'] case final Map<Object?, Object?> rawDays) {
      for (final MapEntry(:key, :value) in rawDays.entries) {
        if (key is! String || value is! Map) continue;
        days[key] = {
          for (final MapEntry(key: name, :value) in value.entries)
            if (name is String && value is num) name: value.round(),
        };
      }
    }
    final months = <String, ({int providerCalls, int decks})>{};
    if (raw['months'] case final Map<Object?, Object?> rawMonths) {
      for (final MapEntry(:key, :value) in rawMonths.entries) {
        if (key is! String || value is! Map) continue;
        months[key] = (
          providerCalls: whole(value['providerCalls']),
          decks: whole(value['decks']),
        );
      }
    }
    final live = raw['live'] is Map ? raw['live'] as Map : const {};
    return InsightsReport(
      days: days,
      months: months,
      liveEnabled: live['enabled'] is bool ? live['enabled'] as bool : null,
      weeklyCap: live['weeklyCap'] is num ? whole(live['weeklyCap']) : null,
      monthlyCallStop:
          live['monthlyCallStop'] is num
              ? whole(live['monthlyCallStop'])
              : null,
    );
  }

  /// The totals for the days from [from] to [to], inclusive. [today] decides
  /// which cohorts are old enough to have a day-1, 7 or 30 answer yet.
  InsightsPeriod period(DateTime from, DateTime to, {required DateTime today}) {
    final keys = <String>[];
    for (
      var day = DateTime.utc(from.year, from.month, from.day);
      !day.isAfter(DateTime.utc(to.year, to.month, to.day));
      day = day.add(const Duration(days: 1))
    ) {
      keys.add(insightsDay(day));
    }
    return InsightsPeriod._([
      for (final key in keys) (key, days[key] ?? const <String, int>{}),
    ], DateTime.utc(today.year, today.month, today.day));
  }
}

/// A run of days and the numbers the dashboard shows for them.
class InsightsPeriod {
  InsightsPeriod._(this.days, this._today) {
    for (final (_, counts) in days) {
      counts.forEach(
        (name, value) => _totals[name] = (_totals[name] ?? 0) + value,
      );
    }
  }

  /// Each day in order with its totals.
  final List<(String, Map<String, int>)> days;
  final DateTime _today;
  final _totals = <String, int>{};

  int operator [](String name) => _totals[name] ?? 0;

  /// A share as a fraction, or null when there is nothing to divide by.
  static double? share(num part, num whole) => whole > 0 ? part / whole : null;

  // What people decided: rooms that finished with votes, and Quick Picks made.
  int get decisions => this['roomsCompleted'] + this['searchesQuickPick'];
  int get searches => this['searchesRoom'] + this['searchesQuickPick'];
  int get providerCalls => this['providerCalls'];
  int get activeSessions => this['activeGuests'] + this['activeAccounts'];

  double? get decisionsPerCall => share(decisions, providerCalls);
  double? get capHitShare =>
      share(this['weeklyCapHits'], searches + this['weeklyCapHits']);
  double? get noResultShare =>
      share(this['searchesTooFew'], searches + this['searchesTooFew']);
  double? get smallPoolShare => share(this['smallPools'], searches);
  double? get averageRerolls =>
      share(this['quickPickRerolls'], this['searchesQuickPick']);
  double? get averageCards => share(this['candidatesShown'], searches);
  double? get yesShare => share(this['ballotsLiked'], this['ballotsCast']);
  double? get timedOutShare =>
      share(this['ballotsTimedOut'], this['ballotsCast']);
  double? get averageDailySessions => share(activeSessions, days.length);

  /// Group Room with a search, Group Room from a list, and Quick Pick.
  ({int liveRooms, int listRooms, int quickPicks}) get modes => (
    liveRooms: this['searchesRoom'],
    listRooms: this['roomsStartedOwnList'],
    quickPicks: this['searchesQuickPick'],
  );

  /// How rooms ended, including those closed before voting started.
  ({int unanimous, int majority, int noMatch, int noVotes, int unstarted})
  get outcomes => (
    unanimous: this['roomsUnanimous'],
    majority: this['roomsMajority'],
    noMatch: this['roomsNoMatch'],
    noVotes: this['roomsNoVotes'],
    unstarted: this['roomsClosedUnstarted'],
  );

  double? get demoToAccount =>
      share(this['tap_signUpAfterDemo'], this['tap_demoStarted']);
  double? get guestToAccount =>
      share(this['guestsUpgraded'], this['newGuests']);
  double? get introSkipShare => share(
    this['tap_introSkipped'],
    this['tap_introSkipped'] + this['tap_introFinished'],
  );

  /// How often a finished decision led to a tap on map or directions.
  double? get directionsShare => share(
    this['tap_resultMap'] +
        this['tap_resultDirections'] +
        this['tap_ownResultMap'] +
        this['tap_ownResultDirections'],
    decisions,
  );

  /// Of the people first seen on days old enough to tell, the share who
  /// came back on day 1, in days 7 to 13, or in days 30 to 59. With
  /// [accounts], counted from the day the account was made.
  double? returned(int after, {bool accounts = false}) {
    final key = switch (after) {
      1 => 'd1',
      7 => 'd7',
      _ => 'd30',
    };
    var cohort = 0;
    var back = 0;
    for (final (day, counts) in days) {
      if (DateTime.parse(day).add(Duration(days: after)).isAfter(_today)) {
        continue;
      }
      cohort +=
          accounts
              ? (counts['newAccounts'] ?? 0) + (counts['guestsUpgraded'] ?? 0)
              : (counts['newGuests'] ?? 0) + (counts['newAccounts'] ?? 0);
      back += counts['${accounts ? 'accountReturned' : 'returned'}_$key'] ?? 0;
    }
    return share(back, cohort);
  }

  /// The largest counters starting with [prefix], without it, biggest first.
  List<(String, int)> top(String prefix, {int limit = 5}) {
    final found = [
      for (final MapEntry(:key, :value) in _totals.entries)
        if (key.startsWith(prefix) && value > 0)
          (key.substring(prefix.length), value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return found.take(limit).toList();
  }

  /// One number per day, for the trend line.
  List<int> daily(int Function(Map<String, int> counts) pick) => [
    for (final (_, counts) in days) pick(counts),
  ];
}
