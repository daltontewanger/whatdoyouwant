import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/own_spot.dart';
import '../services/own_list.dart';
import '../services/place_links.dart';
import '../services/room_backend.dart';
import 'place_card.dart';
import '../themes/main_theme.dart';

/// We'll Decide What We Want: the person's own list of spots, and a pick
/// from it. Everything here runs on the device; it never searches.
class OwnListScreen extends StatefulWidget {
  const OwnListScreen({super.key, this.random, this.onStartRoom});

  /// Decides the order picks come in; fixed in tests.
  final Random? random;

  /// Starts a room from the chosen spots, where rooms can be made.
  final Future<void> Function(List<OwnSpot> spots)? onStartRoom;

  @override
  State<OwnListScreen> createState() => _OwnListScreenState();
}

class _OwnListScreenState extends State<OwnListScreen> {
  late final Random _random = widget.random ?? Random();
  OwnListStore? _store;

  // Picks come from a shuffled order, so every spot shows once before any
  // shows again.
  List<OwnSpot> _order = [];
  int _position = 0;
  OwnSpot? _pick;
  bool _chosen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = RoomBackendScope.of(context).ownList;
    if (store == _store) return;
    _store?.removeListener(_changed);
    _store = store?..addListener(_changed);
    store?.load().catchError((_) => store.spots);
  }

  @override
  void dispose() {
    _store?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<OwnSpot> get _spots => _store?.spots ?? const [];

  Future<void> _save(List<OwnSpot> next) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _store?.save(next);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "Saved on this device. It'll reach your account when you're back online.",
          ),
        ),
      );
    }
  }

  Future<void> _edit([OwnSpot? spot]) async {
    final result = await showDialog<_SpotEdit>(
      context: context,
      builder: (_) => _SpotDialog(spot: spot),
    );
    if (result == null || !mounted) return;
    final spots = [..._spots];
    switch (result) {
      case _Delete():
        spots.removeWhere((s) => s.id == spot!.id);
      case _Saved(:final edited):
        final at = spots.indexWhere((s) => s.id == edited.id);
        if (at < 0) {
          spots.add(edited);
        } else {
          spots[at] = edited;
        }
    }
    await _save(spots);
  }

  void _pickOne() {
    final spots = _spots;
    if (spots.length < 2) return;
    setState(() {
      _order = [...spots]..shuffle(_random);
      _position = 0;
      _pick = _order.first;
      _chosen = false;
    });
  }

  void _another() {
    setState(() {
      _position++;
      if (_position >= _order.length) {
        final last = _pick;
        _order = [..._spots]..shuffle(_random);
        // A fresh round never starts with the spot just shown.
        if (_order.length > 1 && _order.first.id == last?.id) {
          _order.add(_order.removeAt(0));
        }
        _position = 0;
      }
      _pick = _order[_position];
    });
  }

  /// The host picks which spots everyone swipes on; all of them to start.
  Future<void> _chooseForRoom(
    Future<void> Function(List<OwnSpot>) start,
  ) async {
    final spots = _spots;
    final chosen = await showDialog<List<OwnSpot>>(
      context: context,
      builder: (context) {
        final picked = {for (final spot in spots) spot.id};
        return StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: const Text('Which spots?'),
                content: SizedBox(
                  width: 360,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      const Text(
                        "Everyone in the room swipes on these. Doesn't use a live search.",
                      ),
                      const SizedBox(height: 8),
                      for (final spot in spots)
                        CheckboxListTile(
                          value: picked.contains(spot.id),
                          title: Text(spot.name),
                          contentPadding: EdgeInsets.zero,
                          onChanged:
                              (on) => setDialogState(
                                () =>
                                    on == true
                                        ? picked.add(spot.id)
                                        : picked.remove(spot.id),
                              ),
                        ),
                      if (picked.length < 2)
                        Text(
                          'Pick at least 2.',
                          style: TextStyle(color: Colors.red[800]),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed:
                        picked.length < 2
                            ? null
                            : () => Navigator.pop(context, [
                              for (final spot in spots)
                                if (picked.contains(spot.id)) spot,
                            ]),
                    child: const Text('Create Room'),
                  ),
                ],
              ),
        );
      },
    );
    if (chosen != null && mounted) await start(chosen);
  }

  Widget _heading(ThemeData theme) => Column(
    children: [
      Text(
        "We'll Decide What We Want",
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall!.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Your own spots. No search used, and it works for anyone.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          color: Colors.grey[800],
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  Widget _list(ThemeData theme) {
    final store = _store;
    final spots = _spots;
    final full = spots.length >= OwnSpot.maxSpots;
    final left = store?.leftOver ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(theme),
        const SizedBox(height: 18),
        if (left.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1C9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  '${left.length} ${left.length == 1 ? 'spot' : 'spots'} '
                  "from this device didn't fit in your account's list of "
                  '${OwnSpot.maxSpots}. Remove some, then bring them over.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF5A4300)),
                ),
                TextButton(
                  onPressed: full ? null : () => store?.bringOverLeftOver(),
                  child: const Text('Bring them over'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final spot in spots) ...[
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFCFE6DB)),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              title: Text(
                spot.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle:
                  spot.address.isEmpty && spot.note.isEmpty
                      ? null
                      : Text(
                        [
                          spot.address,
                          spot.note,
                        ].where((part) => part.isNotEmpty).join(' · '),
                      ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(spot),
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: Text(full ? 'Your list is full' : 'Add a spot'),
          onPressed: full ? null : _edit,
        ),
        const SizedBox(height: 8),
        Text(
          '${spots.length} of ${OwnSpot.maxSpots} · '
          '${store?.synced == true ? 'saved to your account' : 'saved on this device'}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton(
            onPressed: spots.length < 2 ? null : _pickOne,
            style: ElevatedButton.styleFrom(minimumSize: const Size(220, 46)),
            child: const Text(
              'Pick one for me',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
        if (widget.onStartRoom case final start?) ...[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: spots.length < 2 ? null : () => _chooseForRoom(start),
              style: OutlinedButton.styleFrom(minimumSize: const Size(220, 46)),
              child: const Text('Start a room with these'),
            ),
          ),
        ],
        if (spots.length < 2) ...[
          const SizedBox(height: 10),
          Text(
            'Add at least 2 spots to pick from.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _revealed(ThemeData theme, OwnSpot pick) {
    final restaurant = pick.toRestaurant();
    return Column(
      children: [
        Text(
          _chosen ? "You're going to:" : 'How about:',
          style: theme.textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 14),
        PlaceCard(restaurant: restaurant),
        const SizedBox(height: 20),
        if (_chosen)
          PlaceActions(links: placeLinksFor(restaurant))
        else ...[
          ElevatedButton(
            onPressed: () => setState(() => _chosen = true),
            style: ElevatedButton.styleFrom(minimumSize: const Size(220, 46)),
            child: const Text("Let's go here", style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _another,
            style: OutlinedButton.styleFrom(minimumSize: const Size(220, 46)),
            child: const Text('Not feeling it'),
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          icon: const Icon(Icons.list),
          label: const Text('Back to my list'),
          onPressed: () => setState(() => _pick = null),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pick = _pick;
    return PopScope(
      canPop: pick == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _pick = null);
      },
      child: Scaffold(
        backgroundColor: screenBackground,
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
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.black54,
                                    size: 28,
                                  ),
                                  tooltip: 'Back',
                                  onPressed: () => Navigator.maybePop(context),
                                ),
                                const Spacer(),
                                if (pick != null)
                                  PlaceShareButtons(
                                    restaurant: pick.toRestaurant(),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            pick == null
                                ? _list(theme)
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

sealed class _SpotEdit {
  const _SpotEdit();
}

class _Saved extends _SpotEdit {
  const _Saved(this.edited);
  final OwnSpot edited;
}

class _Delete extends _SpotEdit {
  const _Delete();
}

class _SpotDialog extends StatefulWidget {
  const _SpotDialog({this.spot});

  final OwnSpot? spot;

  @override
  State<_SpotDialog> createState() => _SpotDialogState();
}

class _SpotDialogState extends State<_SpotDialog> {
  late final _name = TextEditingController(text: widget.spot?.name);
  late final _address = TextEditingController(text: widget.spot?.address);
  late final _note = TextEditingController(text: widget.spot?.note);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    final spot = widget.spot;
    final edited =
        spot == null
            ? OwnSpot(
              id: const Uuid().v4(),
              name: name,
              address: _address.text.trim(),
              note: _note.text.trim(),
            )
            : spot.copyWith(
              name: name,
              address: _address.text.trim(),
              note: _note.text.trim(),
            );
    Navigator.pop<_SpotEdit>(context, _Saved(edited));
  }

  TextField _field(
    TextEditingController controller,
    String label,
    int max, {
    String? hint,
    String? error,
    bool autofocus = false,
  }) => TextField(
    controller: controller,
    autofocus: autofocus,
    maxLength: max,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
    ),
    onChanged: error == null ? null : (_) => setState(() => _error = null),
    onSubmitted: (_) => _done(),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.spot == null ? 'Add a spot' : 'Edit spot'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(
            _name,
            'Name',
            OwnSpot.maxName,
            hint: "Tony's Pizza",
            error: _error,
            autofocus: true,
          ),
          _field(
            _address,
            'Address (optional)',
            OwnSpot.maxAddress,
            hint: '100 Main St',
          ),
          _field(_note, 'Note (optional)', OwnSpot.maxNote, hint: 'Get the #4'),
        ],
      ),
    ),
    actions: [
      if (widget.spot != null)
        TextButton(
          onPressed: () => Navigator.pop<_SpotEdit>(context, const _Delete()),
          style: TextButton.styleFrom(foregroundColor: Colors.red[800]),
          child: const Text('Remove'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _done, child: const Text('Save')),
    ],
  );
}
