import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void checkFirebaseEnvironment(String environment, String projectId) {
  const projects = {
    'production': 'what-do-you-want-8a404',
    'staging': 'whatdoyouwant-staging',
    'local': 'demo-whatdoyouwant',
  };
  if (!projects.containsKey(environment) ||
      projects[environment] != projectId) {
    throw StateError('Firebase project does not match the entry point.');
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final expected = environment;
    if (appFlavor != expected) {
      throw StateError('Android flavor does not match the entry point.');
    }
  }
}
