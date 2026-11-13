import 'package:flutter/material.dart';

import '../services/live_search.dart';
import '../services/room_backend.dart';
import '../themes/main_theme.dart';

/// "Live searches: 7 of 10 left" in the account card, with a dot for each
/// search, so someone can see what they have without starting a room. Asks
/// again each time the Account tab comes into view, so it stays current after
/// a search.
class LiveSearchesRow extends StatefulWidget {
  const LiveSearchesRow({super.key});

  @override
  State<LiveSearchesRow> createState() => _LiveSearchesRowState();
}

class _LiveSearchesRowState extends State<LiveSearchesRow> {
  LiveSearchAllowance? _allowance;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The Account tab stays alive behind Home; it counts as shown when its
    // animations are on.
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown && !_shown) _load();
    _shown = shown;
  }

  Future<void> _load() async {
    final backend = RoomBackendScope.maybeOf(context)?.backend;
    if (backend == null) return;
    try {
      final allowance = await backend.liveSearchAllowance();
      if (mounted) setState(() => _allowance = allowance);
    } catch (_) {
      // Shown next time the tab opens.
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowance = _allowance;
    if (allowance == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cap = allowance.weeklyCap;
    final left = allowance.remaining.clamp(0, cap);
    final when = resetTimeText(allowance.resetsAt);
    final summary =
        allowance.paused
            ? 'Paused for now'
            : allowance.newAccount
            ? '$left of $cap left today'
            : '$left of $cap left';
    final note =
        allowance.paused
            ? 'Live restaurant search is paused for everyone. Try again later.'
            : left == 0
            ? 'More arrive $when.'
            : allowance.newAccount
            ? 'New accounts start with $cap. More arrive $when.'
            : 'More arrive $when.';

    return Semantics(
      container: true,
      label: 'Live searches: $summary. $note',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Text('Live searches')),
              Text(
                summary,
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (cap > 0 && cap <= 30) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (var i = 0; i < cap; i++)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          i < left && !allowance.paused
                              ? primaryGreen
                              : primaryGreen.withValues(alpha: 0.15),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            note,
            style: theme.textTheme.bodySmall!.copyWith(color: inkSoft),
          ),
        ],
      ),
    );
  }
}
