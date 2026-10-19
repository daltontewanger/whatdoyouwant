/// What a new password must meet. Length matters most; there are no rules
/// about mixing character types, any character is allowed (spaces included,
/// so passphrases work), and nothing is ever cut short.
abstract final class PasswordPolicy {
  static const minLength = 12;
  // Generous, so long passphrases and password-manager output fit.
  static const maxLength = 128;

  static const hint =
      'At least $minLength characters. A short phrase of a few words works well.';

  /// Why [password] can't be used, or null when it's fine. [email] lets it
  /// reject passwords built from the person's own address.
  static String? problem(String password, {String email = ''}) {
    // Counted in characters as people see them, not UTF-16 code units.
    final length = password.runes.length;
    if (length < minLength) {
      return 'Use a password with at least $minLength characters.';
    }
    if (length > maxLength) {
      return 'Use a password with at most $maxLength characters.';
    }
    if (_guessable(password, email)) {
      return 'That password is too easy to guess. Try a short phrase instead.';
    }
    return null;
  }

  static bool _guessable(String password, String email) {
    final plain = password.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (plain.runes.toSet().length <= 2) return true;
    // The letters left once digits and symbols around them are dropped.
    final trimmed = plain.replaceAll(RegExp(r'^[^a-z]+|[^a-z]+$'), '');
    if (_runs.any(
      (run) =>
          run.contains(plain) || (trimmed.length >= 6 && run.contains(trimmed)),
    )) {
      return true;
    }
    final name = email.split('@').first.toLowerCase();
    if (name.length >= 4 && plain.contains(name)) return true;
    // Common passwords and the app's own name with digits or symbols tacked
    // on and letters swapped for look-alikes, such as "p@ssw0rd2026!".
    final core = trimmed.split('').map((c) => _lookAlikes[c] ?? c).join();
    return _common.contains(plain) || _commonWords.contains(core);
  }

  static const _lookAlikes = {
    '@': 'a',
    '4': 'a',
    '3': 'e',
    '1': 'i',
    '!': 'i',
    '0': 'o',
    r'$': 's',
    '5': 's',
    '7': 't',
  };

  // Keyboard and counting runs; anything that fits inside one is a pattern.
  static const _runs = [
    '1234567890123456789012345678901234567890',
    '0987654321098765432109876543210987654321',
    'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz',
    'qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnm',
    'qwertyuiopqwertyuiopqwertyuiop',
    'asdfghjklasdfghjklasdfghjkl',
    'zxcvbnmzxcvbnmzxcvbnm',
    '1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik9ol0p',
    'qazwsxedcrfvtgbyhnujmikolp',
  ];

  // Long entries from common-password lists that pass the length check.
  static const _common = {
    'passwordpassword',
    'iloveyouiloveyou',
    'letmeinletmein',
    'trustno1trustno1',
    'football1234',
    'baseball1234',
    'starwars1234',
    'mustang12345',
    'princess1234',
    'sunshine1234',
    'welcome12345',
    'changeme1234',
    'administrator',
    'administrator1',
    'qwertyqwerty',
    'abc123abc123',
    'aaaaaaaaaaaa',
    'myspace12345',
    'superman1234',
    'iloveyou1234',
  };

  // Words that, with only digits or symbols around them, make a weak password.
  static const _commonWords = {
    'password',
    'passw',
    'pass',
    'passwd',
    'iloveyou',
    'letmein',
    'welcome',
    'admin',
    'administrator',
    'qwerty',
    'monkey',
    'dragon',
    'football',
    'baseball',
    'sunshine',
    'princess',
    'starwars',
    'whatdoyouwant',
    'whatdoyouwantapp',
    'getwhatdoyouwant',
    'changeme',
    'secret',
    'login',
    'master',
    'shadow',
    'superman',
    'batman',
    'trustno',
    'abc',
  };
}
