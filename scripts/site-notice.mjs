// The site-wide notice (for example "our terms are changing") lives in
// site/notice.json and is written into every page at build time, so it needs
// no script, no storage and no change to the pages' security policy. It shows
// only on builds made between its two dates; outside them, or with no notice
// set, pages are left exactly as they are.

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_MESSAGE = 240;

// Returns the checked notice, or null when none is set.
export function parseNotice(value) {
  if (value?.notice === null) return null;
  const notice = value?.notice;
  const problem = message => { throw new Error(`site/notice.json: ${message}`); };
  if (!notice || typeof notice !== 'object') problem('expected {"notice": null} or {"notice": {...}}.');
  const { message, link, showFrom, showUntil } = notice;
  if (typeof message !== 'string' || !message.trim() || message.length > MAX_MESSAGE) {
    problem(`message must be 1-${MAX_MESSAGE} characters.`);
  }
  if (!DATE.test(showFrom ?? '') || !DATE.test(showUntil ?? '') || showFrom > showUntil) {
    problem('showFrom and showUntil must be YYYY-MM-DD dates, in order.');
  }
  // Only links within this site; a notice is never a way to send people elsewhere.
  if (link !== undefined && (typeof link?.text !== 'string' || !link.text.trim() ||
    typeof link?.href !== 'string' || !/^\/(?!\/)[A-Za-z0-9_\-./#]*$/.test(link.href))) {
    problem('link needs text and an href on this site, such as "/terms#changes".');
  }
  return { message: message.trim(), link, showFrom, showUntil };
}

export function noticeShowsOn(notice, day) {
  return Boolean(notice) && notice.showFrom <= day && day <= notice.showUntil;
}

const escape = text => text.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

export function noticeMarkup(notice) {
  const link = notice.link ? ` <a href="${escape(notice.link.href)}">${escape(notice.link.text.trim())}</a>` : '';
  return `\n  <aside class="site-notice" aria-label="Notice"><div class="wrap"><p>${escape(notice.message)}${link}</p></div></aside>`;
}

// Puts the notice right under the page's top bar.
export function addNotice(html, notice) {
  const bar = /<header class="topbar">[\s\S]*?<\/header>/;
  if (!bar.test(html)) throw new Error('Page has no top bar to put the notice under.');
  return html.replace(bar, header => header + noticeMarkup(notice));
}
