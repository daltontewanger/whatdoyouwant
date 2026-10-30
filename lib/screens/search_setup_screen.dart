import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cuisines.dart';
import '../services/search_defaults.dart';

/// One line describing a search, such as "Within 5 mi · 10 options", led by
/// the ZIP code when the search starts from one.
String searchSummary(
  SearchPreferences search, {
  bool withDeckSize = true,
  String? zip,
}) =>
    '${zip == null ? '' : 'Near $zip · '}'
    'Within ${search.radius} ${search.unit.label}'
    '${withDeckSize ? ' · ${search.deckSize} options' : ''}';

/// What the settings screen hands back: the saved choices, and the ZIP code
/// for this session (null to search where the device is).
typedef SearchSetup = ({SearchPreferences search, String? zip});

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
  const SearchSetupScreen({
    super.key,
    required this.initial,
    this.initialZip,
    this.choosesDeckSize = true,
  });

  final SearchPreferences initial;
  final String? initialZip;

  /// Quick Pick shows one card at a time, so it has no number of options.
  final bool choosesDeckSize;

  @override
  State<SearchSetupScreen> createState() => _SearchSetupScreenState();
}

class _SearchSetupScreenState extends State<SearchSetupScreen> {
  late SearchPreferences _search = widget.initial;
  late bool _byZip = widget.initialZip != null;
  late final _zip = TextEditingController(text: widget.initialZip);
  bool _zipChecked = false;

  @override
  void dispose() {
    _zip.dispose();
    super.dispose();
  }

  void _apply() {
    final zip = _zip.text.trim();
    if (_byZip && !isZipCode(zip)) {
      setState(() => _zipChecked = true);
      return;
    }
    Navigator.pop<SearchSetup>(context, (
      search: _search,
      zip: _byZip ? zip : null,
    ));
  }

  Widget _where(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        theme,
        'Where to search',
        hint:
            _byZip
                ? 'Searches around the middle of that ZIP code. US only.'
                : 'Your location is asked for when the search starts.',
      ),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            icon: Icon(Icons.my_location),
            label: Text('My location'),
          ),
          ButtonSegment(
            value: true,
            icon: Icon(Icons.pin_drop_outlined),
            label: Text('ZIP code'),
          ),
        ],
        selected: {_byZip},
        onSelectionChanged: (value) => setState(() => _byZip = value.single),
      ),
      if (_byZip) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _zip,
          autofocus: widget.initialZip == null,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          decoration: InputDecoration(
            labelText: 'ZIP code',
            border: const OutlineInputBorder(),
            helperText: 'Not saved. Forgotten when you close the app.',
            errorText:
                _zipChecked && !isZipCode(_zip.text.trim())
                    ? 'Enter a 5-digit ZIP code.'
                    : null,
          ),
          onChanged: (_) {
            if (_zipChecked) setState(() {});
          },
          onSubmitted: (_) => _apply(),
        ),
      ],
    ],
  );

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

  Widget _cuisineChips(ThemeData theme, {required bool include}) {
    final chosen =
        include ? _search.includedCuisineIds : _search.excludedCuisineIds;
    final other =
        include ? _search.excludedCuisineIds : _search.includedCuisineIds;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final cuisine in cuisines)
          if (other.contains(cuisine.id))
            // Already chosen in the other list. Greyed out so that choice is
            // easy to see, but still tappable to move it here.
            FilterChip(
              label: Text(cuisine.label),
              tooltip: include ? 'Left out below' : 'Preferred above',
              selected: false,
              labelStyle: TextStyle(
                color: muted,
                decoration: TextDecoration.lineThrough,
                decorationColor: muted,
              ),
              side: BorderSide(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
              ),
              backgroundColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.06,
              ),
              onSelected: (_) => _toggleCuisine(cuisine.id, include: include),
            )
          else
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
                _where(theme),
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
                if (widget.choosesDeckSize) ...[
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
                                () =>
                                    _search = _search.copyWith(deckSize: size),
                              ),
                        ),
                    ],
                  ),
                ],
                _heading(
                  theme,
                  'Cuisines to prefer',
                  hint:
                      'Shown first when there are enough nearby. Leave empty for anything.',
                ),
                _cuisineChips(theme, include: true),
                _heading(
                  theme,
                  'Cuisines to leave out',
                  hint:
                      'Left out when the listing says so. Labels come from listings and are not a guide to ingredients or allergens.',
                ),
                _cuisineChips(theme, include: false),
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
                  onPressed: _apply,
                  child: const Text('Use these settings'),
                ),
                TextButton(
                  // Quick Pick leaves the room's number of options as it was.
                  onPressed:
                      () => setState(() {
                        _byZip = false;
                        _search =
                            widget.choosesDeckSize
                                ? const SearchPreferences()
                                : const SearchPreferences().copyWith(
                                  deckSize: _search.deckSize,
                                );
                      }),
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
