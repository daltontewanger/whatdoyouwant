import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/site_links.dart';

void main() {
  test('join and account links are read from the site or a local run', () {
    expect(
      appLinkFrom(Uri.parse('https://example.test/app/join/ab3k7x'))?.joinCode,
      'AB3K7X',
    );
    expect(
      appLinkFrom(Uri.parse('http://localhost:5080/join/AB3K7X'))?.joinCode,
      'AB3K7X',
    );
    expect(
      appLinkFrom(Uri.parse('https://example.test/app/account'))?.account,
      isTrue,
    );
    for (final other in [
      'https://example.test/app/',
      'https://example.test/app/join/AB3K7',
      'https://example.test/app/join/AB3K7I',
      'https://example.test/app/join/AB3K7X/extra',
      'https://example.test/privacy',
    ]) {
      expect(appLinkFrom(Uri.parse(other)), isNull, reason: other);
    }
  });

  test('installed apps link to their project site; the web app to itself', () {
    expect(
      siteOrigin('whatdoyouwant-staging'),
      'https://whatdoyouwant-staging.web.app',
    );
    expect(
      siteOrigin('what-do-you-want-8a404'),
      'https://what-do-you-want-8a404.web.app',
    );
    expect(
      siteOrigin(
        'what-do-you-want-8a404',
        current: Uri.parse('https://whatdoyouwant.example/app/'),
      ),
      'https://whatdoyouwant.example',
    );
    expect(
      joinLink('https://whatdoyouwant.example', 'AB3K7X').toString(),
      'https://whatdoyouwant.example/app/join/AB3K7X',
    );
    expect(
      privacyLink('https://whatdoyouwant.example').toString(),
      'https://whatdoyouwant.example/privacy',
    );
  });
}
