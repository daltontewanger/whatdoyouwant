// Room callables shared by the deployed codebase and the local emulator entry.
// Firebase modules are injected so each entry can supply its own copies.
const { randomBytes, randomInt, createHash } = require('node:crypto');
const { authorize } = require('./authorization');
const { parseSearchRequest, InvalidSearchRequest } = require('./search/request');
const { assertProvider } = require('./search/provider');
const { createFakeProvider } = require('./search/fake-provider');
const { resultCard, storedCandidate } = require('./decks');
const { createGeneration } = require('./generation');

const ROOM_TTL_MS = 24 * 3600000;
const VOTING_WINDOW_MS = 30 * 60000;
// Provider decks are kept only as long as a vote needs them: until 30 minutes
// after voting ends, or 15 minutes after the room closes, whichever is sooner.
// The winner and backup are copied onto the room's results first.
const DECK_AFTER_VOTING_MS = 30 * 60000;
const DECK_AFTER_CLOSE_MS = 15 * 60000;
const SWEEP_BATCH = 200;
const RECEIPT_TTL_MS = 24 * 3600000;
// A Quick Pick and its deck last an hour: long enough to decide, short enough
// that provider results are not kept around.
const QUICK_PICK_MS = 60 * 60000;
const MAX_REROLLS = 5;
const QUICK_PICK_ID = /^[a-f0-9]{24}$/;
const RECENT_SIGN_IN_SECONDS = 300;
// Members per room, host included.
const CAPACITY = 15;
// No 0/O, 1/I/L: codes are read aloud and typed on phones.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE = /^[A-HJKMNP-Z2-9]{6}$/;
const ROOM_ID = /^[A-F0-9]{24}$/;
const REQUEST_ID = /^[A-Za-z0-9_-]{16,64}$/;
const UID = /^[A-Za-z0-9]{1,128}$/;

const digest = value => createHash('sha256').update(value).digest('hex');
const newJoinCode = () => Array.from({ length: 6 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join('');

function createRoomHandlers({ db, FieldValue, Timestamp, HttpsError, deleteAuthUser,
  now = () => Date.now(), provider = createFakeProvider(), newSeed = () => randomBytes(16).toString('hex'),
  log = () => {} }) {
  assertProvider(provider);
  const deny = () => { throw new HttpsError('permission-denied', 'Room action unavailable.'); };
  const invalid = () => { throw new HttpsError('invalid-argument', 'Invalid request.'); };
  const expiry = ms => Timestamp.fromMillis(now() + ms);

  function identity(request) {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in first.');
    const token = request.auth.token;
    return { uid: request.auth.uid, provider: token.firebase?.sign_in_provider,
      emailVerified: token.email_verified === true, authTime: token.auth_time };
  }

  // Accepts exactly one of the given shapes; no extra fields, so a client cannot
  // smuggle in identity or state.
  function input(request, ...shapes) {
    const value = request.data ?? {};
    if (typeof value !== 'object' || Array.isArray(value)) invalid();
    const keys = Object.keys(value);
    for (const shape of shapes) {
      const names = Object.keys(shape);
      if (keys.length !== names.length || !names.every(name => keys.includes(name))) continue;
      const parsed = {};
      for (const name of names) {
        let field = value[name];
        if (typeof field !== 'string') invalid();
        if (name === 'joinCode') field = field.toUpperCase().replace(/[\s-]/g, '');
        if (!shape[name].test(field)) invalid();
        parsed[name] = field;
      }
      return parsed;
    }
    return invalid();
  }

  async function limit(uid, action, maximum, period) {
    const bucket = Math.floor(now() / period);
    const ref = db.doc(`_limits/${digest(`${uid}:${action}:${bucket}`)}`);
    await db.runTransaction(async tx => {
      const previous = await tx.get(ref);
      const count = previous.exists ? previous.data().count : 0;
      if (count >= maximum) throw new HttpsError('resource-exhausted', 'Please wait before trying again.');
      tx.set(ref, { count: count + 1, expiresAt: Timestamp.fromMillis((bucket + 2) * period) });
    });
  }

  // gRPC CANCELLED, DEADLINE_EXCEEDED, ABORTED and UNAVAILABLE: worth one more try.
  async function retryTransient(operation) {
    try {
      return await operation();
    } catch (error) {
      if (![1, 4, 10, 14].includes(error?.code)) throw error;
      return operation();
    }
  }

  const generation = createGeneration({ db, FieldValue, Timestamp, HttpsError, provider, now, newSeed, log,
    retryTransient });

  // A target ID plus one search request. The search is parsed by its own
  // strict contract; its origin is used for this call and never kept.
  function searchInput(request, name, pattern) {
    const value = request.data ?? {};
    if (typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join() !== [name, 'search'].sort().join() || typeof value[name] !== 'string' ||
      !pattern.test(value[name])) {
      invalid();
    }
    try {
      return { [name]: value[name], search: parseSearchRequest(value.search) };
    } catch (error) {
      if (error instanceof InvalidSearchRequest) invalid();
      throw error;
    }
  }

  function rerollInput(request) {
    const value = request.data ?? {};
    if (typeof value !== 'object' || Array.isArray(value) || Object.keys(value).sort().join() !== 'from,quickPickId' ||
      typeof value.quickPickId !== 'string' || !QUICK_PICK_ID.test(value.quickPickId) ||
      !Number.isInteger(value.from) || value.from < 0 || value.from > 24) {
      invalid();
    }
    return value;
  }

  const quickPickRef = quickPickId => db.doc(`quickPicks/${quickPickId}`);
  const quickPickView = (quickPickId, data) => ({ quickPickId, deckId: data.deckId, position: data.position,
    candidateId: data.order[data.position],
    rerollsLeft: Math.max(0, Math.min(MAX_REROLLS - data.rerollsUsed, data.order.length - 1 - data.position)) });
  function shuffled(ids) {
    const order = [...ids];
    for (let i = order.length - 1; i > 0; i--) {
      const j = randomInt(i + 1);
      [order[i], order[j]] = [order[j], order[i]];
    }
    return order;
  }

  const roomRef = roomId => db.doc(`rooms/${roomId}`);
  const deckRef = deckId => db.doc(`restaurantDecks/${deckId}`);
  const startedView = (roomId, state) => ({ roomId, deckId: state.deckId ?? null,
    candidateCount: state.candidateCount ?? 0 });
  const codeRef = code => db.doc(`roomCodes/${code}`);
  const stateOf = snapshot => ({ ...snapshot.data(), expiresAt: snapshot.data().expiresAt.toMillis() });

  // Reads everything a room operation needs and rejects callers who are not an
  // active member of a live room. Must run before any transaction writes.
  async function memberView(tx, roomId, uid) {
    const room = roomRef(roomId);
    const [snapshot, membership] = await Promise.all([tx.get(room), tx.get(room.collection('members').doc(uid))]);
    if (!snapshot.exists) deny();
    const state = stateOf(snapshot);
    if (state.expiresAt <= now() || !membership.exists || membership.data().active !== true) deny();
    return { room, snapshot, state };
  }

  async function tally(tx, room, state) {
    const [members, deck] = await Promise.all([
      tx.get(room.collection('members').where('active', '==', true)),
      state.deckId ? tx.get(deckRef(state.deckId)) : null,
    ]);
    const deckData = deck?.exists ? deck.data() : null;
    const deckIds = deckData?.candidateIds ?? [];
    const likes = Object.fromEntries(deckIds.map(id => [id, 0]));
    let voters = 0;
    let complete = true;
    for (const member of members.docs) {
      const ballots = await tx.get(room.collection('votes').doc(member.id).collection('ballot'));
      if (!ballots.empty) voters++;
      if (ballots.size < (state.candidateCount ?? deckIds.length)) complete = false;
      for (const ballot of ballots.docs) {
        if (ballot.data().liked === true && ballot.id in likes) likes[ballot.id]++;
      }
    }
    // Most likes wins; deck order (best ranked first) breaks ties.
    const ranking = [...deckIds].sort((a, b) => likes[b] - likes[a]);
    const card = id => resultCard(deckData?.candidates?.find(candidate => candidate.id === id));
    const winner = ranking[0] ?? null;
    const backup = ranking[1] ?? null;
    return { complete, deck: deck?.exists ? deck : null,
      results: { likes, winner, backup, voters, winnerCard: card(winner), backupCard: card(backup) } };
  }

  // Closing keeps the result on the room and lets the deck go shortly after.
  function closeInto(tx, room, state, outcome) {
    tx.update(room, { status: 'closed', closedAt: FieldValue.serverTimestamp(), joinCode: FieldValue.delete(),
      ...(outcome?.results ? { results: outcome.results } : {}) });
    if (state.joinCode) tx.delete(codeRef(state.joinCode));
    const soon = now() + DECK_AFTER_CLOSE_MS;
    if (outcome?.deck && outcome.deck.data().expiresAt.toMillis() > soon) {
      tx.update(outcome.deck.ref, { expiresAt: Timestamp.fromMillis(soon) });
    }
  }

  return {
    async createRoom(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      const { requestId } = input(request, { requestId: REQUEST_ID });
      await limit(actor.uid, 'create', 10, 3600000);
      const receipt = db.doc(`_requests/${digest(`${actor.uid}:${requestId}`)}`);
      const roomId = randomBytes(12).toString('hex').toUpperCase();
      for (let attempt = 0; attempt < 3; attempt++) {
        const joinCode = newJoinCode();
        const created = await db.runTransaction(async tx => {
          const [previous, taken] = await Promise.all([tx.get(receipt), tx.get(codeRef(joinCode))]);
          if (previous.exists) {
            const existing = await tx.get(roomRef(previous.data().roomId));
            return { roomId: existing.id, joinCode: existing.data()?.joinCode ?? null };
          }
          if (taken.exists) return null;
          const expiresAt = expiry(ROOM_TTL_MS);
          const room = roomRef(roomId);
          tx.create(room, { creator: actor.uid, status: 'lobby', memberCount: 1, joinCode,
            createdAt: FieldValue.serverTimestamp(), expiresAt });
          tx.create(room.collection('members').doc(actor.uid), { uid: actor.uid, active: true,
            joinedAt: FieldValue.serverTimestamp(), expiresAt });
          tx.create(codeRef(joinCode), { roomId, expiresAt });
          tx.create(receipt, { roomId, uidHash: digest(actor.uid), expiresAt: expiry(RECEIPT_TTL_MS) });
          return { roomId, joinCode };
        });
        if (created) return created;
      }
      throw new HttpsError('unavailable', 'Please try again.');
    },

    async joinRoom(request) {
      const actor = identity(request);
      // Failed attempts also count; missing, closed and revoked rooms share one response.
      await limit(actor.uid, 'join', 10, 60000);
      const { joinCode, roomId: knownRoom } = input(request, { joinCode: CODE }, { roomId: ROOM_ID });
      return db.runTransaction(async tx => {
        let roomId = knownRoom;
        if (joinCode) {
          const code = await tx.get(codeRef(joinCode));
          if (!code.exists || code.data().expiresAt.toMillis() <= now()) deny();
          roomId = code.data().roomId;
        }
        const room = roomRef(roomId);
        const member = room.collection('members').doc(actor.uid);
        const [snapshot, membership] = await Promise.all([tx.get(room), tx.get(member)]);
        if (!snapshot.exists) deny();
        const state = stateOf(snapshot);
        if (state.expiresAt <= now()) deny();
        if (membership.exists) {
          if (membership.data().active !== true) deny();
          return { roomId };
        }
        // The internal room ID only reconnects existing members; joining needs the current code.
        if (!joinCode || state.joinCode !== joinCode || !authorize('join', actor, state)) deny();
        // Only someone holding the current code learns that the room is full.
        if (state.memberCount >= CAPACITY) {
          throw new HttpsError('failed-precondition', 'Room is full.', { reason: 'room-full', capacity: CAPACITY });
        }
        tx.create(member, { uid: actor.uid, active: true, joinedAt: FieldValue.serverTimestamp(),
          expiresAt: snapshot.data().expiresAt });
        tx.update(room, { memberCount: state.memberCount + 1 });
        return { roomId };
      });
    },

    async startRoom(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      const { roomId, search } = searchInput(request, 'roomId', ROOM_ID);
      await limit(actor.uid, 'start', 10, 60000);
      return generation.generateDeck({ uid: actor.uid, mode: 'room', targetId: roomId, search, target: {
        async check(tx) {
          const { room, snapshot, state } = await memberView(tx, roomId, actor.uid);
          if (state.creator !== actor.uid) deny();
          if (state.status !== 'lobby') return { done: startedView(roomId, state) };
          if (!authorize('start', actor, state, true)) deny();
          return { ready: { room, snapshot, state } };
        },
        commit(tx, deck, built, { room, snapshot, state }) {
          const roomExpiry = snapshot.data().expiresAt.toMillis();
          tx.update(room, { status: 'voting', deckId: deck.id, candidateCount: built.candidates.length,
            joinCode: FieldValue.delete(), startedAt: FieldValue.serverTimestamp(),
            votingEndsAt: expiry(VOTING_WINDOW_MS) });
          if (state.joinCode) tx.delete(codeRef(state.joinCode));
          // The cards come back with the start, so the host need not read the deck.
          return { view: { roomId, deckId: deck.id, candidateCount: built.candidates.length,
            candidates: built.candidates.map(storedCandidate) },
            expiresAt: Timestamp.fromMillis(Math.min(roomExpiry, now() + VOTING_WINDOW_MS + DECK_AFTER_VOTING_MS)) };
        },
      } });
    },

    // One live deck for one person, revealed a card at a time. The request ID
    // names the pick, so a retried call returns it instead of searching again.
    async createQuickPick(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      const { requestId, search } = searchInput(request, 'requestId', REQUEST_ID);
      await limit(actor.uid, 'quickPick', 10, 60000);
      const quickPickId = digest(`${actor.uid}:${requestId}`).slice(0, 24);
      const ref = quickPickRef(quickPickId);
      return generation.generateDeck({ uid: actor.uid, mode: 'quickPick', targetId: quickPickId, search, target: {
        async check(tx) {
          const existing = await tx.get(ref);
          if (!existing.exists) return { ready: null };
          if (existing.data().ownerUid !== actor.uid || existing.data().expiresAt.toMillis() <= now()) deny();
          return { done: quickPickView(quickPickId, existing.data()) };
        },
        commit(tx, deck, built) {
          const data = { ownerUid: actor.uid, deckId: deck.id, order: shuffled(built.candidates.map(c => c.id)),
            position: 0, rerollsUsed: 0, createdAt: FieldValue.serverTimestamp(), expiresAt: expiry(QUICK_PICK_MS) };
          tx.create(ref, data);
          return { view: quickPickView(quickPickId, data), expiresAt: data.expiresAt };
        },
      } });
    },

    // Shows the next card from the same deck: no search and no charge. `from` is
    // the position the app was showing, so a retried reroll does not skip a card.
    async rerollQuickPick(request) {
      const actor = identity(request);
      const { quickPickId, from } = rerollInput(request);
      await limit(actor.uid, 'reroll', 30, 60000);
      return db.runTransaction(async tx => {
        const ref = quickPickRef(quickPickId);
        const snapshot = await tx.get(ref);
        const data = snapshot.data();
        if (!snapshot.exists || data.ownerUid !== actor.uid || data.expiresAt.toMillis() <= now()) deny();
        if (data.position !== from) return quickPickView(quickPickId, data);
        if (quickPickView(quickPickId, data).rerollsLeft === 0) {
          throw new HttpsError('failed-precondition', 'No rerolls left.', { reason: 'no-rerolls' });
        }
        const next = { ...data, position: data.position + 1, rerollsUsed: data.rerollsUsed + 1 };
        tx.update(ref, { position: next.position, rerollsUsed: next.rerollsUsed });
        return quickPickView(quickPickId, next);
      });
    },

    // Remaining live searches this week, when they reset, and whether live
    // search is paused. Guests and unverified accounts cannot search at all.
    async liveSearchStatus(request) {
      const actor = identity(request);
      input(request, {});
      await limit(actor.uid, 'status', 30, 60000);
      if (!authorize('create', actor)) return { eligible: false };
      return { eligible: true, ...(await generation.allowance(actor.uid)) };
    },

    async closeRoom(request) {
      const actor = identity(request);
      const { roomId } = input(request, { roomId: ROOM_ID });
      await limit(actor.uid, 'close', 30, 60000);
      return db.runTransaction(async tx => {
        const { room, state } = await memberView(tx, roomId, actor.uid);
        if (state.creator !== actor.uid) deny();
        if (state.status === 'closed') return { roomId, status: 'closed', results: state.results ?? null };
        const outcome = state.status === 'voting' ? await tally(tx, room, state) : null;
        closeInto(tx, room, state, outcome);
        return { roomId, status: 'closed', results: outcome?.results ?? null };
      });
    },

    // Members ask for results; the room closes itself here once everyone has voted
    // on every candidate or the voting window has passed, so no scheduler is needed.
    async roomResults(request) {
      const actor = identity(request);
      const { roomId } = input(request, { roomId: ROOM_ID });
      await limit(actor.uid, 'results', 60, 60000);
      return db.runTransaction(async tx => {
        const { room, state } = await memberView(tx, roomId, actor.uid);
        if (state.status === 'closed') return { roomId, status: 'closed', results: state.results ?? null };
        if (state.status !== 'voting') return { roomId, status: state.status, results: null };
        const outcome = await tally(tx, room, state);
        const ended = state.votingEndsAt && state.votingEndsAt.toMillis() <= now();
        if (!outcome.complete && !ended) {
          return { roomId, status: 'voting', results: null, voters: outcome.results.voters };
        }
        closeInto(tx, room, state, outcome);
        return { roomId, status: 'closed', results: outcome.results };
      });
    },

    // Scheduled: closes rooms whose voting ended with nobody asking for results,
    // deletes expired decks and settles deck generations that never finished.
    // TTL deletion can lag by a day; this does not.
    async sweep() {
      let closed = 0;
      const stale = await db.collection('rooms').where('status', '==', 'voting')
        .where('votingEndsAt', '<=', Timestamp.fromMillis(now())).limit(SWEEP_BATCH).get();
      for (const snapshot of stale.docs) {
        closed += await retryTransient(() => db.runTransaction(async tx => {
          const current = await tx.get(snapshot.ref);
          const state = current.exists ? stateOf(current) : null;
          if (state?.status !== 'voting' || !(state.votingEndsAt?.toMillis() <= now())) return 0;
          closeInto(tx, current.ref, state, await tally(tx, current.ref, state));
          return 1;
        }));
      }
      const expired = await db.collection('restaurantDecks').where('expiresAt', '<=', Timestamp.fromMillis(now()))
        .limit(SWEEP_BATCH).get();
      if (!expired.empty) {
        await retryTransient(async () => {
          const batch = db.batch();
          expired.forEach(deck => batch.delete(deck.ref));
          await batch.commit();
        });
      }
      const leasesSettled = await generation.reconcile();
      log({ event: 'rooms_swept', roomsClosed: closed, decksDeleted: expired.size, leasesSettled });
      return { roomsClosed: closed, decksDeleted: expired.size, leasesSettled };
    },

    async revokeMember(request) {
      const actor = identity(request);
      const { roomId, memberUid } = input(request, { roomId: ROOM_ID, memberUid: UID });
      await limit(actor.uid, 'revoke', 30, 60000);
      if (memberUid === actor.uid) deny();
      return db.runTransaction(async tx => {
        const { room, state } = await memberView(tx, roomId, actor.uid);
        if (state.creator !== actor.uid || state.status === 'closed') deny();
        const member = room.collection('members').doc(memberUid);
        const membership = await tx.get(member);
        if (!membership.exists) deny();
        if (membership.data().active === true) {
          tx.update(member, { active: false });
          tx.update(room, { memberCount: Math.max(1, state.memberCount - 1) });
        }
        return { roomId };
      });
    },

    async rotateJoinCode(request) {
      const actor = identity(request);
      const { roomId } = input(request, { roomId: ROOM_ID });
      await limit(actor.uid, 'rotate', 10, 60000);
      for (let attempt = 0; attempt < 3; attempt++) {
        const joinCode = newJoinCode();
        const rotated = await db.runTransaction(async tx => {
          const { room, snapshot, state } = await memberView(tx, roomId, actor.uid);
          if (state.creator !== actor.uid || state.status !== 'lobby') deny();
          if ((await tx.get(codeRef(joinCode))).exists) return null;
          if (state.joinCode) tx.delete(codeRef(state.joinCode));
          tx.create(codeRef(joinCode), { roomId, expiresAt: snapshot.data().expiresAt });
          tx.update(room, { joinCode });
          return { roomId, joinCode };
        });
        if (rotated) return rotated;
      }
      throw new HttpsError('unavailable', 'Please try again.');
    },

    async deleteAccount(request) {
      const actor = identity(request);
      input(request, {});
      if (actor.provider !== 'anonymous' &&
        !(Number.isFinite(actor.authTime) && now() / 1000 - actor.authTime <= RECENT_SIGN_IN_SECONDS)) {
        throw new HttpsError('failed-precondition', 'Sign in again before deleting your account.');
      }
      await limit(actor.uid, 'delete', 5, 3600000);
      // Every step is safe to repeat, so a deletion that fails part way is
      // completed by retrying it rather than leaving data or the Auth user behind.
      const hosted = await db.collection('rooms').where('creator', '==', actor.uid).get();
      for (const room of hosted.docs) {
        await retryTransient(async () => {
          const batch = db.batch();
          batch.update(room.ref, { status: 'closed', closedAt: FieldValue.serverTimestamp(),
            expiresAt: Timestamp.fromMillis(now()), joinCode: FieldValue.delete() });
          if (room.data().joinCode) batch.delete(codeRef(room.data().joinCode));
          await batch.commit();
        });
      }
      const hostedIds = new Set(hosted.docs.map(room => room.id));
      const memberships = await db.collectionGroup('members').where('uid', '==', actor.uid).get();
      for (const membership of memberships.docs) {
        const room = membership.ref.parent.parent;
        // A transaction rereads the membership, so a repeat never decrements twice.
        await retryTransient(() => db.runTransaction(async tx => {
          const [current, ballots] = await Promise.all([tx.get(membership.ref),
            tx.get(room.collection('votes').doc(actor.uid).collection('ballot'))]);
          ballots.forEach(ballot => tx.delete(ballot.ref));
          if (!current.exists) return;
          tx.delete(membership.ref);
          if (current.data().active === true && !hostedIds.has(room.id)) {
            tx.update(room, { memberCount: FieldValue.increment(-1) });
          }
        }));
      }
      const decks = await db.collection('restaurantDecks').where('ownerUid', '==', actor.uid).get();
      const quickPicks = await db.collection('quickPicks').where('ownerUid', '==', actor.uid).get();
      for (const records of [decks, quickPicks]) {
        if (records.empty) continue;
        await retryTransient(async () => {
          const batch = db.batch();
          records.forEach(record => batch.delete(record.ref));
          await batch.commit();
        });
      }
      // Receipts, weekly usage and generation leases are tied to the person
      // only through a hash of their UID.
      for (const collection of ['_requests', 'usageWeeks', 'deckGenerations']) {
        const records = await db.collection(collection).where('uidHash', '==', digest(actor.uid)).get();
        if (records.empty) continue;
        await retryTransient(async () => {
          const batch = db.batch();
          records.forEach(record => batch.delete(record.ref));
          await batch.commit();
        });
      }
      try {
        await deleteAuthUser(actor.uid);
      } catch (error) {
        if (error?.code !== 'auth/user-not-found') throw error;
      }
      // No UID, email or ballot content in the record.
      log({ event: 'account_deleted', hostedRooms: hosted.size, memberships: memberships.size, decks: decks.size });
      return { deleted: true };
    },
  };
}

const CALLABLES = ['createRoom', 'joinRoom', 'startRoom', 'closeRoom', 'roomResults',
  'revokeMember', 'rotateJoinCode', 'deleteAccount', 'liveSearchStatus', 'createQuickPick', 'rerollQuickPick'];

module.exports = { createRoomHandlers, CALLABLES, CODE_ALPHABET, CAPACITY };
