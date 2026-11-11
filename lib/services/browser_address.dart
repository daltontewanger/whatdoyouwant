import 'browser_address_stub.dart'
    if (dart.library.js_interop) 'browser_address_web.dart'
    as browser;

/// Swaps the browser's address for the app's home without adding a history
/// entry, so a page someone was turned away from leaves no trace in the
/// address bar or the back button. Does nothing outside the browser.
void showAppHomeAddress() => browser.showAppHomeAddress();
