import 'package:flutter/material.dart';

import '../services/room_backend.dart';
import '../themes/main_theme.dart';

/// No vote by hand for this long marks someone inactive on the host's list.
/// The server holds the same line before it lets the host finish without them.
const inactiveAfter = Duration(minutes: 1);

/// The server finishes without someone on its own after this long.
const countedOutAfter = Duration(minutes: 3);

const _butter = Color(0xFFFFF1C9);
const _amberInk = Color(0xFF6B4E00);

/// Who is still voting: everyone who isn't done.
List<VoterProgress> stillVoting(List<VoterProgress> people) => [
  for (final person in people)
    if (!person.done) person,
];

/// The host may finish now once everyone still voting has stopped.
bool canFinishWithoutInactive(List<VoterProgress> people) {
  final left = stillVoting(people);
  return left.isNotEmpty &&
      left.every((person) => person.inactive >= inactiveAfter);
}

/// When the server will finish without the people left, if none of them votes
/// again; null while anyone left is still voting.
DateTime? finishesWithoutThemAt(List<VoterProgress> people, DateTime checked) {
  if (!canFinishWithoutInactive(people)) return null;
  var wait = Duration.zero;
  for (final person in stillVoting(people)) {
    final left = countedOutAfter - person.inactive;
    if (left > wait) wait = left;
  }
  return checked.add(wait);
}

/// Names for the list: nicknames, "Guest" for one guest, numbered guests for
/// more, and "You" for the host.
List<String> voterLabels(List<VoterProgress> people) {
  final guests = people.where((p) => p.name == null && !p.host).length;
  var guest = 0;
  return [
    for (final person in people)
      person.host
          ? 'You'
          : person.name ?? (guests == 1 ? 'Guest' : 'Guest ${++guest}'),
  ];
}

/// The host's screen after they finish voting: who is still voting, who has
/// stopped, and, once only people who stopped are left, a way to finish
/// without them. Long rooms stay short: people who are done fold into one line.
class HostWaiting extends StatelessWidget {
  const HostWaiting({
    super.key,
    required this.progress,
    required this.checkedAt,
    required this.finishing,
    required this.onFinish,
  });

  final List<VoterProgress>? progress;
  final DateTime? checkedAt;
  final bool finishing;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = progress;
    final left = people == null ? const <VoterProgress>[] : stillVoting(people);
    final labels = people == null ? const <String>[] : voterLabels(people);
    String label(VoterProgress person) => labels[people!.indexOf(person)];
    final done = people == null ? 0 : people.length - left.length;
    final others =
        people == null ? 0 : people.where((p) => p.done && !p.host).length;
    final finishAt =
        people == null || checkedAt == null
            ? null
            : finishesWithoutThemAt(people, checkedAt!);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "You're done voting",
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium!.copyWith(
            fontSize: 26,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          people == null
              ? 'Checking who is still voting...'
              : left.isEmpty
              ? 'Everyone is done. Getting your result...'
              : 'Waiting on ${left.length} ${left.length == 1 ? 'person' : 'people'} to finish.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge!.copyWith(color: inkSoft),
        ),
        const SizedBox(height: 16),
        for (final person in left)
          _Row(
            label: label(person),
            status:
                person.inactive >= inactiveAfter
                    ? 'Inactive ${person.inactive.inMinutes} min'
                    : 'Voting · ${person.votes} of ${person.total}',
            inactive: person.inactive >= inactiveAfter,
          ),
        if (done > 0)
          _Row(
            label:
                others == 0
                    ? 'You'
                    : 'You and $others other${others == 1 ? '' : 's'}',
            status: 'Done',
            done: true,
          ),
        if (finishAt != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _butter,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${left.length == 1 ? "${label(left.first)} hasn't" : "They haven't"} voted in a while. '
                  "We'll finish without them at "
                  '${TimeOfDay.fromDateTime(finishAt.toLocal()).format(context)}, '
                  'or you can finish now.',
                  style: theme.textTheme.bodyMedium!.copyWith(color: _amberInk),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: finishing ? null : onFinish,
                  child: Text(
                    finishing
                        ? 'Finishing...'
                        : 'Finish without inactive people',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Their unvoted places count as No. Anyone who votes again stays in.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall!.copyWith(color: inkSoft),
          ),
        ] else if (left.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'If everyone still voting goes 3 minutes without a vote, voting '
            'stops automatically.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall!.copyWith(color: inkSoft),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.status,
    this.inactive = false,
    this.done = false,
  });

  final String label;
  final String status;
  final bool inactive;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        done
            ? primaryGreen
            : inactive
            ? _amberInk
            : inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          if (done || inactive)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                done ? Icons.check : Icons.schedule,
                size: 18,
                color: color,
              ),
            ),
          Text(
            status,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
