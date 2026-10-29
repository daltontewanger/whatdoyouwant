import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/restaurant.dart';
import '../services/live_search.dart';
import '../services/place_links.dart';
import '../services/room_backend.dart';
import '../services/search_defaults.dart';
import 'search_panel.dart';

/// What to tell someone whose Quick Pick could not start.
String quickPickErrorMessage(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Only verified accounts can use Quick Pick. Open Account to sign in or verify your email.';
  }
  return searchErrorMessage(error) ??
      'Could not load restaurants. Check your connection and try again.';
}

/// What to tell someone whose reroll did not go through.
String rerollErrorMessage(Object error) {
  if (callableReason(error) == 'no-rerolls') {
    return "That was the last pick from this search. Start a new search for more.";
  }
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'This pick has expired. Start a new search.';
  }
  return 'Could not get another pick. Check your connection and try again.';
}

/// One live search, shown one place at a time: take it, or ask for another
/// from the same search without using another.
class QuickPickScreen extends StatefulWidget {
  const QuickPickScreen({super.key});

  @override
  State<QuickPickScreen> createState() => _QuickPickScreenState();
}

class _QuickPickScreenState extends State<QuickPickScreen> with SearchStarter {
  QuickPick? _pick;
  bool _chosen = false;
  bool _busy = false;

  // Kept until a pick comes back, so retrying after a lost reply returns that
  // pick instead of spending another search.
  String? _requestId;

  @override
  String get startLabel => 'Pick for me';

  @override
  String get searchCostNote => 'A pick uses one; rerolls are free.';

  @override
  bool get choosesDeckSize => false;

  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    loadSearchSetup();
    if (backend.usesDeviceLocation) {
      unawaited(backend.prepareStart().catchError((_) {}));
    }
  }

  @override
  Future<void> editSearch() async {
    await super.editSearch();
    _requestId = null;
  }

  Future<void> _pickForMe() async {
    setState(() => _busy = true);
    try {
      if (backend.usesDeviceLocation && !await locationReady()) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      _requestId ??= const Uuid().v4();
      // At most six places ever show (one and five rerolls); ten leaves room
      // for the deck's variety rules.
      final pick = await backend.createQuickPick(
        requestId: _requestId!,
        search: search.copyWith(deckSize: 10),
      );
      _requestId = null;
      if (!mounted) return;
      setState(() {
        _pick = pick;
        _chosen = false;
        _busy = false;
      });
      unawaited(refreshAllowance());
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (showBlockedLocation(e)) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(quickPickErrorMessage(e))));
    }
  }

  Future<void> _reroll() async {
    final pick = _pick;
    if (pick == null) return;
    setState(() => _busy = true);
    try {
      final next = await backend.rerollQuickPick(pick);
      if (!mounted) return;
      setState(() {
        _pick = next;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(rerollErrorMessage(e))));
    }
  }

  void _newSearch() => setState(() {
    _pick = null;
    _chosen = false;
  });

  /// Leaving drops the pick, and picking again uses another search.
  Future<void> _confirmLeave() async {
    final navigator = Navigator.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Leave this pick?'),
            content: const Text(
              'Picking again will use another of your live searches.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave'),
              ),
            ],
          ),
    );
    if (leave == true && mounted) navigator.pop();
  }

  Widget _setup(ThemeData theme) => Column(
    children: [
      Text(
        'Quick Pick',
        style: theme.textTheme.headlineSmall!.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        "We'll pick one place near you. Not feeling it? Get another from the "
        'same search, up to 5 times, without using another search.'
        "${backend.usesFictionalRestaurants ? '\n\nThis build uses fictional test restaurants.' : ''}",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          color: Colors.grey[800],
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 20),
      searchPanel(theme, busy: _busy),
      const SizedBox(height: 20),
      _busy
          ? const CircularProgressIndicator()
          : ElevatedButton(
            onPressed: cannotSearch ? null : _pickForMe,
            style: ElevatedButton.styleFrom(minimumSize: const Size(170, 46)),
            child: const Text('Pick for me', style: TextStyle(fontSize: 16)),
          ),
    ],
  );

  Widget _revealed(ThemeData theme, QuickPick pick) {
    final restaurant = pick.restaurant;
    return Column(
      children: [
        Text(
          _chosen ? "You're going to" : 'How about',
          style: theme.textTheme.titleMedium!.copyWith(color: Colors.grey[800]),
        ),
        const SizedBox(height: 10),
        _PlaceCard(restaurant: restaurant),
        const SizedBox(height: 20),
        if (_chosen)
          _PlaceActions(links: placeLinksFor(restaurant))
        else if (_busy)
          const CircularProgressIndicator()
        else ...[
          ElevatedButton(
            onPressed: () => setState(() => _chosen = true),
            style: ElevatedButton.styleFrom(minimumSize: const Size(220, 46)),
            child: const Text("Let's go here", style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: pick.rerollsLeft > 0 ? _reroll : null,
            style: OutlinedButton.styleFrom(minimumSize: const Size(220, 46)),
            child: Text(
              pick.rerollsLeft > 0
                  ? 'Not feeling it (${pick.rerollsLeft} left)'
                  : 'No more from this search',
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (!_busy)
          TextButton.icon(
            icon: const Icon(Icons.search),
            label: const Text('New search'),
            onPressed: _newSearch,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pick = _pick;
    return PopScope(
      canPop: pick == null || _chosen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
        body: SafeArea(
          child: LayoutBuilder(
            builder:
                (context, constraints) => SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 420,
                        minHeight: constraints.maxHeight,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.10,
                              ),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.black54,
                                  size: 28,
                                ),
                                tooltip: 'Back',
                                onPressed: () => Navigator.maybePop(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            pick == null
                                ? _setup(theme)
                                : _revealed(theme, pick),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.primary, width: 3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            restaurant.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall!.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (restaurant.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(restaurant.address, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 8),
          Text(
            'Distance: ${distanceText(restaurant.distance, RoomBackendScope.distanceUnitOf(context))}',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}

/// Map, directions, website and phone, where the listing has them.
class _PlaceActions extends StatelessWidget {
  const _PlaceActions({required this.links});

  final PlaceLinks links;

  Future<void> _open(BuildContext context, Uri url) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (_) {}
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open that link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return const Text('This listing has no map or contact details.');
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (url, icon, label) in [
          (links.map, Icons.map_outlined, 'Map'),
          (links.directions, Icons.directions, 'Directions'),
          (links.website, Icons.language, 'Website'),
          (links.phone, Icons.call, 'Call'),
        ])
          if (url != null)
            OutlinedButton.icon(
              icon: Icon(icon),
              label: Text(label),
              onPressed: () => _open(context, url),
            ),
      ],
    );
  }
}
