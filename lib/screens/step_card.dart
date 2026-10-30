import 'package:flutter/material.dart';

/// The logo's colors, as the public site uses them for its numbered steps:
/// each badge with a dark text of its own hue for contrast.
enum StepColor {
  yellow(Color(0xFFF7C948), Color(0xFF5A4300)),
  blue(Color(0xFF6FB7E9), Color(0xFF0C3A5C)),
  green(Color(0xFF65B292), Color(0xFF173404)),
  coral(Color(0xFFF59E84), Color(0xFF6A2A17)),
  lavender(Color(0xFFAFA9EC), Color(0xFF26215C)),
  mint(Color(0xFFE3F2EA), Color(0xFF1E5641));

  const StepColor(this.badge, this.ink);
  final Color badge;
  final Color ink;
}

class HomeStep {
  const HomeStep(this.number, this.title, this.text, this.color, {this.icon});

  final int number;
  final String title;
  final String text;
  final StepColor color;

  /// Shown in the badge in place of the number.
  final IconData? icon;
}

const quickPickStep = HomeStep(
  4,
  'Tell Me What I Want',
  'Still too much pressure swiping? We can help pick for you.',
  StepColor.coral,
);

const ownListStep = HomeStep(
  5,
  "We'll Decide What We Want",
  "Already have spots in mind? We'll pick from your own list.",
  StepColor.lavender,
);

/// A numbered card like the site's "how it works" steps. With [onTap] the
/// whole card opens something and shows an arrow.
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
              color: step.color.badge,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
                bottomRight: Radius.circular(10),
                bottomLeft: Radius.circular(3),
              ),
            ),
            child:
                step.icon == null
                    ? Text(
                      '${step.number}',
                      style: TextStyle(
                        color: step.color.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    )
                    : Icon(step.icon, size: 18, color: step.color.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1F2A24),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.text,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: const Color(0xFF4A5A52),
                    height: 1.35,
                  ),
                ),
              ],
            ),
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
