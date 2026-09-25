import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:whatdoyouwant/firebase_options_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/environment_guard.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('entry points reject other projects and unknown environments', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    for (final pair
        in {
          'production': 'what-do-you-want-8a404',
          'staging': 'whatdoyouwant-staging',
          'local': 'demo-whatdoyouwant',
        }.entries) {
      expect(
        () => checkFirebaseEnvironment(pair.key, pair.value),
        returnsNormally,
      );
      expect(
        () => checkFirebaseEnvironment(pair.key, 'wrong-project'),
        throwsStateError,
      );
    }
    expect(
      () => checkFirebaseEnvironment('unknown', 'wrong-project'),
      throwsStateError,
    );
  });
  test('Android requires the exact environment flavor', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    for (final pair
        in {
          'local': 'demo-whatdoyouwant',
          'staging': 'whatdoyouwant-staging',
          'production': 'what-do-you-want-8a404',
        }.entries) {
      expect(
        () => checkFirebaseEnvironment(pair.key, pair.value),
        appFlavor == pair.key ? returnsNormally : throwsStateError,
      );
    }
  });
  test('local Android native and Dart Firebase options agree', () {
    final config = jsonDecode(
      File('android/app/src/local/google-services.json').readAsStringSync(),
    );
    final native = config['client'][0];
    const options = LocalFirebaseOptions.android;
    expect(native['api_key'][0]['current_key'], options.apiKey);
    expect(native['client_info']['mobilesdk_app_id'], options.appId);
    expect(config['project_info']['project_id'], options.projectId);
    expect(config['project_info']['project_number'], options.messagingSenderId);
  });
}
