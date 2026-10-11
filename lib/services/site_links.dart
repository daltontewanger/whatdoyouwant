// Addresses on the public site, shared by every way the app is installed.

/// The public site for each Firebase project. The custom domain replaces the
/// production entry once it is connected.
const _siteOrigins = {
  'what-do-you-want-8a404': 'https://what-do-you-want-8a404.web.app',
  'whatdoyouwant-staging': 'https://whatdoyouwant-staging.web.app',
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
class AppLink {
  const AppLink.join(this.joinCode) : account = false;
  const AppLink.account() : joinCode = null, account = true;

  final String? joinCode;
  final bool account;
}

/// Reads `/app/join/<code>` and `/app/account`. The app is served from `/app`
/// on the site and from the root during local development.
AppLink? appLinkFrom(Uri uri) {
  final segments = [...uri.pathSegments.where((part) => part.isNotEmpty)];
  if (segments.isNotEmpty && segments.first == 'app') segments.removeAt(0);
  if (segments.length == 2 && segments.first == 'join') {
    final code = segments[1].toUpperCase();
    if (RegExp(r'^[A-HJKMNP-Z2-9]{6}$').hasMatch(code)) {
      return AppLink.join(code);
    }
  }
  if (segments.length == 1 && segments.first == 'account') {
    return const AppLink.account();
  }
  return null;
}
