// Errors the app reports about itself. They are only logged, kept as long as
// other server logs, and scrubbed first: no account ID, no query strings,
// nothing that looks like an email address or a map coordinate. The entry is
// shaped as an Error Reporting event, so reports are grouped there and new
// kinds of error can send an email.
const REPORTED_ERROR_EVENT = 'type.googleapis.com/google.devtools.clouderrorreporting.v1beta1.ReportedErrorEvent';
const SERVICE = 'app';
const LIMIT_PER_HOUR = 10;
const HOUR_MS = 60 * 60 * 1000;
const TRACKED_CALLERS = 5000;

function scrub(text, max) {
  return text
    .replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '[email]')
    .replace(/(https?:\/\/[^\s?#)]*)[?#][^\s)]*/g, '$1')
    .replace(/-?\d{1,3}\.\d{4,}/g, '[number]')
    .slice(0, max);
}

function createClientErrorReporter({ now, logError, invalid }) {
  // Per instance, which is enough to stop one browser stuck in an error loop
  // from filling the logs; the function's instance cap bounds the rest.
  const recent = new Map();

  return function report(uid, data) {
    const value = data ?? {};
    if (typeof value !== 'object' || Array.isArray(value)) invalid();
    const allowed = ['message', 'stack', 'build', 'fatal'];
    if (!Object.keys(value).every(key => allowed.includes(key))) invalid();
    const { message, stack = '', build, fatal = false } = value;
    if (typeof message !== 'string' || !message || typeof stack !== 'string' || typeof fatal !== 'boolean' ||
      !Number.isInteger(build) || build < 0 || build > 1e9) {
      invalid();
    }

    const at = now();
    const caller = recent.get(uid);
    if (caller && at - caller.since < HOUR_MS) {
      if (caller.count >= LIMIT_PER_HOUR) return { accepted: false };
      caller.count++;
    } else {
      if (recent.size >= TRACKED_CALLERS) recent.clear();
      recent.set(uid, { since: at, count: 1 });
    }
    const text = scrub(message, 500);
    const trace = scrub(stack, 4000);
    logError({
      '@type': REPORTED_ERROR_EVENT,
      serviceContext: { service: SERVICE, version: String(build) },
      // Error Reporting groups by the message, which reads best with the stack after it.
      message: trace ? `${text}\n${trace}` : text,
      event: 'client_error', build, fatal,
    });
    return { accepted: true };
  };
}

module.exports = { createClientErrorReporter, scrub, LIMIT_PER_HOUR, REPORTED_ERROR_EVENT };
