// Runs before the app loads: takes the loading screen away once the app has
// drawn, and runs the page's screen reader link.
(function () {
  window.addEventListener('flutter-first-frame', function () {
    var loading = document.getElementById('loading');
    if (loading) loading.remove();
  });

  // The app keeps its setting under this name (shared_preferences adds the
  // "flutter." prefix and stores values as JSON) and reads it at start, so
  // flipping it here and reloading turns support on or off.
  var key = 'flutter.accessibility.screenReader';
  var link = document.getElementById('reader-support');
  if (!link) return;
  function isOn() {
    try { return localStorage.getItem(key) === 'true'; } catch (error) { return false; }
  }
  link.textContent = isOn() ? 'Turn off screen reader support' : 'Turn on screen reader support';
  link.addEventListener('click', function (event) {
    event.preventDefault();
    try {
      if (isOn()) localStorage.removeItem(key);
      else localStorage.setItem(key, 'true');
    } catch (error) {
      return;
    }
    location.reload();
  });
})();
