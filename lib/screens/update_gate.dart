import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/room_backend.dart';

/// The installed app's build number, or 0 where it cannot be read.
Future<int> appBuildNumber() async =>
    int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

/// Shows [child] unless the backend says this build is too old to use. A
/// failed check lets the person in: the check is a courtesy, not a control.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child, this.installedBuild});

  final Widget child;

  /// Overrides how the installed build number is found, for tests.
  final Future<int> Function()? installedBuild;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _updateRequired = false;
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    final backend = RoomBackendScope.of(context).backend;
    () async {
      try {
        final build = await (widget.installedBuild ?? appBuildNumber)();
        final required = await backend.updateRequired(build);
        if (mounted && required) setState(() => _updateRequired = true);
      } catch (_) {}
    }();
  }

  @override
  Widget build(BuildContext context) =>
      _updateRequired ? const UpdateRequiredScreen() : widget.child;
}

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.system_update,
                  size: 56,
                  color: theme.colorScheme.primary,
                  semanticLabel: 'Update available',
                ),
                const SizedBox(height: 16),
                Text(
                  'A newer version is ready',
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  kIsWeb
                      ? 'This version can no longer join rooms. Reload to get the latest one.'
                      : 'This version can no longer join rooms. Update the app from your app store to keep deciding together.',
                  textAlign: TextAlign.center,
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 20),
                  ElevatedButton(
                    // Reopening the app's own address loads the newest build.
                    onPressed:
                        () => launchUrl(Uri.base, webOnlyWindowName: '_self'),
                    child: const Text('Reload'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
