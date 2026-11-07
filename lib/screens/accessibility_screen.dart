import 'package:flutter/material.dart';

import '../services/accessibility.dart';

/// The person's accessibility choices, a page of its own off Account.
class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key, required this.settings});

  final AccessibilitySettings settings;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Accessibility features')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            TextSizeSection(settings: settings),
            const SizedBox(height: 16),
            AccessibilitySection(settings: settings),
            if (settings.web) ...[
              const SizedBox(height: 16),
              ScreenReaderSection(settings: settings),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Makes the app's text bigger than the device's own size.
class TextSizeSection extends StatelessWidget {
  const TextSizeSection({super.key, required this.settings});

  final AccessibilitySettings settings;

  static String percent(double size) => '${(size * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder:
          (context, _) => Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.text_fields),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Text size',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        percent(settings.textSize),
                        style: theme.textTheme.titleMedium!.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Makes the words in the app bigger, on top of the size '
                    'your device already uses.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Row(
                    children: [
                      const ExcludeSemantics(
                        child: Text('A', style: TextStyle(fontSize: 14)),
                      ),
                      Expanded(
                        child: Slider(
                          value: settings.textSize,
                          min: AccessibilitySettings.minTextSize,
                          max: AccessibilitySettings.maxTextSize,
                          divisions: 4,
                          label: percent(settings.textSize),
                          semanticFormatterCallback: percent,
                          onChanged: settings.setTextSize,
                        ),
                      ),
                      const ExcludeSemantics(
                        child: Text('A', style: TextStyle(fontSize: 26)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

/// Voting without the card timer. A screen reader or switch control turns
/// it on by itself.
class AccessibilitySection extends StatelessWidget {
  const AccessibilitySection({super.key, required this.settings});

  final AccessibilitySettings settings;

  @override
  Widget build(BuildContext context) {
    final automatic = assistiveTechOn(context);
    return ListenableBuilder(
      listenable: settings,
      builder:
          (context, _) => Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: const Icon(Icons.timer_off_outlined),
              title: const Text('No vote timer'),
              subtitle: Text(
                "${automatic ? 'On while your screen reader or switch control is in use. ' : ''}"
                'Vote at your own pace instead of 15 seconds a card. Rooms still '
                "finish 30 minutes after voting starts, and if you don't vote for "
                "3 minutes, the rest count as places you don't want.",
              ),
              value: automatic || settings.noTimer,
              onChanged: automatic ? null : settings.setNoTimer,
            ),
          ),
    );
  }
}

/// Turns on what screen readers read in the web app. Off unless asked for:
/// keeping it up to date makes the app slower for everyone else.
class ScreenReaderSection extends StatelessWidget {
  const ScreenReaderSection({super.key, required this.settings});

  final AccessibilitySettings settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder:
        (context, _) => Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            secondary: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Screen reader support'),
            subtitle: const Text(
              'Lets screen readers such as VoiceOver, TalkBack and NVDA read '
              "the app in this browser. Leave it off if you don't use one; "
              'it makes the app a little slower. Remembered on this device.',
            ),
            value: settings.screenReader,
            onChanged: settings.setScreenReader,
          ),
        ),
  );
}
