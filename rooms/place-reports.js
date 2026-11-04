// Reports that a place from a result is closed or has wrong details. The
// person who reports a place closed stops seeing it at once (the app keeps
// that on their own lists); here, reports from separate verified accounts add
// up until the place, or just its wrong button, is hidden for everyone for a
// while. A reopened place comes back when the hiding runs out.
//
// placeReports/{cardId}/byAccount/{hash of uid and kind}: one per account and
//   kind, counted for REPORT_WINDOW_MS. Tied to the account only through a
//   hash of its UID, and deleted with the account.
// placeFlags/{cardId}: what is hidden for everyone and until when. A place
//   hidden as closed keeps its name and address for 30 days at most, so the
//   owner can pass the list on to HERE.
const { PLACE_ID } = require('./place-lists');

const DAY_MS = 24 * 3600000;
const REPORT_WINDOW_MS = 90 * DAY_MS;
const HIDDEN_MS = 180 * DAY_MS;
const FLAG_DETAILS_MS = 30 * DAY_MS;
const REPORTS_TO_HIDE = 3;
// What each kind hides once enough accounts agree; a wrong map spot is only
// collected, since there is nothing in the app to correct.
const KINDS = Object.freeze({ closed: 'closedUntil', website: 'websiteUntil', phone: 'phoneUntil', location: null });
const ROOM_ID = /^[A-F0-9]{24}$/;
const QUICK_PICK_ID = /^[a-f0-9]{24}$/;

class InvalidReport extends Error {}

/** `{cardId, kind}` plus where the place was shown: a room or a Quick Pick. */
function parseReport(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new InvalidReport();
  const keys = Object.keys(data).sort().join();
  const from = keys === 'cardId,kind,roomId' ? 'room' : keys === 'cardId,kind,quickPickId' ? 'quickPick' : null;
  const target = from === 'room' ? data.roomId : data.quickPickId;
  if (!from || typeof data.cardId !== 'string' || !PLACE_ID.test(data.cardId) ||
    typeof data.kind !== 'string' || !Object.hasOwn(KINDS, data.kind) || typeof target !== 'string' ||
    !(from === 'room' ? ROOM_ID : QUICK_PICK_ID).test(target)) {
    throw new InvalidReport();
  }
  return { cardId: data.cardId, kind: data.kind, from, targetId: target };
}

/**
 * Whether a shown card can take this kind of report: places from a search
 * only, and a wrong website or phone only when the card had one.
 */
function reportable(card, kind) {
  if (!card || card.userEntered || !PLACE_ID.test(card.id ?? '')) return false;
  if (kind === 'website') return Boolean(card.website);
  if (kind === 'phone') return Boolean(card.phone);
  return true;
}

/** What is hidden for everyone right now, from a placeFlags document. */
function activeFlags(data, now) {
  const until = field => (data?.[field]?.toMillis?.() ?? 0) > now;
  return { closed: until('closedUntil'), website: until('websiteUntil'), phone: until('phoneUntil') };
}

module.exports = { parseReport, reportable, activeFlags, InvalidReport, KINDS, REPORT_WINDOW_MS, HIDDEN_MS,
  FLAG_DETAILS_MS, REPORTS_TO_HIDE };
