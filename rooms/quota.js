// Calendar keys and server configuration for live-search limits. Kept free of
// Firebase imports so they can be unit tested directly.
const DAY_MS = 24 * 3600000;
const WEEK_MS = 7 * DAY_MS;

// Weeks start Monday 00:00 UTC.
function weekOf(ms) {
  const date = new Date(ms);
  const daysSinceMonday = (date.getUTCDay() + 6) % 7;
  const startsAt = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() - daysSinceMonday);
  return { key: new Date(startsAt).toISOString().slice(0, 10), startsAt, resetsAt: startsAt + WEEK_MS };
}

function monthOf(ms) {
  return new Date(ms).toISOString().slice(0, 7);
}

const count = value => (Number.isInteger(value) && value >= 0 ? value : null);

// config/liveSearch, read on every generation. Anything missing or malformed
// pauses live search rather than falling back to a guess.
function liveSearchConfig(data) {
  const caps = {};
  if (data?.weeklyCaps && typeof data.weeklyCaps === 'object') {
    for (const [entitlement, cap] of Object.entries(data.weeklyCaps)) {
      if (count(cap) !== null) caps[entitlement] = cap;
    }
  }
  const monthlyCallStop = count(data?.monthlyCallStop);
  const configured = Boolean(data) && monthlyCallStop !== null && count(caps.free) !== null;
  return {
    enabled: configured && data.enabled === true,
    pausedReason: !data ? 'not-configured'
      : !configured ? 'misconfigured'
        : data.enabled === true ? null
          : (typeof data.pausedReason === 'string' && data.pausedReason) || 'paused',
    weeklyCaps: caps,
    monthlyCallStop: monthlyCallStop ?? 0,
  };
}

// Features held back behind switches in the same document, all off unless
// set exactly right:
//   deckNotices: { enabled: true, every: 3-10, title, text }  a card in room
//     decks every so often that nobody votes on (room for future ad cards).
//   photos: { enabled: true }  keep a place photo if the provider sends one.
function deckFeatures(data) {
  const notices = data?.deckNotices;
  const words = (value, max) => (typeof value === 'string' && value.trim() && value.length <= max ? value.trim() : null);
  const valid = notices?.enabled === true && Number.isInteger(notices.every) && notices.every >= 3 &&
    notices.every <= 10 && words(notices.title, 60) && words(notices.text, 200);
  return {
    notices: valid ? { every: notices.every, title: words(notices.title, 60), text: words(notices.text, 200) } : null,
    photos: data?.photos?.enabled === true,
  };
}

function weeklyCapFor(config, entitlement) {
  return config.weeklyCaps[entitlement] ?? config.weeklyCaps.free ?? 0;
}

module.exports = { weekOf, monthOf, liveSearchConfig, deckFeatures, weeklyCapFor, DAY_MS, WEEK_MS };
