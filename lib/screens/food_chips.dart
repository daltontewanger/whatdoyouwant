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
/// and with [expandable] a "+ more" chip that shows the rest. With
/// [maxRows] the chips are centred and kept to that many rows: a chip that
/// would need another row is left out rather than shortened, so the ones
/// shown stay readable.
class FoodChips extends StatefulWidget {
  const FoodChips({
    super.key,
    required this.labels,
    this.max = 3,
    this.expandable = false,
    this.alignment = WrapAlignment.start,
    this.maxRows,
  });

  final List<String> labels;
  final int max;
  final bool expandable;
  final WrapAlignment alignment;
  final int? maxRows;

  @override
  State<FoodChips> createState() => _FoodChipsState();
}

/// The labels, in order, that fit in [rows] rows of [width] when laid out
/// the way a [Wrap] does. One that would need another row is skipped, so a
/// shorter one after it can still take the space. The first label always
/// shows, shortened if it is wider than a whole row.
List<String> fitInRows(
  List<String> labels, {
  required double width,
  required int rows,
  required double Function(String) widthOf,
}) {
  final fitting = <String>[];
  var row = 0;
  var used = 0.0;
  for (final label in labels) {
    final need = widthOf(label).clamp(0.0, width);
    if (fitting.isEmpty) {
      fitting.add(label);
      used = need;
    } else if (used + _chipSpacing + need <= width) {
      fitting.add(label);
      used += _chipSpacing + need;
    } else if (row + 1 < rows) {
      fitting.add(label);
      row++;
      used = need;
    }
  }
  return fitting;
}

double _chipWidth(BuildContext context, String label, TextStyle style) {
  final text = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  // Padding 8 + 10, border 1 + 1, icon 16 and its gap 4.
  return text.width + 40;
}

const _chipSpacing = 6.0;

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
    final style = theme.textTheme.bodySmall!.copyWith(
      color: ink,
      fontWeight: FontWeight.w700,
    );
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
            child: Text(label, overflow: TextOverflow.ellipsis, style: style),
          ),
        ],
      ),
    );
    if (widget.maxRows case final rows?) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final fitting = fitInRows(
            labels.take(widget.max).toList(),
            width: constraints.maxWidth,
            rows: rows,
            widthOf: (label) => _chipWidth(context, label, style),
          );
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: _chipSpacing,
            runSpacing: _chipSpacing,
            children: [
              for (final label in fitting)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: chip(label),
                ),
            ],
          );
        },
      );
    }
    return Wrap(
      alignment: widget.alignment,
      spacing: _chipSpacing,
      runSpacing: _chipSpacing,
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
