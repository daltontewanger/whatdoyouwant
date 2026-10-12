// Addresses on the public site, shared by every way the app is installed.

/// The public site for each Firebase project.
const _siteOrigins = {
  'what-do-you-want-8a404': 'https://getwhatdoyouwant.app',
  'whatdoyouwant-staging': 'https://staging.getwhatdoyouwant.app',
};

/// Where the site lives. The web app is already on it, so it uses its own
/// address; installed apps use the project's site.
String siteOrigin(String projectId, {Uri? current}) {
  if (current != null &&
      (current.scheme == 'http' || current.scheme == 'https')) {
    return current.origin;
  }
  return _siteOrigins[projectId] ?? _siteOrigins['what-do-you-want-8a404']!;
}

/// The link a host shares: opening it joins the room with that code.
Uri joinLink(String origin, String joinCode) =>
    Uri.parse('$origin/app/join/$joinCode');

Uri privacyLink(String origin) => Uri.parse('$origin/privacy');

/// What an app address asks the app to open.
enum AppLinkTarget { host, join, account }

class AppLink {
  const AppLink(this.target, {this.joinCode});

  final AppLinkTarget target;

  /// Set when a join link carries the room's code.
  final String? joinCode;
}

bool _launchLinkTaken = false;

/// The link the web app was opened with, handed out only once. Home is built
/// again when a room ends, and it must not rejoin the room it came from.
AppLink? takeLaunchLink(Uri uri) {
  if (_launchLinkTaken) return null;
  _launchLinkTaken = true;
  return appLinkFrom(uri);
}

/// Reads `/app/host`, `/app/join`, `/app/join/<code>` and `/app/account`. The
/// app is served from `/app` on the site and from the root during local
/// development.
AppLink? appLinkFrom(Uri uri) {
  final segments = [...uri.pathSegments.where((part) => part.isNotEmpty)];
  if (segments.isNotEmpty && segments.first == 'app') segments.removeAt(0);
  if (segments.length == 2 && segments.first == 'join') {
    final code = segments[1].toUpperCase();
    if (RegExp(r'^[A-HJKMNP-Z2-9]{6}$').hasMatch(code)) {
      return AppLink(AppLinkTarget.join, joinCode: code);
    }
    return null;
  }
  if (segments.length != 1) return null;
  return switch (segments.single) {
    'host' => const AppLink(AppLinkTarget.host),
    'join' => const AppLink(AppLinkTarget.join),
    'account' => const AppLink(AppLinkTarget.account),
    _ => null,
  };
}
