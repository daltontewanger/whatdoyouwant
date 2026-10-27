import 'package:flutter/material.dart';

import '../models/cuisines.dart';
import '../services/search_defaults.dart';

/// One line describing a search, such as "Within 5 mi · 10 options".
String searchSummary(SearchPreferences search) =>
    'Within ${search.radius} ${search.unit.label} · ${search.deckSize} options';

/// The cuisine and open-now part of a search, or null for "anything".
String? preferenceSummary(SearchPreferences search) {
  final parts = [
    if (search.includedCuisineIds.isNotEmpty)
      'Prefer ${search.includedCuisineIds.map(cuisineLabel).join(', ')}',
    if (search.excludedCuisineIds.isNotEmpty)
      'No ${search.excludedCuisineIds.map(cuisineLabel).join(', ')}',
    if (search.openNowPreferred) 'Open now first',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Lets the host choose what the deck searches for. Returns the new choices,
/// or null when the host leaves without applying them.
class SearchSetupScreen extends StatefulWidget {
  const SearchSetupScreen({super.key, required this.initial});

  final SearchPreferences initial;

  @override
  State<SearchSetupScreen> createState() => _SearchSetupScreenState();
}

class _SearchSetupScreenState extends State<SearchSetupScreen> {
  late SearchPreferences _search = widget.initial;

  void _toggleCuisine(String id, {required bool include}) {
    final included = [..._search.includedCuisineIds];
    final excluded = [..._search.excludedCuisineIds];
    final list = include ? included : excluded;
    final other = include ? excluded : included;
    if (list.contains(id)) {
      list.remove(id);
    } else {
      if (list.length >= maxCuisinesPerList) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Choose up to $maxCuisinesPerList cuisines here.'),
            ),
          );
        return;
      }
      // A cuisine can be preferred or left out, not both.
      other.remove(id);
      list.add(id);
    }
    setState(
      () =>
          _search = _search.copyWith(
            includedCuisineIds: included,
            excludedCuisineIds: excluded,
          ),
    );
  }

  Widget _heading(ThemeData theme, String text, {String? hint}) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(text, style: theme.textTheme.titleMedium),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(hint, style: theme.textTheme.bodySmall),
          ),
      ],
    ),
  );

  Widget _cuisineChips({required bool include}) {
    final chosen =
        include ? _search.includedCuisineIds : _search.excludedCuisineIds;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final cuisine in cuisines)
          FilterChip(
            label: Text(cuisine.label),
            selected: chosen.contains(cuisine.id),
            onSelected: (_) => _toggleCuisine(cuisine.id, include: include),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = _search.unit.label;
    return Scaffold(
      appBar: AppBar(title: const Text('Search settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                _heading(theme, 'Distance'),
                SegmentedButton<DistanceUnit>(
                  segments: const [
                    ButtonSegment(value: DistanceUnit.mi, label: Text('Miles')),
                    ButtonSegment(
                      value: DistanceUnit.km,
                      label: Text('Kilometers'),
                    ),
                  ],
                  selected: {_search.unit},
                  onSelectionChanged:
                      (value) => setState(
                        () => _search = _search.copyWith(unit: value.single),
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final radius in SearchPreferences.radiusChoices)
                      ChoiceChip(
                        label: Text('$radius $unit'),
                        selected: _search.radius == radius,
                        onSelected:
                            (_) => setState(
                              () => _search = _search.copyWith(radius: radius),
                            ),
                      ),
                  ],
                ),
                _heading(theme, 'Number of options'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final size in SearchPreferences.deckSizes)
                      ChoiceChip(
                        label: Text('$size'),
                        selected: _search.deckSize == size,
                        onSelected:
                            (_) => setState(
                              () => _search = _search.copyWith(deckSize: size),
                            ),
                      ),
                  ],
                ),
                _heading(
                  theme,
                  'Cuisines to prefer',
                  hint:
                      'Shown first when there are enough nearby. Leave empty for anything.',
                ),
                _cuisineChips(include: true),
                _heading(
                  theme,
                  'Cuisines to leave out',
                  hint:
                      'Left out when the listing says so. Labels come from listings and are not a guide to ingredients or allergens.',
                ),
                _cuisineChips(include: false),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show places open now first'),
                  subtitle: const Text(
                    'Opening hours come from listings and can change.',
                  ),
                  value: _search.openNowPreferred,
                  onChanged:
                      (value) => setState(
                        () =>
                            _search = _search.copyWith(openNowPreferred: value),
                      ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _search),
                  child: const Text('Use these settings'),
                ),
                TextButton(
                  onPressed:
                      () => setState(() => _search = const SearchPreferences()),
                  child: const Text('Reset to the standard settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
