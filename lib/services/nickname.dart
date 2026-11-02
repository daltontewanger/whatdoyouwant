import 'package:cloud_functions/cloud_functions.dart';

import 'live_search.dart';

/// The same format the server accepts, checked on the device first so the
/// person hears about a typo straight away. Blocked words are only known to
/// the server.
class Nickname {
  static const minLength = 2;
  static const maxLength = 20;

  static final _allowed = RegExp(r"^[\p{L}\p{M}0-9 ._'-]+$", unicode: true);
  static final _letterOrDigit = RegExp(r'[\p{L}0-9]', unicode: true);
  static final _domainLike = RegExp(
    r'[\p{L}\p{M}0-9]\.[\p{L}\p{M}0-9]{2,}',
    unicode: true,
  );

  /// Trimmed, with runs of spaces made one, as the server stores it.
  static String tidy(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// What is wrong with [raw], or null when it can be sent. Empty is fine:
  /// it clears the nickname.
  static String? problem(String raw) {
    final text = tidy(raw);
    if (text.isEmpty) return null;
    final length = text.runes.length;
    if (length < minLength || length > maxLength) {
      return 'Use $minLength to $maxLength characters.';
    }
    if (!_allowed.hasMatch(text) || !_letterOrDigit.hasMatch(text)) {
      return "Use letters, numbers, spaces and - _ . ' only.";
    }
    if (_domainLike.hasMatch(text)) {
      return "A nickname can't look like a web address.";
    }
    return null;
  }
}

String nicknameErrorMessage(Object error) {
  switch (callableReason(error)) {
    case 'nickname-blocked':
      return "That nickname isn't allowed. Try a different one.";
    case 'nickname-format':
      return "Use letters, numbers, spaces and - _ . ' only.";
  }
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'resource-exhausted':
        return 'Too many changes for now. Try again later.';
      case 'permission-denied':
        return 'Verify your email to choose a nickname.';
    }
  }
  return 'Your nickname could not be saved. Check your connection and try again.';
}
