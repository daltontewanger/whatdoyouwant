import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

import '../models/restaurant.dart';
import '../services/place_links.dart';
import '../services/room_backend.dart';
import '../services/search_defaults.dart';

/// A chosen restaurant as the results screens show it: name, address and
/// distance in the person's own unit.
class PlaceCard extends StatelessWidget {
  const PlaceCard({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            restaurant.name,
            style: theme.textTheme.headlineSmall!.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          if (restaurant.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(restaurant.address, style: theme.textTheme.bodyLarge),
          ],
          const SizedBox(height: 4),
          Text(
            'Distance: ${distanceText(restaurant.distance, RoomBackendScope.distanceUnitOf(context))}',
            style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

/// Map, directions, website and phone, where the listing has them.
///
/// Each button is a real link, so on the web the browser opens it from the
/// tap itself: pages are not caught by pop-up blockers, and a phone number
/// opens in place, which is what makes a phone browser offer to call. The
/// apps hand everything to the phone instead.
class PlaceActions extends StatelessWidget {
  const PlaceActions({super.key, required this.links});

  final PlaceLinks links;

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
            Link(
              uri: url,
              target:
                  kIsWeb && url.isScheme('tel')
                      ? LinkTarget.self
                      : LinkTarget.blank,
              builder:
                  (context, followLink) => OutlinedButton.icon(
                    icon: Icon(icon),
                    label: Text(label),
                    onPressed: followLink,
                  ),
            ),
      ],
    );
  }
}
