import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/link.dart';

import '../models/restaurant.dart';
import '../services/place_links.dart';
import '../services/room_backend.dart';
import '../services/search_defaults.dart';

/// A chosen restaurant as the results screens show it: name, address and
/// distance in the person's own unit, with an optional note after the
/// distance and anything else (usually [PlaceActions]) underneath.
class PlaceCard extends StatelessWidget {
  const PlaceCard({
    super.key,
    required this.restaurant,
    this.note,
    this.child,
    this.onClose,
    this.closeTooltip = 'Close',
  });

  final Restaurant restaurant;
  final String? note;
  final Widget? child;

  /// Shows a close button in the corner when set.
  final VoidCallback? onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distance = distanceText(
      restaurant.distance,
      RoomBackendScope.distanceUnitOf(context),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(right: onClose == null ? 0 : 36),
                child: Text(
                  restaurant.name,
                  style: theme.textTheme.headlineSmall!.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ),
              if (restaurant.address.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(restaurant.address, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: 4),
              Text(
                note == null
                    ? 'Distance: $distance'
                    : 'Distance: $distance · $note',
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: Colors.black54,
                ),
              ),
              if (child case final child?) ...[
                const SizedBox(height: 14),
                child,
              ],
            ],
          ),
          if (onClose != null)
            Positioned(
              top: -8,
              right: -8,
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: closeTooltip,
                onPressed: onClose,
              ),
            ),
        ],
      ),
    );
  }
}

/// What Copy and Share send: the place, and a HERE WeGo map link when the
/// listing has a position.
String placeShareText(Restaurant restaurant) {
  final where = [
    restaurant.name,
    restaurant.address,
  ].where((part) => part.trim().isNotEmpty).join(', ');
  final map = placeLinksFor(restaurant).map;
  return "We're going to $where. Picked with What Do You Want?!"
      "${map == null ? '' : '\n$map'}";
}

Future<void> copyPlace(BuildContext context, Restaurant restaurant) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var copied = true;
  try {
    await Clipboard.setData(ClipboardData(text: placeShareText(restaurant)));
  } catch (_) {
    // Browsers can refuse clipboard access.
    copied = false;
  }
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(copied ? 'Copied' : 'Could not copy. Try again.')),
    );
}

/// Opens the phone's share menu. Browsers without one copy instead.
Future<void> sharePlace(BuildContext context, Restaurant restaurant) async {
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: placeShareText(restaurant),
        mailToFallbackEnabled: false,
      ),
    );
  } catch (_) {
    if (context.mounted) await copyPlace(context, restaurant);
  }
}

/// Copy and Share for the place on screen.
class PlaceShareButtons extends StatelessWidget {
  const PlaceShareButtons({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        icon: const Icon(Icons.copy_rounded),
        tooltip: 'Copy',
        color: Colors.black54,
        onPressed: () => copyPlace(context, restaurant),
      ),
      IconButton(
        icon: const Icon(Icons.share),
        tooltip: 'Share',
        color: Colors.black54,
        onPressed: () => sharePlace(context, restaurant),
      ),
    ],
  );
}

/// Credit for the listings, shown wherever place details are.
class PlaceCredit extends StatelessWidget {
  const PlaceCredit({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Place details from HERE',
    textAlign: TextAlign.center,
    style: Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: Colors.black54),
  );
}

/// Map, directions, website and phone, where the listing has them.
///
/// Each link is a real link, so on the web the browser opens it from the
/// tap itself: pages are not caught by pop-up blockers, and a phone number
/// opens in place, which is what makes a phone browser offer to call. The
/// apps hand everything to the phone instead.
class PlaceActions extends StatelessWidget {
  const PlaceActions({
    super.key,
    required this.links,
    this.alignment = WrapAlignment.center,
  });

  final PlaceLinks links;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return const Text('This listing has no map or contact details.');
    }
    final directions = links.directions;
    return Wrap(
      alignment: alignment,
      spacing: 10,
      runSpacing: 10,
      children: [
        if (links.map case final map?)
          _link(map, (follow) => _button(Icons.map_outlined, 'Map', follow)),
        if (directions != null)
          _button(
            Icons.directions,
            'Directions',
            () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (context) => _DirectionsChoice(links: links),
            ),
          ),
        if (links.website case final website?)
          _link(
            website,
            (follow) => _button(Icons.language, 'Website', follow),
          ),
        if (links.phone case final phone?)
          _link(phone, (follow) => _button(Icons.call, 'Call', follow)),
      ],
    );
  }

  static Widget _button(IconData icon, String label, VoidCallback? onPressed) =>
      OutlinedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
      );
}

Widget _link(Uri url, Widget Function(VoidCallback? follow) builder) => Link(
  uri: url,
  target: kIsWeb && url.isScheme('tel') ? LinkTarget.self : LinkTarget.blank,
  builder: (context, followLink) => builder(followLink),
);

/// HERE WeGo first, then the maps apps the device is likely to have.
class _DirectionsChoice extends StatelessWidget {
  const _DirectionsChoice({required this.links});

  final PlaceLinks links;

  @override
  Widget build(BuildContext context) {
    final platform = defaultTargetPlatform;
    final apple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final choices = [
      (links.directions, 'HERE WeGo', 'Default'),
      (links.googleDirections, 'Google Maps', null),
      if (apple) (links.appleDirections, 'Apple Maps', null),
      if (platform == TargetPlatform.android)
        (links.deviceMaps, "Your phone's maps app", null),
    ];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Get directions with',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final (url, label, note) in choices)
            if (url != null)
              _link(
                url,
                (follow) => ListTile(
                  leading: const Icon(Icons.directions),
                  title: Text(label),
                  subtitle: note == null ? null : Text(note),
                  onTap:
                      follow == null
                          ? null
                          : () {
                            follow();
                            Navigator.pop(context);
                          },
                ),
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
