import 'package:flutter/material.dart';

import '../services/room_backend.dart';
import 'help_links.dart';
import 'main_shell.dart';

/// Questions people ask about the app, answered in the app so they work
/// offline and in the installed apps. Anything else goes to Support.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const entries = [
    (
      "Why doesn't this place have a website or phone number?",
      "Place details come from our map data provider, HERE. Some places don't "
          "list a website or phone number there, and we don't guess one, so "
          "you won't be sent to a wrong or unrelated site. You can still get "
          'directions to them.',
    ),
    (
      'What does "You\'ve been found wanting" mean?',
      "It's our name for the menu of other ways to decide, for when swiping "
          "with a group isn't what you need right now. Nobody is judging you. "
          'Much.',
    ),
    (
      'What\'s "Tell Me What I Want"?',
      'We search near you and hand you one place. Not feeling it? Ask for '
          'another, up to 5 times from the same search. It uses one of your '
          'weekly searches, like a room does.',
    ),
    (
      'What\'s "We\'ll Decide What We Want"?',
      'Your own list of places you type in yourself. We can pick one for '
          'you, or you can start a room where everyone swipes on the spots you '
          'choose. It never searches, so it never uses one of your weekly '
          'searches. Guests can keep a list and have us pick from it; starting '
          'a room needs an account.',
    ),
    (
      'What are "I know what I want" and "Never what I want"?',
      "They're our names for your favorites and for the places you don't "
          'want to see again. The heart adds a place to I know what I want and '
          'counts as a Yes. The crossed plate adds it to Never what I want, '
          'counts as a No, and keeps it out of what we show you next time. In '
          "a room, the host can choose to mix everyone's favorites in and leave "
          "everyone's never places out. Nobody sees whose list a place came "
          'from.',
    ),
    (
      'Why is there a weekly limit on searches?',
      'Every search costs us to look up real places. A weekly limit for each '
          'account keeps the app free with no ads. Joining rooms and voting '
          'never count, and your own list never counts.',
    ),
    (
      'Can anyone see how I voted?',
      'No. Results show how many people liked a place, never who.',
    ),
    (
      'Why did a card vote No for me?',
      "Each card has a short timer so the group isn't kept waiting. When it "
          'runs out, it counts as a No for you. If you\'d rather vote at your '
          'own pace, turn on "No vote timer" in Account > Accessibility '
          'features. The room is told that someone votes without a timer, '
          'never who.',
    ),
    (
      'Do I need an account?',
      'Not to join a room and vote. To start a room\'s search or use Tell Me '
          'What I Want, you need an account with a verified email address.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Questions & answers')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              24 + FloatingBarInset.of(context),
            ),
            children: [
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (question, answer) in entries)
                      ExpansionTile(
                        title: Text(
                          question,
                          style: theme.textTheme.titleMedium!.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        expandedAlignment: Alignment.centerLeft,
                        children: [
                          Text(answer, style: theme.textTheme.bodyLarge),
                        ],
                      ),
                  ],
                ),
              ),
              if (RoomBackendScope.maybeOf(context) != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Something else?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                TextButton(
                  onPressed: () => openSitePage(context, '/support'),
                  child: const Text('Get help on our Support page'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
