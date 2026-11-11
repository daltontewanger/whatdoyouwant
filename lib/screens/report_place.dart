import 'dart:async';

import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../models/saved_place.dart';
import '../services/room_backend.dart';
import '../themes/main_theme.dart';
import 'place_marks.dart';

/// A quiet link under a result card for saying the place is closed or its
/// details are wrong. Only places from a search can be reported.
class ReportPlaceLink extends StatelessWidget {
  const ReportPlaceLink({
    super.key,
    required this.restaurant,
    required this.from,
  });

  final Restaurant restaurant;
  final ReportedFrom from;

  @override
  Widget build(BuildContext context) {
    if (!SavedPlace.canSave(restaurant)) return const SizedBox.shrink();
    return Center(
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF4A5A52),
          minimumSize: const Size(48, 44),
        ),
        icon: const Icon(Icons.outlined_flag, size: 18),
        label: const Text('Closed or wrong info?'),
        onPressed: () => reportPlace(context, restaurant, from),
      ),
    );
  }
}

/// Asks what is wrong with [restaurant] and acts on the answer. A closed
/// place leaves this person's decks at once; the report itself only counts
/// from a verified account, and nobody in the room sees it.
Future<void> reportPlace(
  BuildContext context,
  Restaurant restaurant,
  ReportedFrom from,
) async {
  final problem = await showModalBottomSheet<PlaceProblem>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFFFFFAF0),
    isScrollControlled: true,
    builder: (_) => _ReportSheet(restaurant: restaurant),
  );
  if (problem == null || !context.mounted) return;
  final scope = RoomBackendScope.of(context);
  final places = scope.myPlaces;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final before = places?.places;
  if (problem == PlaceProblem.closed && places != null) {
    try {
      await places.addClosed(restaurant);
    } catch (_) {
      // An account's device copy keeps the change and sends it next time.
    }
  }
  // Guests' reports would be refused, so only accounts send them. Sending
  // can fail quietly: what the person sees does not depend on it.
  if (places?.synced ?? true) {
    unawaited(
      scope.backend.reportPlace(restaurant, problem, from).catchError((_) {}),
    );
  }
  if (problem == PlaceProblem.closed) {
    tell(
      messenger,
      "Thanks. ${restaurant.name} won't come up for you again.",
      undo:
          places == null || before == null
              ? null
              : () => places.restore(before).catchError((_) {}),
    );
  } else {
    tell(messenger, 'Thanks for letting us know.');
  }
}

class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = [
      (
        PlaceProblem.closed,
        "It's closed for good",
        "We'll stop showing it to you right away.",
      ),
      if (restaurant.website?.isNotEmpty ?? false)
        (PlaceProblem.website, 'The website is wrong', null),
      if (restaurant.phone?.isNotEmpty ?? false)
        (PlaceProblem.phone, 'The phone number is wrong', null),
      (PlaceProblem.location, "It's somewhere else on the map", null),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                "What's wrong with ${restaurant.name}?",
                style: theme.textTheme.titleLarge!.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your report stays private. Nobody in the room sees it.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: const Color(0xFF4A5A52),
              ),
            ),
            const SizedBox(height: 16),
            for (final (problem, title, note) in choices) ...[
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xFFCFE6DB)),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: note == null ? null : Text(note),
                  onTap: () => Navigator.pop(context, problem),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextButton(
              style: TextButton.styleFrom(foregroundColor: primaryGreen),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
