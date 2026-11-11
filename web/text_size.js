// Safari and the other iPhone and iPad browsers don't pass the device's
// text size to web pages, but the -apple-system-body font follows it, at
// 17px for the default size. The app reads the page's root font size
// (16px is its 100%) and watches it, so setting that from the font lets
// the app follow the device. Macs are left alone: their body font is
// smaller and has nothing to do with a text size setting.
(function () {
  if (!window.CSS || !CSS.supports('font', '-apple-system-body')) return;
  if (navigator.maxTouchPoints < 2) return;
  var probe = document.createElement('span');
  probe.setAttribute('aria-hidden', 'true');
  probe.style.cssText = 'position:fixed;visibility:hidden;font:-apple-system-body';
  function follow() {
    document.body.appendChild(probe);
    var size = parseFloat(getComputedStyle(probe).fontSize) || 17;
    probe.remove();
    document.documentElement.style.fontSize = (16 * size / 17) + 'px';
  }
  follow();
  // The setting can change while the app is in the background.
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) follow();
  });
})();
