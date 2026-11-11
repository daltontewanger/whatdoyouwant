import 'package:flutter/material.dart';

import '../models/cuisines.dart';
import '../models/insights.dart';
import '../services/browser_address.dart';
import '../services/room_backend.dart';

/// The owner's usage page: daily totals only, read-only, and refused by the
/// server to anyone but the owner. Nothing shows until the server agrees;
/// anyone else is quietly taken back to Home, so the page gives nothing away.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    this.today,
    this.leaveAddress = showAppHomeAddress,
  });

  /// Fixed in tests; the device's date otherwise.
  final DateTime? today;

  /// Clears this page from the browser's address when someone is turned away.
  final void Function() leaveAddress;

  static const ranges = [7, 30, 90, 180];

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _days = InsightsScreen.ranges.first;
  InsightsReport? _report;
  Object? _error;
  // Set once the server has answered; until then nothing of the page shows.
  bool _allowed = false;
  bool _loading = false;
  int _request = 0;

  DateTime get _today {
    final now = (widget.today ?? DateTime.now()).toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_report == null && !_loading && _error == null) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    final backend = RoomBackendScope.of(context).backend;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // This period and the one before it, for the comparisons.
      final report = await backend.insightsReport(
        _today.subtract(Duration(days: _days * 2 - 1)),
        _today,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _report = report;
        _loading = false;
        _allowed = true;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      if (!_allowed) {
        widget.leaveAddress();
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't refresh. Try again.")),
      );
    }
  }

  void _pick(int days) {
    if (days == _days) return;
    setState(() {
      _days = days;
      _report = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final report = _report;
    final current = report?.period(
      _today.subtract(Duration(days: _days - 1)),
      _today,
      today: _today,
    );
    final previous = report?.period(
      _today.subtract(Duration(days: _days * 2 - 1)),
      _today.subtract(Duration(days: _days)),
      today: _today,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in InsightsScreen.ranges)
              ChoiceChip(
                label: Text('$days days'),
                selected: days == _days,
                onSelected: (_) => _pick(days),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Totals only, never people or places. Days run midnight to '
          'midnight UTC; today is included so far.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (current == null || previous == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ..._sections(context, report!, current, previous),
      ],
    );
  }

  List<Widget> _sections(
    BuildContext context,
    InsightsReport report,
    InsightsPeriod now,
    InsightsPeriod before,
  ) {
    final modes = now.modes;
    final outcomes = now.outcomes;
    // Returns need cohorts old enough to have answered, so they look back
    // over both periods rather than only the one picked.
    final cohorts = report.period(
      _today.subtract(Duration(days: _days * 2 - 1)),
      _today,
      today: _today,
    );
    final month = insightsDay(_today).substring(0, 7);
    final ledger = report.months[month];
    final roomsEnded =
        outcomes.unanimous +
        outcomes.majority +
        outcomes.noMatch +
        outcomes.noVotes +
        outcomes.unstarted;
    final platforms =
        now['activeOn_web'] + now['activeOn_android'] + now['activeOn_ios'];
    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: [
          _Tile(
            label: 'Decisions made',
            value: '${now.decisions}',
            note: _change(now.decisions, before.decisions),
          ),
          _Tile(
            label: 'Per provider call',
            value: _number(now.decisionsPerCall),
            note: '${now.providerCalls} calls',
          ),
          _Tile(
            label: 'Sessions a day',
            value: _number(now.averageDailySessions),
            note: _change(now.activeSessions, before.activeSessions),
          ),
          _Tile(
            label: 'Weekly cap hit',
            value: _percent(now.capHitShare),
            note: '${now['weeklyCapHits']} times',
          ),
        ],
      ),
      _Section(
        title: 'Decisions by day',
        children: [
          _Trend(
            values: now.daily(
              (c) => (c['roomsCompleted'] ?? 0) + (c['searchesQuickPick'] ?? 0),
            ),
          ),
        ],
      ),
      _Section(
        title: 'What people use',
        children: _shares([
          ('Group Room, live search', modes.liveRooms),
          ('Group Room, own list', modes.listRooms),
          ('Tell Me What I Want', modes.quickPicks),
        ]),
      ),
      _Section(
        title: 'How rooms end',
        children: [
          ..._shares([
            ('Everyone agreed', outcomes.unanimous),
            ('Majority pick', outcomes.majority),
            ('Nobody liked any', outcomes.noMatch),
            ('Nobody voted', outcomes.noVotes),
            ('Closed before voting', outcomes.unstarted),
          ], whole: roomsEnded),
          _Row(
            'People per room: 2',
            _percent(
              InsightsPeriod.share(
                now['roomVoters_two'],
                now['roomsCompleted'],
              ),
            ),
          ),
          _Row(
            'People per room: 3 to 4',
            _percent(
              InsightsPeriod.share(
                now['roomVoters_threeToFour'],
                now['roomsCompleted'],
              ),
            ),
          ),
          _Row(
            'People per room: 5 or more',
            _percent(
              InsightsPeriod.share(
                now['roomVoters_fivePlus'],
                now['roomsCompleted'],
              ),
            ),
          ),
          _Row(
            'Decided in under 5 minutes',
            _percent(
              InsightsPeriod.share(
                now['decided_under2m'] + now['decided_twoTo5m'],
                now['roomsCompleted'],
              ),
            ),
          ),
          _Row('Yes votes', _percent(now.yesShare)),
          _Row('Cards that timed out', _percent(now.timedOutShare)),
        ],
      ),
      _Section(
        title: 'Getting people in',
        children: [
          _Bar('Demo, then signed up', now.demoToAccount),
          _Bar('Guests who made an account', now.guestToAccount),
          _Bar('Intro skipped', now.introSkipShare),
          _Row('New guests', '${now['newGuests']}'),
          _Row('Guests who joined a room', '${now['roomJoinsGuest']}'),
          _Row('Opened from the website', '${now['tap_openedFromSite']}'),
          _Row('Demos opened', '${now['tap_demoStarted']}'),
        ],
      ),
      _Section(
        title: 'Coming back',
        children: [
          _Bar('Everyone, day 1', cohorts.returned(1)),
          _Bar('Everyone, days 7 to 13', cohorts.returned(7)),
          _Bar('Everyone, days 30 to 59', cohorts.returned(30)),
          _Bar('Accounts, day 1', cohorts.returned(1, accounts: true)),
          _Bar('Accounts, days 7 to 13', cohorts.returned(7, accounts: true)),
          _Bar('Accounts, days 30 to 59', cohorts.returned(30, accounts: true)),
          Text(
            'Counted for people first seen in the last ${_days * 2} days, once enough '
            'days have passed.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      _Section(
        title: 'Searches and results',
        children: [
          _Bar('Too few places found', now.noResultShare),
          _Bar('Thin decks (fewer than asked)', now.smallPoolShare),
          _Bar('Decisions that opened map or directions', now.directionsShare),
          _Row('Cards per deck', _number(now.averageCards)),
          _Row('Rerolls per Quick Pick', _number(now.averageRerolls)),
          _Row('Quick Picks chosen', '${now['tap_quickPickChosen']}'),
          _Row('Open-now searches', '${now['openNowOn']}'),
          _Row('Failed searches', '${now['searchesFailed']}'),
          _Row('Slow answers (over 3 s)', '${now['providerTime_over3s']}'),
        ],
      ),
      _Section(
        title: 'Taps on results',
        children: [
          _Row('Map', '${now['tap_resultMap'] + now['tap_ownResultMap']}'),
          _Row(
            'Directions',
            '${now['tap_resultDirections'] + now['tap_ownResultDirections']}',
          ),
          _Row('Website', '${now['tap_resultWebsite']}'),
          _Row('Call', '${now['tap_resultPhone']}'),
          _Row('Share', '${now['tap_resultShare']}'),
        ],
      ),
      _Section(
        title: 'Joining rooms',
        children: [
          _Row('Joined by link', '${now['tap_joinWithLink']}'),
          _Row('Joined by code', '${now['tap_joinWithCode']}'),
          _Row('Join links copied', '${now['tap_shareRoomCode']}'),
          _Row('Joins, all', '${now['roomJoins']}'),
        ],
      ),
      _Section(
        title: 'Cuisines',
        children: [
          Text(
            'Picked as filters',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          ..._top(now.top('cuisinePicked_'), label: cuisineLabel),
          const SizedBox(height: 8),
          Text('Won rooms', style: Theme.of(context).textTheme.labelLarge),
          ..._top(now.top('winnerCuisine_'), label: cuisineLabel),
        ],
      ),
      _Section(
        title: 'Settings people search with',
        children: [
          ..._top(
            now.top('radius_'),
            label:
                (id) => id
                    .replaceAll('_', '.')
                    .replaceAllMapped(RegExp(r'(mi|km)$'), (m) => ' ${m[1]}'),
          ),
          ..._top(now.top('deckSize_'), label: (id) => '$id cards'),
        ],
      ),
      _Section(
        title: 'Devices and versions',
        children: [
          ..._shares([
            ('Web', now['activeOn_web']),
            ('Android', now['activeOn_android']),
            ('iPhone', now['activeOn_ios']),
          ], whole: platforms),
          ..._top(now.top('activeBuild_'), label: (id) => 'Build $id'),
        ],
      ),
      _Section(
        title: 'Busiest hours (UTC)',
        children: _top(
          now.top('hourUtc_', limit: 4),
          label: (id) => '${id.padLeft(2, '0')}:00',
        ),
      ),
      _Section(
        title: 'Cost and limits',
        children: [
          _Row(
            'Provider calls this month',
            ledger == null ? '0' : '${ledger.providerCalls}',
          ),
          if (report.monthlyCallStop case final stop?)
            _Bar(
              'Of the monthly stop ($stop calls)',
              InsightsPeriod.share(ledger?.providerCalls ?? 0, stop),
            ),
          _Row(
            'Live decks this month',
            ledger == null ? '0' : '${ledger.decks}',
          ),
          _Row(
            'Weekly searches allowed',
            report.weeklyCap?.toString() ?? 'Not set',
          ),
          _Row('Live search', report.liveEnabled == false ? 'Paused' : 'On'),
          _Row('Live search paused when tried', '${now['livePausedHits']}'),
        ],
      ),
      _Section(
        title: 'Support and moderation',
        children: [
          _Row('Closed reports', '${now['placeReports_closed']}'),
          _Row(
            'Wrong website or phone',
            '${now['placeReports_website'] + now['placeReports_phone']}',
          ),
          _Row('Wrong spot', '${now['placeReports_location']}'),
          _Row('Places hidden', '${now['placesHidden']}'),
          _Row('App errors reported', '${now['clientErrors']}'),
          _Row('Accounts deleted', '${now['accountsDeleted']}'),
        ],
      ),
    ];
  }

  List<Widget> _shares(List<(String, int)> rows, {int? whole}) {
    final total = whole ?? rows.fold<int>(0, (sum, row) => sum + row.$2);
    return [
      for (final (label, value) in rows)
        _Bar(label, InsightsPeriod.share(value, total), count: value),
    ];
  }

  List<Widget> _top(
    List<(String, int)> rows, {
    required String Function(String) label,
  }) {
    if (rows.isEmpty) return [const _Row('Nothing yet', '')];
    final most = rows.first.$2;
    return [
      for (final (id, value) in rows)
        _Bar(
          label(id),
          InsightsPeriod.share(value, most),
          count: value,
          showCount: true,
        ),
    ];
  }

  static String _percent(double? share) =>
      share == null ? '–' : '${(share * 100).round()}%';

  static String _number(double? value) =>
      value == null ? '–' : value.toStringAsFixed(value >= 10 ? 0 : 1);

  static String _change(int now, int before) {
    if (before == 0) return now == 0 ? 'None before' : 'New this period';
    final change = ((now - before) / before * 100).round();
    return '${change >= 0 ? '+' : ''}$change% vs before';
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.note});

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F7F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall!.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            note,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// A label, a bar for its share, and the share (or count) at the end.
class _Bar extends StatelessWidget {
  const _Bar(this.label, this.share, {this.count, this.showCount = false});

  final String label;
  final double? share;
  final int? count;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end =
        showCount
            ? '${count ?? 0}'
            : share == null
            ? '–'
            : '${(share! * 100).round()}%';
    return Semantics(
      label: '$label: $end',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (share ?? 0).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE6EFEA),
                ),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                end,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

/// One bar per day, tallest day full height.
class _Trend extends StatelessWidget {
  const _Trend({required this.values});

  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final most = values.fold<int>(0, (a, b) => a > b ? a : b);
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label:
          'Decisions by day, from ${values.isEmpty ? 0 : values.first} to ${values.isEmpty ? 0 : values.last}; most in a day $most',
      excludeSemantics: true,
      child: SizedBox(
        height: 72,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final value in values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: values.length > 60 ? 0 : 1,
                  ),
                  child: FractionallySizedBox(
                    heightFactor:
                        most == 0 ? 0.02 : (value / most).clamp(0.02, 1.0),
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      color: value == 0 ? const Color(0xFFE6EFEA) : color,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
