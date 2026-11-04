import 'package:flutter/material.dart';

/// A standard icon for a food label, matched on its words. Stand-ins until
/// the drawn set is ready; anything unmatched gets a plain plate.
IconData foodIcon(String label) {
  final words = label.toLowerCase();
  for (final (keys, icon) in _icons) {
    if (keys.any(words.contains)) return icon;
  }
  return Icons.restaurant;
}

// Checked in order, so the specific comes before the broad: sushi before
// Japanese, pizza before Italian.
const _icons = <(List<String>, IconData)>[
  (['pizza'], Icons.local_pizza),
  (['burger', 'sandwich', 'deli', 'sub', 'hoagie'], Icons.lunch_dining),
  (['sushi', 'seafood', 'fish', 'poke', 'oyster', 'crab'], Icons.set_meal),
  (
    ['noodle', 'ramen', 'pho', 'udon', 'vietnamese', 'japanese'],
    Icons.ramen_dining,
  ),
  (['coffee', 'cafe', 'café', 'tea'], Icons.local_cafe),
  (['ice cream', 'gelato', 'frozen', 'yogurt'], Icons.icecream),
  (['dessert', 'cake', 'sweet', 'candy', 'chocolate'], Icons.cake),
  (
    [
      'bakery',
      'pastr',
      'bread',
      'bagel',
      'donut',
      'doughnut',
      'french',
      'crepe',
    ],
    Icons.bakery_dining,
  ),
  (['breakfast', 'brunch', 'pancake', 'waffle'], Icons.breakfast_dining),
  (
    [
      'kebab',
      'gyro',
      'greek',
      'mediterranean',
      'middle eastern',
      'turkish',
      'lebanese',
      'falafel',
      'persian',
    ],
    Icons.kebab_dining,
  ),
  (['barbecue', 'bbq', 'grill', 'steak', 'smoke'], Icons.outdoor_grill),
  (
    [
      'chinese',
      'korean',
      'thai',
      'indian',
      'asian',
      'curry',
      'rice',
      'filipino',
      'dim sum',
      'hot pot',
    ],
    Icons.rice_bowl,
  ),
  (['italian', 'pasta'], Icons.dinner_dining),
  (['tapas', 'spanish'], Icons.tapas),
  (['soup'], Icons.soup_kitchen),
  (['fast food', 'hot dog', 'fries', 'chicken', 'wings'], Icons.fastfood),
  (['bar', 'pub', 'brew', 'wine', 'beer'], Icons.local_bar),
];

/// What a place serves, as chips with an icon and a word: the first [max],
/// and with [expandable] a "+ more" chip that shows the rest.
class FoodChips extends StatefulWidget {
  const FoodChips({
    super.key,
    required this.labels,
    this.max = 3,
    this.expandable = false,
    this.alignment = WrapAlignment.start,
    this.singleLine = false,
  });

  final List<String> labels;
  final int max;
  final bool expandable;
  final WrapAlignment alignment;

  /// One centred line, long words shortened, so a card keeps its height.
  final bool singleLine;

  @override
  State<FoodChips> createState() => _FoodChipsState();
}

class _FoodChipsState extends State<FoodChips> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    if (labels.isEmpty) return const SizedBox.shrink();
    final hidden = labels.length - widget.max;
    final shown = _open || hidden <= 0 ? labels : labels.take(widget.max);
    final theme = Theme.of(context);
    const ink = Color(0xFF1E5641);
    Widget chip(String label) => Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCFE6DB)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(foodIcon(label), size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (widget.singleLine) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (i, label) in shown.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Flexible(child: chip(label)),
          ],
        ],
      );
    }
    return Wrap(
      alignment: widget.alignment,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in shown) chip(label),
        if (widget.expandable && hidden > 0)
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _open = !_open),
              child: Container(
                constraints: const BoxConstraints(minHeight: 28),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.primary),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _open ? 'Show less' : '+$hidden more',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// What the listing says about vegetarian, vegan, halal or kosher food,
/// worded as the listing's claim, never ours.
class DietaryNote extends StatelessWidget {
  const DietaryNote({super.key, required this.dietary});

  final List<String> dietary;

  static const _known = ['vegetarian', 'vegan', 'halal', 'kosher'];

  static String? textFor(List<String> dietary) {
    final listed = _known.where(dietary.contains).toList();
    if (listed.isEmpty) return null;
    final names =
        listed.length == 1
            ? listed.single
            : '${listed.take(listed.length - 1).join(', ')} and ${listed.last}';
    return 'The listing mentions $names options. We aren\'t connected to '
        'this place, so check with them if it matters to you.';
  }

  @override
  Widget build(BuildContext context) {
    final text = textFor(dietary);
    if (text == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.eco_outlined, size: 16, color: Color(0xFF4A5A52)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(color: const Color(0xFF4A5A52)),
          ),
        ),
      ],
    );
  }
}
