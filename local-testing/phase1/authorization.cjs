// Executable contract only; deliberately not imported by production Functions.
function authorize(action, identity, room, member, now = Date.now()) {
  if (typeof identity?.uid !== 'string' || !identity.uid.length) return false;
  const registered = ['password', 'google.com', 'apple.com'].includes(identity.provider) && identity.emailVerified === true;
  if (action === 'create') return registered;
  if (!room || !Number.isFinite(room.expiresAt) || room.expiresAt <= now) return false;
  if (action === 'join') return room.status === 'lobby';
  if (action === 'search') return registered && room.creator === identity.uid && member === true && room.status === 'lobby';
  return false;
}
module.exports = { authorize };
