import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/room_backend.dart';
import '../services/search_defaults.dart';
import 'bubble_icons.dart';
import 'demo_screen.dart';
import 'place_marks.dart';
import 'room_roster.dart';
import 'step_card.dart';
import '../services/usage_counts.dart';

const _ink = Color(0xFF1F2A24);
const _inkSoft = Color(0xFF4A5A52);
const _line = Color(0xFFCFE6DB);

/// A few pages on how a room works and the other ways to decide, in the
/// site's words. Shown once on a device's first launch and again from the
/// menu. The pictures are drawn, not screenshots, so they stay sharp at any
/// text size; they are decoration, and the words carry everything.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  static const pages = [
    ('Start a room', 'Choose how far to look and how many spots to swipe.'),
    (
      'Share the code',
      'Friends join with the code, a link or a QR code. No account needed.',
    ),
    (
      'Everyone swipes',
      'Swipe right for yes, left for no, each on your own phone. Tap the '
          'heart to save a favorite, or the crossed plate to rule a spot out '
          'for good.',
    ),
    (
      'See where to eat',
      'The spot most of you wanted, a backup and directions. Nobody sees who '
          'voted for what.',
    ),
    (
      'More ways to want',
      'Searches near you need an account with a verified email. Joining a '
          'room and voting never do.',
    ),
  ];

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pages = PageController();
  var _page = 0;

  bool get _last => _page == IntroScreen.pages.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final count = IntroScreen.pages.length;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Visibility(
                  visible: !_last,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: TextButton(
                    onPressed: () {
                      countTap(context, UsageEvent.introSkipped);
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'Skip',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: count,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) {
                  final (title, text) = IntroScreen.pages[index];
                  return _IntroPage(
                    picture: _picture(index),
                    title: title,
                    text: text,
                    action:
                        index == count - 1
                            ? OutlinedButton.icon(
                              onPressed: () {
                                countTap(context, UsageEvent.introFinished);
                                Navigator.of(
                                  context,
                                ).pushReplacement(DemoScreen.route());
                              },
                              icon: const Icon(Icons.science_outlined),
                              label: const Text('Try the demo'),
                            )
                            : null,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Visibility(
                        visible: _page > 0,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: TextButton(
                          onPressed: () => _go(_page - 1),
                          child: const Text(
                            'Back',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Page ${_page + 1} of $count',
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          AnimatedContainer(
                            duration:
                                MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page ? primary : _line,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed:
                            _last
                                ? () {
                                  countTap(context, UsageEvent.introFinished);
                                  Navigator.of(context).pop();
                                }
                                : () => _go(_page + 1),
                        child: Text(_last ? "Let's eat" : 'Next'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _picture(int index) => switch (index) {
    0 => const _Frame(child: _RadiusScene()),
    1 => const _Frame(child: _CodeScene()),
    2 => const _Frame(child: _SwipeScene()),
    3 => const _Frame(child: _ResultsScene()),
    _ => const _MoreWays(),
  };
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.picture,
    required this.title,
    required this.text,
    this.action,
  });

  final Widget picture;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              picture,
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall!.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: _inkSoft,
                  height: 1.4,
                ),
              ),
              if (action case final action?) ...[
                const SizedBox(height: 20),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The site's square picture frame, hidden from screen readers. The scene inside is laid out at a fixed
/// size and scaled to fit, like the site's.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _line, width: 2),
            borderRadius: BorderRadius.circular(32),
          ),
          clipBehavior: Clip.antiAlias,
          child: FittedBox(
            child: SizedBox.square(
              dimension: 240,
              // The scene keeps its own size whatever the person's text size.
              child: MediaQuery.withNoTextScaling(child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.solid = true});

  final String text;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: solid ? primary : Colors.white,
        border: Border.all(color: primary, width: 2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: solid ? Colors.white : primary,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _RadiusScene extends StatelessWidget {
  const _RadiusScene();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final unit = RoomBackendScope.distanceUnitOf(context);
    Widget pin(double left, double top, Color color) => Positioned(
      left: left,
      top: top,
      child: Icon(Icons.location_on, size: 26, color: color),
    );
    return Stack(
      children: [
        Positioned(
          left: 45,
          top: 30,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE3F2EA),
              border: Border.all(color: const Color(0xFF65B292), width: 3),
            ),
          ),
        ),
        Positioned(
          left: 108,
          top: 93,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary,
              border: Border.all(color: Colors.white, width: 4),
            ),
          ),
        ),
        pin(72, 52, const Color(0xFFE5755A)),
        pin(150, 66, const Color(0xFFD9A514)),
        pin(88, 132, const Color(0xFF3B8FCB)),
        pin(146, 122, const Color(0xFFE5755A)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: Center(child: _Tag('5 ${unit.label} · 10 spots')),
        ),
      ],
    );
  }
}

class _CodeScene extends StatelessWidget {
  const _CodeScene();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(color: _line, width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: QrImageView(
            data: 'https://getwhatdoyouwant.app/app/join/AB3K7X',
            size: 88,
            padding: EdgeInsets.zero,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: _ink,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: _ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'AB3 K7X',
          style: TextStyle(
            color: primary,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 6),
        const _Tag('Copy join link', solid: false),
        const SizedBox(height: 10),
        SizedBox(
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final (i, letter) in ['A', 'J', 'M', 'S'].indexed)
                Positioned(
                  left: 120 - 54 + i * 26.0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: RoomRoster.colors[i],
                      child: Text(
                        letter,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwipeScene extends StatelessWidget {
  const _SwipeScene();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final distance = distanceText(
      1.8,
      RoomBackendScope.distanceUnitOf(context),
    );
    Widget mark(String label, Widget icon, Color color, {bool after = false}) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!after) ...[icon, const SizedBox(width: 3)],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
            if (after) ...[const SizedBox(width: 3), icon],
          ],
        );
    return Stack(
      children: [
        Positioned(
          left: 45,
          top: 18,
          child: Transform.rotate(
            angle: -0.09,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: const Color(0xFFD6EEE5),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        Positioned(
          left: 45,
          top: 18,
          child: Container(
            width: 150,
            height: 150,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F8F3),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                children: [
                  Text(
                    'Taco Spot',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('412 Main St', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    'Distance: $distance',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 51,
          top: 140,
          child: mark('Never', const NeverIcon(size: 20), neverColor),
        ),
        Positioned(
          right: 51,
          top: 140,
          child: mark(
            'Favorite',
            const FavoriteIcon(size: 20),
            favoriteColor,
            after: true,
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: 178,
          child: Row(
            children: [
              const BubbleIcon(BubbleGlyph.no, size: 46, tailRight: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      '7',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 22,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: 0.6,
                      color: Colors.orange,
                      backgroundColor: primary.withValues(alpha: 0.13),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const BubbleIcon(BubbleGlyph.yes, size: 46),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultsScene extends StatelessWidget {
  const _ResultsScene();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final distance = distanceText(
      1.8,
      RoomBackendScope.distanceUnitOf(context),
    );
    Widget action(IconData icon, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB9C4BE), width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: primary),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
      child: Column(
        children: [
          Text(
            'Results',
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.w900,
              fontSize: 24,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.celebration, size: 15, color: primary),
                  const SizedBox(width: 4),
                  Text(
                    'Well, most of you wanted it',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Taco Spot',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                  ),
                  const SizedBox(height: 2),
                  const Text('412 Main St', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                    'Distance: $distance · 3 of 4 liked it',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      action(Icons.map_outlined, 'Map'),
                      const SizedBox(width: 6),
                      action(Icons.directions, 'Directions'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreWays extends StatelessWidget {
  const _MoreWays();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      StepCard(
        step: HomeStep(
          'Tell Me What I Want',
          'We search near you and hand you one place.',
          icon: Icons.auto_awesome,
        ),
      ),
      SizedBox(height: 10),
      StepCard(
        step: HomeStep(
          "We'll Decide What We Want",
          'We pick from places you type in yourself.',
          icon: Icons.checklist_rounded,
        ),
      ),
    ],
  );
}
