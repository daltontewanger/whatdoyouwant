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
    for (final (path, target) in [
      ('app/account', AppLinkTarget.account),
      ('app/host', AppLinkTarget.host),
      ('app/join', AppLinkTarget.join),
    ]) {
      final link = appLinkFrom(Uri.parse('https://example.test/$path'));
      expect((link?.target, link?.joinCode), (target, null), reason: path);
    }
    for (final other in [
      'https://example.test/app/',
      'https://example.test/app/settings',
      'https://example.test/app/join/AB3K7',
      'https://example.test/app/join/AB3K7I',
      'https://example.test/app/join/AB3K7X/extra',
      'https://example.test/privacy',
    ]) {
      expect(appLinkFrom(Uri.parse(other)), isNull, reason: other);
    }
  });

  test('the launch link is acted on once', () {
    final opened = Uri.parse('https://example.test/app/join/AB3K7X');
    expect(takeLaunchLink(opened)?.joinCode, 'AB3K7X');
    // Home is rebuilt when a room ends; the same address must not join again.
    expect(takeLaunchLink(opened), isNull);
  });

  test('installed apps link to their project site; the web app to itself', () {
    expect(
      siteOrigin('whatdoyouwant-staging'),
      'https://staging.getwhatdoyouwant.app',
    );
    expect(
      siteOrigin('what-do-you-want-8a404'),
      'https://getwhatdoyouwant.app',
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
      sitePageLink('https://whatdoyouwant.example', '/privacy').toString(),
      'https://whatdoyouwant.example/privacy',
    );
  });

  test('emailed account links open the account step with their code', () {
    final link = appLinkFrom(
      Uri.parse(
        'https://getwhatdoyouwant.app/app/account?mode=resetPassword&oobCode=abc123&apiKey=k&lang=en',
      ),
    );
    expect(link?.target, AppLinkTarget.accountAction);
    expect(link?.mode, 'resetPassword');
    expect(link?.code, 'abc123');
    expect(
      appLinkFrom(
        Uri.parse('http://localhost:5080/?mode=verifyEmail&oobCode=x'),
      )?.mode,
      'verifyEmail',
    );
    // Unknown steps, missing codes and other pages are left alone.
    for (final address in [
      'https://getwhatdoyouwant.app/app/account?mode=signIn&oobCode=x',
      'https://getwhatdoyouwant.app/app/account?mode=resetPassword',
      'https://getwhatdoyouwant.app/app/join/AB3K7X?mode=verifyEmail&oobCode=x',
    ]) {
      expect(
        appLinkFrom(Uri.parse(address))?.target,
        isNot(AppLinkTarget.accountAction),
        reason: address,
      );
    }
    expect(
      accountReturnLink('whatdoyouwant-staging').toString(),
      'https://staging.getwhatdoyouwant.app/app/account',
    );
  });
}
