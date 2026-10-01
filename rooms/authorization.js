// Who may do what to a room. Kept free of Firebase imports so rules tests can
// exercise the same contract the callables enforce.
const REGISTERED_PROVIDERS = ['password', 'google.com', 'apple.com'];

function isRegistered(identity) {
  return REGISTERED_PROVIDERS.includes(identity?.provider) && identity.emailVerified === true;
}

function authorize(action, identity, room, member, now = Date.now()) {
  if (typeof identity?.uid !== 'string' || !identity.uid.length) return false;
  if (action === 'create') return isRegistered(identity);
  if (!room || !Number.isFinite(room.expiresAt) || room.expiresAt <= now) return false;
  if (action === 'join') return room.status === 'lobby';
  if (action === 'start') {
    return isRegistered(identity) && room.creator === identity.uid && member === true && room.status === 'lobby';
  }
  return false;
}

module.exports = { authorize, isRegistered };
