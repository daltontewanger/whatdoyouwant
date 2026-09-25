// Worker-local defense: accidental HERE/other external HTTP calls fail before I/O.
// This is not an OS network sandbox; Firebase CLI runs in a separate process.
function installHttpGuard() {
  const restores = [];
  function check(target) {
    let hostname;
    if (typeof target === 'string' || target instanceof URL) hostname = new URL(target).hostname;
    else {
      if (target?.socketPath) throw new Error('Local tests do not allow HTTP socketPath overrides.');
      hostname = target?.hostname || target?.host || 'localhost';
      if (!['::1', '[::1]'].includes(hostname)) hostname = hostname.replace(/:\d+$/, '');
    }
    if (!['localhost', '127.0.0.1', '::1', '[::1]'].includes(hostname)) {
      throw new Error('External HTTP is disabled in local tests. Use synthetic provider fixtures.');
    }
  }
  for (const protocol of ['node:http', 'node:https']) {
    const module = require(protocol);
    for (const method of ['request', 'get']) {
      const original = module[method];
      module[method] = function (...args) {
        check(args[0]);
        if (args[1] && typeof args[1] === 'object') check(args[1]);
        return original.apply(this, args);
      };
      restores.push(() => { module[method] = original; });
    }
  }
  const originalFetch = globalThis.fetch;
  globalThis.fetch = function (input, ...args) {
    check(input instanceof Request ? input.url : input);
    return originalFetch.call(this, input, ...args);
  };
  restores.push(() => { globalThis.fetch = originalFetch; });
  return () => restores.reverse().forEach(restore => restore());
}
module.exports = { installHttpGuard };
