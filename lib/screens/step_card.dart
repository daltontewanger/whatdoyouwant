import 'package:flutter/material.dart';

/// The app's greens, light to dark, for the rail's dots: each step a shade
/// deeper on the way to where you eat.
const _railGreens = [
  Color(0xFFB4E0CB),
  Color(0xFF65B292),
  Color(0xFF2F7A5C),
  Color(0xFF1E5641),
];

class HomeStep {
  const HomeStep(this.title, this.text, {required this.icon});

  final String title;
  final String text;
  final IconData icon;
}

const quickPickStep = HomeStep(
  'Tell Me What I Want',
  'Still too much pressure swiping? We can help pick for you.',
  icon: Icons.auto_awesome,
);

const ownListStep = HomeStep(
  "We'll Decide What We Want",
  "Already have spots in mind? We'll pick from your own list.",
  icon: Icons.checklist_rounded,
);

/// How a room works: a dot beside each step's title on a line that deepens
/// from mint to dark green, ending at a place setting beside the last step's
/// description.
class RoomSteps extends StatelessWidget {
  const RoomSteps({super.key});

  static const steps = [
    ('Start a room', 'Invite friends with a code, link or QR code.'),
    ('Everyone swipes', 'Yes or no on nearby spots, each on your own phone.'),
    ('See where to eat', 'The winner, a backup and directions.'),
  ];

  static const _gutter = 32.0;
  static const _dot = 12.0;
  static const _end = 26.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The title's first line, so each dot sits level with it at any text size.
    final painter = TextPainter(
      text: TextSpan(text: 'A', style: _StepText.titleStyle(theme)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
    )..layout();
    final titleLine = painter.height;
    painter.dispose();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (title, text)) in steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _gutter,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned(
                        top: i == 0 ? titleLine / 2 : 0,
                        bottom: i == steps.length - 1 ? _end / 2 : 0,
                        width: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [_railGreens[i], _railGreens[i + 1]],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: (titleLine - _dot) / 2,
                        child: Container(
                          width: _dot,
                          height: _dot,
                          decoration: BoxDecoration(
                            color: _railGreens[i],
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                      if (i == steps.length - 1)
                        Positioned(
                          bottom: 0,
                          child: Container(
                            width: _end,
                            height: _end,
                            decoration: BoxDecoration(
                              color: _railGreens.last,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.restaurant,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i == steps.length - 1 ? 0 : 12,
                    ),
                    child: ConstrainedBox(
                      // Room for the dot and the place setting beneath it.
                      constraints: BoxConstraints(
                        minHeight:
                            i == steps.length - 1
                                ? (titleLine + _dot) / 2 + 4 + _end
                                : 0,
                      ),
                      child: _StepText(title: title, text: text, theme: theme),
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

class _StepText extends StatelessWidget {
  const _StepText({
    required this.title,
    required this.text,
    required this.theme,
  });

  final String title;
  final String text;
  final ThemeData theme;

  static TextStyle titleStyle(ThemeData theme) => theme.textTheme.titleMedium!
      .copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF1F2A24));

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: titleStyle(theme)),
      const SizedBox(height: 2),
      Text(
        text,
        style: theme.textTheme.bodyMedium!.copyWith(
          color: const Color(0xFF4A5A52),
          height: 1.35,
        ),
      ),
    ],
  );
}

/// A card for one of the other ways to decide, or a menu entry: a plain
/// green icon, the name and a line about it. With [onTap] the whole card
/// opens something and shows an arrow.
class StepCard extends StatelessWidget {
  const StepCard({super.key, required this.step, this.onTap});

  final HomeStep step;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2EA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(step.icon, size: 19, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StepText(title: step.title, text: step.text, theme: theme),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
              child: const Icon(
                Icons.arrow_forward,
                size: 18,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFCFE6DB)),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          onTap == null
              ? content
              : Semantics(
                button: true,
                child: InkWell(onTap: onTap, child: content),
              ),
    );
  }
}
