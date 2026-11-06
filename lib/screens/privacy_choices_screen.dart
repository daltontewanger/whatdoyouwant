import 'package:flutter/material.dart';

import '../services/usage_counts.dart';
import 'help_links.dart';

/// The person's privacy settings on this device; for now, whether the app
/// sends anonymous usage counts.
class PrivacyChoicesScreen extends StatelessWidget {
  const PrivacyChoicesScreen({super.key, required this.counts});

  final UsageCounts counts;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy choices')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ListenableBuilder(
                listenable: counts,
                builder:
                    (context, _) => SwitchListTile(
                      title: const Text('Share anonymous usage counts'),
                      subtitle: const Text(
                        'Adds to daily totals like "directions opened" so we '
                        'can improve the app. Never who you are or where.',
                      ),
                      value: counts.enabled,
                      onChanged: counts.setEnabled,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => openSitePage(context, '/privacy'),
              child: const Text('Read the privacy policy'),
            ),
          ],
        ),
      ),
    );
  }
}
