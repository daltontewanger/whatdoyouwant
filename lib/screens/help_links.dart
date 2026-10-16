import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/room_backend.dart';

/// The public site's help and legal pages as a list. Installed apps can only
/// reach them through here; on the web the site's home is listed too.
class HelpList extends StatelessWidget {
  const HelpList({super.key});

  static const pages = [
    (Icons.support_agent, 'Support', '/support'),
    (Icons.privacy_tip_outlined, 'Privacy policy', '/privacy'),
    (Icons.description_outlined, 'Terms of use', '/terms'),
    (Icons.cookie_outlined, 'Cookie policy', '/cookies'),
    (Icons.accessibility_new, 'Accessibility', '/accessibility'),
  ];

  @override
  Widget build(BuildContext context) {
    if (RoomBackendScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }
    final color = Theme.of(context).colorScheme.primary;
    Widget row(IconData icon, String label, VoidCallback onTap) => ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (kIsWeb)
            row(
              Icons.language,
              'Website home',
              () => openSitePage(context, '/', leaveApp: true),
            ),
          for (final (icon, label, path) in pages)
            row(icon, label, () => openSitePage(context, path)),
        ],
      ),
    );
  }
}

/// Opens a page of the public site. On the web, help pages open in a new tab
/// so a room in progress stays open; [leaveApp] replaces the app instead.
Future<void> openSitePage(
  BuildContext context,
  String path, {
  bool leaveApp = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final url = RoomBackendScope.of(context).backend.sitePage(path);
  var opened = false;
  try {
    opened = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: leaveApp ? '_self' : '_blank',
    );
  } catch (_) {}
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open that page.')),
    );
  }
}
