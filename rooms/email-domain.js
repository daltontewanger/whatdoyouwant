// Whether an email domain can receive mail, asked before someone signs up so
// typos ("gmial.con") and made-up domains are caught while they can still fix
// them. It can't tell whether a mailbox exists; only the verification email
// can. Only the domain is looked up, never the address, and nothing is logged.
const dns = require('node:dns').promises;

const TIMEOUT_MS = 3000;
const CACHE_MS = 60 * 60 * 1000;
const CACHE_SIZE = 5000;
const DOMAIN = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
// Answers that mean the name truly has nothing to deliver to.
const MISSING = new Set(['ENOTFOUND', 'ENODATA', 'NXDOMAIN']);

function within(promise, ms) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(Object.assign(new Error('timeout'), { code: 'ETIMEOUT' })), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}

function createMailDomainCheck({
  resolveMx = name => dns.resolveMx(name),
  resolveAddress = name => dns.lookup(name),
  now = () => Date.now(),
  timeoutMs = TIMEOUT_MS,
} = {}) {
  const cache = new Map();

  async function lookUp(domain) {
    try {
      const records = await within(resolveMx(domain), timeoutMs);
      // A single empty exchange is a "null MX": the domain says it takes no mail.
      if (records.length === 1 && ['', '.'].includes(records[0].exchange)) return false;
      if (records.length) return true;
    } catch (error) {
      if (!MISSING.has(error?.code)) return true;
      if (error.code !== 'ENODATA') return false;
    }
    // No mail records: mail falls back to the domain's own address, if it has one.
    try {
      await within(resolveAddress(domain), timeoutMs);
      return true;
    } catch (error) {
      return !MISSING.has(error?.code);
    }
  }

  /** True unless the domain clearly can't receive mail; DNS trouble lets it through. */
  return async function canReceiveMail(value) {
    const domain = String(value ?? '').trim().toLowerCase().replace(/\.$/, '');
    if (!DOMAIN.test(domain)) return false;
    const cached = cache.get(domain);
    if (cached && now() - cached.at < CACHE_MS) return cached.answer;
    const answer = await lookUp(domain);
    if (cache.size >= CACHE_SIZE) cache.clear();
    cache.set(domain, { answer, at: now() });
    return answer;
  };
}

module.exports = { createMailDomainCheck };
