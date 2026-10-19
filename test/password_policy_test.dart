import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/password_policy.dart';

void main() {
  test('length is what counts, with no character-type rules', () {
    expect(PasswordPolicy.problem('elevenchars'), contains('at least 12'));
    expect(PasswordPolicy.problem('blue kettle morning'), isNull);
    expect(PasswordPolicy.problem('alllowercaseletters'), isNull);
    expect(PasswordPolicy.problem('x' * 128 + 'y'), contains('at most 128'));
  });

  test('length is counted in characters, so other scripts and emoji fit', () {
    expect(PasswordPolicy.problem('🍕🌮🍣🍔🥗🍜🍩🍪🥐🧇🥞🍦'), isNull);
    expect(PasswordPolicy.problem('お腹がすいたので何か食べよう'), isNull);
    expect(PasswordPolicy.problem('🍕🌮🍣🍔🥗🍜'), contains('at least 12'));
  });

  test('common and patterned passwords are rejected', () {
    for (final weak in [
      'password1234',
      'Password1234!',
      'p@ssw0rd2026',
      'qwertyuiop12',
      '123456789012',
      'abcdefghijklm',
      'aaaaaaaaaaaaaa',
      'abababababab',
      'iloveyou1234',
      'WhatDoYouWant2026',
    ]) {
      expect(PasswordPolicy.problem(weak), contains('too easy'), reason: weak);
    }
  });

  test("a password built on the person's own email name is rejected", () {
    expect(
      PasswordPolicy.problem(
        'pat.morgan1990!',
        email: 'pat.morgan@example.test',
      ),
      contains('too easy'),
    );
    expect(
      PasswordPolicy.problem('blue kettle morning', email: 'pat@example.test'),
      isNull,
    );
  });
}
