import 'package:flutter/material.dart';

import '../services/accessibility.dart';
import '../services/room_backend.dart';
import '../themes/main_theme.dart';
import 'bubble_icons.dart';
import 'food_loader.dart';
import 'room_roster.dart';

/// Seconds each card waits before it counts as a No.
const swipeSeconds = 15;

/// How voting works, in the same words wherever it is shown: while waiting
/// for the host, behind the swipe screen's help, and in the demo.
class WhatToExpect extends StatelessWidget {
  const WhatToExpect({super.key});

  @override
  Widget build(BuildContext context) {
    final untimed = votesWithoutTimer(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Line(
          icon: BubbleIcon(BubbleGlyph.yes, size: 34),
          text: 'Swipe right or tap "Yes" for a place you want.',
        ),
        const _Line(
          icon: BubbleIcon(BubbleGlyph.no, size: 34, tailRight: true),
          text: 'Swipe left or tap "No" for a place you don\'t want.',
        ),
        const _Line(
          icon: BubbleIcon(BubbleGlyph.favorite, size: 34),
          text: 'Favorite counts as a yes and saves it for next time.',
        ),
        const _Line(
          icon: BubbleIcon(BubbleGlyph.never, size: 34),
          text: 'Never counts as a no and keeps it out of future picks.',
        ),
        _Line(
          icon: const SizedBox.square(
            dimension: 34,
            child: Icon(Icons.schedule, color: Color(0xFFBA7517), size: 24),
          ),
          text:
              untimed
                  ? "No timer for you, so take your time. If you don't vote "
                      'for 3 minutes, the rest count as a no.'
                  : 'Each place has a $swipeSeconds second timer to decide. '
                      'If it runs out, it counts as a no.',
        ),
      ],
    );
  }
}

/// "What to expect" with the list, in a soft panel.
class WhatToExpectPanel extends StatelessWidget {
  const WhatToExpectPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F2EC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'What to expect',
              style: theme.textTheme.bodyLarge!.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const WhatToExpect(),
        ],
      ),
    );
  }
}

/// "What am I supposed to do?" above the cards: folded by default so the
/// cards and timer show first, and opens to the same list.
class SwipeHelp extends StatefulWidget {
  const SwipeHelp({super.key});

  @override
  State<SwipeHelp> createState() => _SwipeHelpState();
}

class _SwipeHelpState extends State<SwipeHelp> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 0, 12, _open ? 8 : 0),
        decoration: BoxDecoration(
          color: _open ? const Color(0xFFF4F2EC) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              // The label wraps at large text sizes instead of running off
              // the card.
              child: TextButton(
                onPressed: () => setState(() => _open = !_open),
                style: TextButton.styleFrom(foregroundColor: primaryGreen),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.help_outline, size: 18),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'What am I supposed to do?',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (_open) const WhatToExpect(),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ExcludeSemantics(child: icon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: const Color(0xFF222222)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The demo's look at the other side: the card someone who joins sees while
/// the host gets ready, with the demo's people and this person as a guest.
class JoiningPreview extends StatelessWidget {
  const JoiningPreview({
    super.key,
    required this.people,
    required this.memberCount,
  });

  final List<RoomPerson> people;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asGuest = [
      for (final person in people)
        RoomPerson(name: person.name, host: person.host),
      const RoomPerson(you: true),
    ];
    return Scaffold(
      backgroundColor: screenBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: inkSoft),
                      tooltip: 'Back to the host view',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Text(
                    'Waiting for the host...',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium!.copyWith(
                      fontSize: 26,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(child: FoodLoader(size: FoodLoader.largeSize)),
                  const SizedBox(height: 16),
                  const WhatToExpectPanel(),
                  const SizedBox(height: 20),
                  RoomRoster(people: asGuest, memberCount: memberCount + 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
