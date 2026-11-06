import 'dart:js_interop';

@JS('window.history.replaceState')
external void _replaceState(JSAny? data, JSString unused, JSString url);

// Relative to the page's base address, which is the app's home: /app/ on
// the site and / when run locally.
void showAppHomeAddress() => _replaceState(null, ''.toJS, './'.toJS);
