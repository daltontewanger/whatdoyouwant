import 'package:flutter/material.dart';

import '../services/room_backend.dart';
import '../themes/main_theme.dart';
import 'food_loader.dart';

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
/// more, and the host as "Name (you)", or "You" without a nickname.
List<String> voterLabels(List<VoterProgress> people) {
  final guests = people.where((p) => p.name == null && !p.host).length;
  var guest = 0;
  return [
    for (final person in people)
      person.host
          ? (person.name == null ? 'You' : '${person.name} (you)')
          : person.name ?? (guests == 1 ? 'Guest' : 'Guest ${++guest}'),
  ];
}

/// The host's screen after they finish voting: the food bubbles to show the
/// room is still going, the room's votes as a running total, and two panels,
/// people still deciding (with a note when someone has gone quiet, never how
/// far anyone has got) and people who have decided, as chips that wrap so a
/// full room stays short. Once only quiet people are left, the host can finish
/// without them.
class HostWaiting extends StatelessWidget {
  const HostWaiting({
    super.key,
    required this.progress,
    required this.checkedAt,
    required this.finishing,
    required this.onFinish,
  });

  final HostProgress? progress;
  final DateTime? checkedAt;
  final bool finishing;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = progress?.people;
    final left = people == null ? const <VoterProgress>[] : stillVoting(people);
    final labels = people == null ? const <String>[] : voterLabels(people);
    String label(VoterProgress person) => labels[people!.indexOf(person)];
    final decided =
        people == null
            ? const <VoterProgress>[]
            : [
              for (final person in people)
                if (person.done) person,
            ];
    Widget avatar(VoterProgress person, {double size = 40}) => _Avatar(
      label: label(person),
      host: person.host,
      guest: person.name == null && !person.host,
      size: size,
    );
    final finishAt =
        people == null || checkedAt == null
            ? null
            : finishesWithoutThemAt(people, checkedAt!);
    final votesIn = progress?.votesIn ?? 0;
    final votesTotal = progress?.votesTotal ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "You've decided",
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium!.copyWith(
            fontSize: 26,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        const Center(child: FoodLoader()),
        const SizedBox(height: 12),
        if (progress == null)
          Text(
            'Checking who is still voting...',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge!.copyWith(color: inkSoft),
          )
        else ...[
          Text(
            '$votesIn of $votesTotal votes in',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge!.copyWith(color: inkSoft),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              // The bar slides to each new total instead of jumping.
              tween: Tween(end: votesTotal == 0 ? 0 : votesIn / votesTotal),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder:
                  (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    color: primaryGreen,
                    backgroundColor: primaryGreen.withValues(alpha: 0.12),
                    semanticsLabel: 'Votes in',
                  ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (left.isNotEmpty)
          _Panel(
            title: 'Deciding what they want',
            count: left.length,
            colour: _deciding,
            ink: const Color(0xFF222222),
            child: Column(
              children: [
                for (final person in left)
                  _Arrive(
                    key: ValueKey('deciding-${label(person)}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          avatar(person),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label(person),
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                          if (person.inactive >= inactiveAfter)
                            _InactiveChip(minutes: person.inactive.inMinutes),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (left.isNotEmpty && decided.isNotEmpty) const SizedBox(height: 10),
        if (decided.isNotEmpty)
          _Panel(
            title: 'Already decided',
            count: decided.length,
            colour: _mint,
            ink: _mintInk,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final person in decided)
                  _Arrive(
                    key: ValueKey('decided-${label(person)}'),
                    child: _DecidedChip(
                      label: label(person),
                      avatar: avatar(person, size: 24),
                    ),
                  ),
              ],
            ),
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

const _deciding = Color(0xFFF4F2EC);
const _mint = Color(0xFFE1F5EE);
const _mintInk = Color(0xFF085041);

/// A soft panel with a title and how many people are in it.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.count,
    required this.colour,
    required this.ink,
    required this.child,
  });

  final String title;
  final int count;
  final Color colour;
  final Color ink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: theme.textTheme.bodySmall!.copyWith(color: ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

const _initials = [
  (Color(0xFFEEEDFE), Color(0xFF3C3489)),
  (Color(0xFFE6F1FB), Color(0xFF0C447C)),
  (Color(0xFFFBEAF0), Color(0xFF72243E)),
  (Color(0xFFFAEEDA), Color(0xFF633806)),
];

/// A person's circle with the first letter of how they are listed: the
/// host's in green, a guest's "G" in a plain grey, and a soft colour for each
/// nickname.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    required this.host,
    required this.guest,
    required this.size,
  });

  final String label;
  final bool host;

  final bool guest;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (background, ink) =
        host
            ? (primaryGreen, Colors.white)
            : guest
            ? (const Color(0xFFF1EFE8), const Color(0xFF444441))
            : _initials[label.codeUnitAt(0) % _initials.length];
    final inside = Text(
      label.characters.first.toUpperCase(),
      style: TextStyle(
        color: ink,
        fontSize: size * 0.4,
        fontWeight: FontWeight.w700,
      ),
    );
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: inside,
      ),
    );
  }
}

class _InactiveChip extends StatelessWidget {
  const _InactiveChip({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: _butter,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, size: 14, color: _amberInk),
          const SizedBox(width: 4),
          Text(
            'Inactive $minutes min',
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: _amberInk,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Someone who has decided: their circle and name in a small white chip.
class _DecidedChip extends StatelessWidget {
  const _DecidedChip({required this.label, required this.avatar});

  final String label;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(color: _mintInk),
          ),
        ],
      ),
    );
  }
}

/// Fades and slides in a person the first time they appear in a panel, so
/// moving from deciding to decided reads as movement.
class _Arrive extends StatelessWidget {
  const _Arrive({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder:
          (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 8),
              child: child,
            ),
          ),
      child: child,
    );
  }
}
