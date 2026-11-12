// Limits per network, on top of the limits per account. A script can make a
// new guest account for every request, but it can't easily change networks
// as fast. Kept free of Firebase imports so it can be unit tested directly.
const net = require('node:net');

// Cloud Run appends the address it received the request from as the last
// X-Forwarded-For entry. Anything the caller put in the header sits in front
// of it, so the last entry is the one a caller cannot forge.
function clientNetwork(rawRequest) {
  const forwarded = rawRequest?.headers?.['x-forwarded-for'];
  const header = Array.isArray(forwarded) ? forwarded.join(',') : forwarded;
  const entries = typeof header === 'string' ? header.split(',').map(entry => entry.trim()).filter(Boolean) : [];
  return { network: networkOf(entries.at(-1) ?? rawRequest?.ip), entries: entries.length };
}

// IPv4 addresses count on their own. An IPv6 home or phone usually has a whole
// /64 to itself, so those count by that prefix.
function networkOf(address) {
  if (typeof address !== 'string') return null;
  let ip = address.trim();
  if (ip.startsWith('[')) ip = ip.slice(1, ip.indexOf(']'));
  const withPort = ip.match(/^(\d{1,3}(?:\.\d{1,3}){3}):\d+$/);
  if (withPort) ip = withPort[1];
  if (/^::ffff:/i.test(ip) && net.isIPv4(ip.slice(7))) ip = ip.slice(7);
  if (net.isIPv4(ip)) return ip;
  if (!net.isIPv6(ip)) return null;
  const gap = ip.includes('::');
  const [left, right = ''] = gap ? ip.split('::') : [ip];
  const head = left ? left.split(':') : [];
  const tail = right ? right.split(':') : [];
  const tailGroups = tail.reduce((total, part) => total + (part.includes('.') ? 2 : 1), 0);
  const groups = [...head, ...Array(gap ? 8 - head.length - tailGroups : 0).fill('0'), ...tail];
  return `${groups.slice(0, 4).map(group => parseInt(group, 16).toString(16)).join(':')}::/64`;
}

// Calls per network per minute on this server instance. Kept in memory, so it
// costs nothing and turns a flood away before any database work. The whole
// table starts over each minute, which also bounds its size.
function createNetworkWindow({ now, perMinute, maxTracked = 20000 }) {
  let minute = -1;
  let counts = new Map();
  return network => {
    const current = Math.floor(now() / 60000);
    if (current !== minute) {
      minute = current;
      counts = new Map();
    }
    if (!counts.has(network) && counts.size >= maxTracked) return true;
    const calls = (counts.get(network) ?? 0) + 1;
    counts.set(network, calls);
    return calls <= perMinute;
  };
}

const MODES = Object.freeze(['off', 'log', 'enforce']);

module.exports = { clientNetwork, networkOf, createNetworkWindow, MODES };
