/// A quick check that an address could be real before anything is sent. It
/// can't know whether the mailbox exists; only the verification email can.
String? emailProblem(String value) {
  final email = value.trim();
  if (email.isEmpty) return 'Enter your email address.';
  // One @, a name before it, and a domain with a dot and a real-looking ending.
  final shape = RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)*\.[A-Za-z]{2,}$');
  if (!shape.hasMatch(email)) return 'Enter a valid email address.';
  return null;
}
