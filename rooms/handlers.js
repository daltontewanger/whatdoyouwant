// Room callables shared by the deployed codebase and the local emulator entry.
// Firebase modules are injected so each entry can supply its own copies.
const { randomBytes, randomInt, createHash } = require('node:crypto');
const { authorize, isRegistered } = require('./authorization');
const { createMetrics, roomCounts, parseRange, monthOf, CLIENT_EVENTS, PLATFORMS } = require('./metrics');
const { parseSearchRequest, InvalidSearchRequest, UnknownZip } = require('./search/request');
const { assertProvider } = require('./search/provider');
const { createFakeProvider } = require('./search/fake-provider');
const { resultCard, storedCandidate, ownListDeckDocument } = require('./decks');
const { createClientErrorReporter } = require('./client-errors');
const { parseOwnList, InvalidList } = require('./own-list');
const { parsePlaces, parseRoomLists, detailsExpireAt, withoutStaleDetails, InvalidPlaces } = require('./place-lists');
const { createGeneration } = require('./generation');
const { clientNetwork, createNetworkWindow, MODES } = require('./ip-limits');
const { parseReport, reportable, InvalidReport, KINDS, REPORT_WINDOW_MS, HIDDEN_MS, FLAG_DETAILS_MS,
  REPORTS_TO_HIDE } = require('./place-reports');
const { parseNickname, InvalidNickname, BlockedNickname } = require('./nickname');

const ROOM_TTL_MS = 24 * 3600000;
const VOTING_WINDOW_MS = 30 * 60000;
// Calls per network per minute on one server instance, across every callable.
const NETWORK_CALLS_PER_MINUTE = 120;
// Provider decks are kept only as long as a vote needs them: until 30 minutes
// after voting ends, or 15 minutes after the room closes, whichever is sooner.
// The winner and backup are copied onto the room's results first.
const DECK_AFTER_VOTING_MS = 30 * 60000;
const DECK_AFTER_CLOSE_MS = 15 * 60000;
// A member who has not voted by hand for this long is counted out: their
// remaining cards count as No and the room stops waiting for them. Votes the
// app casts when a card's time runs out do not count as taking part.
const AWAY_MS = 3 * 60000;
// The host may finish without people who have not voted by hand for this
// long, once they are the only ones left; the server checks it, not the app.
const INACTIVE_MS = 60000;
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
// Members are listed on the room under a random seat, never their UID.
const newSeat = () => randomBytes(6).toString('hex');
const newJoinCode = () => Array.from({ length: 6 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join('');

function createRoomHandlers({ db, FieldValue, Timestamp, HttpsError, deleteAuthUser,
  now = () => Date.now(), provider = createFakeProvider(), newSeed = () => randomBytes(16).toString('hex'),
  log = () => {}, logError = log,
  // Emulators and tests accept every domain, so local sign-ups (example.test)
  // work offline; the deployed entry supplies the real DNS check.
  canReceiveMail = async () => true,
  // SHA-256 of the lowercased Google addresses that may read the insights.
  insightsOwners = [],
  // When an account was created (ms), for the smaller allowance new accounts get.
  accountCreatedAt = async () => null,
  // Per-network limits: 'off', 'log' (count and log what would be refused) or 'enforce'.
  networkLimits = 'off' }) {
  assertProvider(provider);
  if (!MODES.includes(networkLimits)) throw new Error(`Unknown network limit mode: ${networkLimits}`);
  const deny = () => { throw new HttpsError('permission-denied', 'Room action unavailable.'); };
  const invalid = () => { throw new HttpsError('invalid-argument', 'Invalid request.'); };
  const expiry = ms => Timestamp.fromMillis(now() + ms);
  const reportError = createClientErrorReporter({ now, logError, invalid });
  const metrics = createMetrics({ db, FieldValue, Timestamp, now, logError });
  const owners = new Set(insightsOwners);

  function identity(request) {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in first.');
    const token = request.auth.token;
    return { uid: request.auth.uid, provider: token.firebase?.sign_in_provider,
      emailVerified: token.email_verified === true, authTime: token.auth_time,
      email: typeof token.email === 'string' ? token.email : null };
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
    retryTransient, metrics, accountCreatedAt });

  // Every call counts against its network in memory first: free, and it stops
  // a flood before any database work. Generous enough for a busy shared network.
  const networkWindow = createNetworkWindow({ now, perMinute: NETWORK_CALLS_PER_MINUTE });
  const logged = new Map();
  // At most one log line per event and action per minute, so a flood can't flood the logs.
  function logOnce(entry) {
    const key = `${entry.event}:${entry.action}`;
    const minute = Math.floor(now() / 60000);
    if (logged.get(key) === minute) return;
    if (logged.size > 200) logged.clear();
    logged.set(key, minute);
    log(entry);
  }
  function refuseNetwork(action, scope) {
    if (networkLimits === 'enforce') throw new HttpsError('resource-exhausted', 'Please wait before trying again.');
    logOnce({ event: 'network_limit_reached', action, scope, mode: networkLimits });
  }
  function checkNetwork(request, action) {
    if (networkLimits === 'off') return null;
    const { network, entries } = clientNetwork(request.rawRequest);
    if (!network) return null;
    // While limits only log, a short hash shows which address was used, to be
    // compared with the platform's request logs; never the address itself.
    if (networkLimits === 'log') {
      logOnce({ event: 'network_seen', action, forwardedEntries: entries, networkHash: digest(network).slice(0, 12) });
    }
    if (!networkWindow(network)) refuseNetwork(action, 'minute');
    return network;
  }
  // Stored counts for the actions worth limiting across all server instances.
  async function limitNetwork(request, action, maximum, period) {
    const network = request.network;
    if (!network) return;
    try {
      await limit(`network:${network}`, action, maximum, period);
    } catch (error) {
      if (!(error instanceof HttpsError) || error.code !== 'resource-exhausted') throw error;
      refuseNetwork(action, 'stored');
    }
  }

  // Only the owner's own Google sign-in reads the insights.
  const ownsInsights = actor => actor.provider === 'google.com' && actor.emailVerified && actor.email !== null &&
    owners.has(digest(actor.email.trim().toLowerCase()));

  // A target ID plus one search request. The search is parsed by its own
  // strict contract; its origin is used for this call and never kept. Fields
  // named in `optional` may also be present; the caller checks them.
  function searchInput(request, name, pattern, optional = []) {
    const value = request.data ?? {};
    const keys = typeof value === 'object' && !Array.isArray(value) ? Object.keys(value) : null;
    if (!keys || !keys.includes(name) || !keys.includes('search') ||
      !keys.every(key => [name, 'search', ...optional].includes(key)) || typeof value[name] !== 'string' ||
      !pattern.test(value[name])) {
      invalid();
    }
    try {
      return { ...value, search: parseSearchRequest(value.search) };
    } catch (error) {
      if (error instanceof UnknownZip) {
        throw new HttpsError('invalid-argument', 'Unknown ZIP code.', { reason: 'unknown-zip' });
      }
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
  const placesRef = uid => db.doc(`userPlaces/${uid}`);
  const profileRef = uid => db.doc(`userProfiles/${uid}`);
  // Only verified accounts have a nickname; guests always show as one of the guests.
  const nicknameOf = async (tx, actor) => {
    if (!authorize('create', actor)) return null;
    const profile = await tx.get(profileRef(actor.uid));
    return profile.exists ? profile.data().nickname ?? null : null;
  };
  const expiresField = at => (at === null ? FieldValue.delete() : Timestamp.fromMillis(at));

  // The lists active members shared for this room, as the host's switches
  // allow; places someone reported closed are left out either way. Read
  // before the deck is built; anything shared later misses it.
  async function roomLists(roomId, use) {
    const room = roomRef(roomId);
    const [members, lists] = await Promise.all([room.collection('members').where('active', '==', true).get(),
      room.collection('lists').get()]);
    const active = new Set(members.docs.map(member => member.id));
    const counted = lists.docs.filter(list => active.has(list.id));
    return {
      lists: {
        never: use.never ? counted.flatMap(list => list.data().never) : [],
        closed: counted.flatMap(list => list.data().closed ?? []),
        favorites: use.favorites ? counted.map(list => list.data().favorites) : [],
      },
      shared: lists.docs.map(list => list.ref),
    };
  }
  const quickPickView = (quickPickId, data) => ({ quickPickId, deckId: data.deckId, position: data.position,
    candidateId: data.order[data.position],
    rerollsLeft: Math.max(0, Math.min(MAX_REROLLS - data.rerollsUsed, data.order.length - 1 - data.position)) });

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

  // The winner or backup a member of this room was shown, if that is
  // `cardId`. Closed rooms count; their results last as long as the room.
  async function shownInRoom(tx, roomId, uid, cardId) {
    const room = roomRef(roomId);
    const [snapshot, membership] = await Promise.all([tx.get(room), tx.get(room.collection('members').doc(uid))]);
    if (!snapshot.exists || !membership.exists || membership.data().active !== true) deny();
    const state = stateOf(snapshot);
    if (state.expiresAt <= now() || state.status !== 'closed') deny();
    const { results } = state;
    if (results?.winner === cardId) return results.winnerCard;
    if (results?.backup === cardId) return results.backupCard;
    return deny();
  }

  // A card the person's own Quick Pick has revealed so far.
  async function shownInPick(tx, quickPickId, uid, cardId) {
    const pick = await tx.get(quickPickRef(quickPickId));
    const data = pick.data();
    if (!pick.exists || data.ownerUid !== uid || data.expiresAt.toMillis() <= now()) deny();
    const index = data.order.indexOf(cardId);
    if (index < 0 || index > data.position) deny();
    const deck = await tx.get(deckRef(data.deckId));
    return deck.data()?.candidates?.find(candidate => candidate.id === cardId) ?? deny();
  }

  // Puts the member's current name on the room's roster. Rooms made before
  // rosters existed give the member a seat the first time.
  function seatIn(tx, room, state, member, membership, name) {
    const seat = membership.seat ?? newSeat();
    const listed = state.roster?.[seat];
    if (listed && listed.name === name) return;
    if (!membership.seat) tx.update(member, { seat });
    tx.update(room, { [`roster.${seat}`]: { name, host: state.creator === membership.uid } });
  }

  const unseated = membership => (membership.seat ? { [`roster.${membership.seat}`]: FieldValue.delete() } : {});

  // Who is still voting, for the host's waiting screen: roster names (already
  // shown to everyone in the room), never account IDs. People who are done
  // come last.
  function progressView(state, outcome) {
    const people = outcome.progress.map(person => {
      const listed = person.seat ? state.roster?.[person.seat] : null;
      return { name: listed?.name ?? null, host: person.uid === state.creator, votes: person.votes,
        total: outcome.total, done: person.done, inactiveSeconds: Math.floor(person.inactiveMs / 1000) };
    });
    return people.sort((a, b) => Number(a.done) - Number(b.done) || Number(b.host) - Number(a.host));
  }

  async function tally(tx, room, state, { awayAfter = AWAY_MS } = {}) {
    const [members, deck] = await Promise.all([
      tx.get(room.collection('members').where('active', '==', true)),
      state.deckId ? tx.get(deckRef(state.deckId)) : null,
    ]);
    const deckData = deck?.exists ? deck.data() : null;
    const deckIds = deckData?.candidateIds ?? [];
    const likes = Object.fromEntries(deckIds.map(id => [id, 0]));
    let voters = 0;
    let countedOut = 0;
    let complete = true;
    const stats = { ballots: 0, liked: 0, timedOut: 0 };
    const progress = [];
    const startedAt = state.startedAt?.toMillis?.() ?? null;
    const total = state.candidateCount ?? deckIds.length;
    for (const member of members.docs) {
      const ballots = await tx.get(room.collection('votes').doc(member.id).collection('ballot'));
      if (!ballots.empty) voters++;
      const lastByHand = Math.max(startedAt ?? 0, ...ballots.docs.filter(ballot => ballot.data().auto !== true)
        .map(ballot => ballot.data().at?.toMillis?.() ?? 0));
      const away = startedAt !== null && now() - lastByHand >= awayAfter;
      const done = ballots.size >= total;
      if (!done && !away) complete = false;
      if (!done && away) countedOut++;
      progress.push({ seat: member.data().seat ?? null, uid: member.id, votes: Math.min(ballots.size, total), done,
        inactiveMs: startedAt === null ? 0 : Math.max(0, now() - lastByHand) });
      for (const ballot of ballots.docs) {
        if (ballot.data().liked === true && ballot.id in likes) likes[ballot.id]++;
        stats.ballots++;
        if (ballot.data().liked === true) stats.liked++;
        if (ballot.data().auto === true) stats.timedOut++;
      }
    }
    // Most likes wins; deck order (best ranked first) breaks ties.
    const ranking = [...deckIds].sort((a, b) => likes[b] - likes[a]);
    const card = id => resultCard(deckData?.candidates?.find(candidate => candidate.id === id));
    const winner = ranking[0] ?? null;
    const backup = ranking[1] ?? null;
    return { complete, deck: deck?.exists ? deck : null, stats, progress, total,
      winnerCandidate: deckData?.candidates?.find(candidate => candidate.id === winner) ?? null,
      results: { likes, winner, backup, voters, winnerCard: card(winner), backupCard: card(backup),
        // How many stopped voting and were finished without (a count only).
        ...(countedOut ? { countedOut } : {}) } };
  }

  // Closing keeps the result on the room and lets the deck go shortly after.
  // Returns what the close adds to the usage counts, recorded once the
  // transaction has committed.
  function closeInto(tx, room, state, outcome) {
    tx.update(room, { status: 'closed', closedAt: FieldValue.serverTimestamp(), joinCode: FieldValue.delete(),
      ...(outcome?.results ? { results: outcome.results } : {}) });
    if (state.joinCode) tx.delete(codeRef(state.joinCode));
    const soon = now() + DECK_AFTER_CLOSE_MS;
    if (outcome?.deck && outcome.deck.data().expiresAt.toMillis() > soon) {
      tx.update(outcome.deck.ref, { expiresAt: Timestamp.fromMillis(soon) });
    }
    const winner = outcome?.winnerCandidate ?? null;
    return {
      // Voting started a fixed window before its deadline; both use the same clock as now().
      counts: roomCounts({ outcome, stats: outcome?.stats, at: now(), winner,
        startedAt: state.votingEndsAt?.toMillis ? state.votingEndsAt.toMillis() - VOTING_WINDOW_MS : null }),
      win: winner ? { cardId: winner.id, voters: outcome.results.voters,
        likes: outcome.results.likes[winner.id] ?? 0 } : null,
    };
  }

  async function afterClose(closed) {
    if (!closed) return;
    await metrics.add(closed.counts);
    if (closed.win) await metrics.recordWin(closed.win);
  }

  const callables = {
    async createRoom(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      const { requestId } = input(request, { requestId: REQUEST_ID });
      await limit(actor.uid, 'create', 10, 3600000);
      await limitNetwork(request, 'create', 30, 3600000);
      const receipt = db.doc(`_requests/${digest(`${actor.uid}:${requestId}`)}`);
      const roomId = randomBytes(12).toString('hex').toUpperCase();
      for (let attempt = 0; attempt < 3; attempt++) {
        const joinCode = newJoinCode();
        const created = await db.runTransaction(async tx => {
          const [previous, taken, name] = await Promise.all([tx.get(receipt), tx.get(codeRef(joinCode)),
            nicknameOf(tx, actor)]);
          if (previous.exists) {
            const existing = await tx.get(roomRef(previous.data().roomId));
            return { roomId: existing.id, joinCode: existing.data()?.joinCode ?? null, repeat: true };
          }
          if (taken.exists) return null;
          const expiresAt = expiry(ROOM_TTL_MS);
          const room = roomRef(roomId);
          const seat = newSeat();
          tx.create(room, { creator: actor.uid, status: 'lobby', memberCount: 1, joinCode,
            roster: { [seat]: { name, host: true } }, createdAt: FieldValue.serverTimestamp(), expiresAt });
          tx.create(room.collection('members').doc(actor.uid), { uid: actor.uid, active: true, seat,
            joinedAt: FieldValue.serverTimestamp(), expiresAt });
          tx.create(codeRef(joinCode), { roomId, expiresAt });
          tx.create(receipt, { roomId, uidHash: digest(actor.uid), expiresAt: expiry(RECEIPT_TTL_MS) });
          return { roomId, joinCode };
        });
        if (created) {
          if (!created.repeat) await metrics.add({ roomsCreated: 1 });
          return { roomId: created.roomId, joinCode: created.joinCode };
        }
      }
      throw new HttpsError('unavailable', 'Please try again.');
    },

    async joinRoom(request) {
      const actor = identity(request);
      // Failed attempts also count; missing, closed and revoked rooms share one response.
      await limit(actor.uid, 'join', 10, 60000);
      await limitNetwork(request, 'join', 100, 600000);
      const { joinCode, roomId: knownRoom } = input(request, { joinCode: CODE }, { roomId: ROOM_ID });
      const joined = await db.runTransaction(async tx => {
        let roomId = knownRoom;
        if (joinCode) {
          const code = await tx.get(codeRef(joinCode));
          if (!code.exists || code.data().expiresAt.toMillis() <= now()) deny();
          roomId = code.data().roomId;
        }
        const room = roomRef(roomId);
        const member = room.collection('members').doc(actor.uid);
        const [snapshot, membership, name] = await Promise.all([tx.get(room), tx.get(member),
          nicknameOf(tx, actor)]);
        if (!snapshot.exists) deny();
        const state = stateOf(snapshot);
        if (state.expiresAt <= now()) deny();
        if (membership.exists) {
          if (membership.data().active !== true) deny();
          // Reconnecting picks up a nickname changed since joining.
          if (state.status === 'lobby') seatIn(tx, room, state, member, membership.data(), name);
          return { roomId };
        }
        // The internal room ID only reconnects existing members; joining needs the current code.
        if (!joinCode || state.joinCode !== joinCode || !authorize('join', actor, state, false, now())) deny();
        // Only someone holding the current code learns that the room is full.
        if (state.memberCount >= CAPACITY) {
          throw new HttpsError('failed-precondition', 'Room is full.', { reason: 'room-full', capacity: CAPACITY });
        }
        const seat = newSeat();
        tx.create(member, { uid: actor.uid, active: true, seat, joinedAt: FieldValue.serverTimestamp(),
          expiresAt: snapshot.data().expiresAt });
        tx.update(room, { memberCount: state.memberCount + 1, [`roster.${seat}`]: { name, host: false } });
        return { roomId, joined: true };
      });
      if (joined.joined) {
        await metrics.add({ roomJoins: 1, ...(actor.provider === 'anonymous' ? { roomJoinsGuest: 1 } : {}) });
      }
      return { roomId: joined.roomId };
    },

    async startRoom(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      const { roomId, search, lists: use = { favorites: false, never: false } } =
        searchInput(request, 'roomId', ROOM_ID, ['lists']);
      if (!use || typeof use !== 'object' || Object.keys(use).sort().join() !== 'favorites,never' ||
        typeof use.favorites !== 'boolean' || typeof use.never !== 'boolean') {
        invalid();
      }
      await limit(actor.uid, 'start', 10, 60000);
      const { lists, shared } = await roomLists(roomId, use);
      return generation.generateDeck({ uid: actor.uid, mode: 'room', targetId: roomId, search, lists,
        counts: { ...(use.favorites ? { roomsWithFavorites: 1 } : {}), ...(use.never ? { roomsWithNever: 1 } : {}) },
        target: {
        async check(tx) {
          const { room, snapshot, state } = await memberView(tx, roomId, actor.uid);
          if (state.creator !== actor.uid) deny();
          if (state.status !== 'lobby') return { done: startedView(roomId, state) };
          if (!authorize('start', actor, state, true, now())) deny();
          return { ready: { room, snapshot, state } };
        },
        commit(tx, deck, built, { room, snapshot, state }) {
          const roomExpiry = snapshot.data().expiresAt.toMillis();
          tx.update(room, { status: 'voting', deckId: deck.id, candidateCount: built.candidates.length,
            joinCode: FieldValue.delete(), startedAt: FieldValue.serverTimestamp(),
            votingEndsAt: expiry(VOTING_WINDOW_MS) });
          if (state.joinCode) tx.delete(codeRef(state.joinCode));
          // Members' lists are only for building the deck.
          shared.forEach(ref => tx.delete(ref));
          // The cards come back with the start, so the host need not read the deck.
          return { view: { roomId, deckId: deck.id, candidateCount: built.candidates.length,
            candidates: built.candidates.map(storedCandidate),
            ...(built.notices.length ? { notices: built.notices } : {}) },
            expiresAt: Timestamp.fromMillis(Math.min(roomExpiry, now() + VOTING_WINDOW_MS + DECK_AFTER_VOTING_MS)) };
        },
      } });
    },

    // A room from the host's own list: the spots they chose become the deck.
    // No search runs, so no provider call and nothing counts against the week.
    async startRoomFromList(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      const value = request.data ?? {};
      if (typeof value !== 'object' || Array.isArray(value) ||
        Object.keys(value).sort().join() !== 'roomId,spots' || typeof value.roomId !== 'string' ||
        !ROOM_ID.test(value.roomId)) {
        invalid();
      }
      let spots;
      try {
        spots = parseOwnList({ spots: value.spots });
      } catch (error) {
        if (error instanceof InvalidList) invalid();
        throw error;
      }
      if (spots.length < 2) invalid();
      const roomId = value.roomId;
      await limit(actor.uid, 'start', 10, 60000);
      let started = false;
      const view = await db.runTransaction(async tx => {
        started = false;
        const { room, snapshot, state } = await memberView(tx, roomId, actor.uid);
        if (state.creator !== actor.uid) deny();
        if (state.status !== 'lobby') return startedView(roomId, state);
        if (!authorize('start', actor, state, true, now())) deny();
        // Shuffled, so the host's own order does not decide who sees what first.
        const order = [...spots];
        for (let i = order.length - 1; i > 0; i--) {
          const j = randomInt(i + 1);
          [order[i], order[j]] = [order[j], order[i]];
        }
        const deck = db.doc(`restaurantDecks/${randomBytes(12).toString('hex')}`);
        const roomExpiry = snapshot.data().expiresAt.toMillis();
        const expiresAt = Timestamp.fromMillis(Math.min(roomExpiry, now() + VOTING_WINDOW_MS + DECK_AFTER_VOTING_MS));
        const document = ownListDeckDocument({ ownerUid: actor.uid, targetId: roomId, spots: order, expiresAt,
          generatedAt: FieldValue.serverTimestamp() });
        tx.create(deck, document);
        tx.update(room, { status: 'voting', deckId: deck.id, candidateCount: document.candidates.length,
          joinCode: FieldValue.delete(), startedAt: FieldValue.serverTimestamp(),
          votingEndsAt: expiry(VOTING_WINDOW_MS) });
        if (state.joinCode) tx.delete(codeRef(state.joinCode));
        started = true;
        return { roomId, deckId: deck.id, candidateCount: document.candidates.length,
          candidates: document.candidates };
      });
      if (started) await metrics.add({ roomsStartedOwnList: 1 });
      return view;
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
      // A pick never suggests a place on the person's own never list, or one
      // they reported closed.
      const places = (await placesRef(actor.uid).get()).data();
      const never = places?.useNever ? places.never.map(place => place.id) : [];
      const closed = (places?.closed ?? []).map(place => place.id);
      return generation.generateDeck({ uid: actor.uid, mode: 'quickPick', targetId: quickPickId, search,
        lists: { never, closed }, target: {
        async check(tx) {
          const existing = await tx.get(ref);
          if (!existing.exists) return { ready: null };
          if (existing.data().ownerUid !== actor.uid || existing.data().expiresAt.toMillis() <= now()) deny();
          return { done: quickPickView(quickPickId, existing.data()) };
        },
        commit(tx, deck, built) {
          // Deck order is already a fresh random draw within each preference
          // tier, so revealing it in order keeps preferred cuisines first.
          const data = { ownerUid: actor.uid, deckId: deck.id, order: built.candidates.map(c => c.id),
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
      let advanced = false;
      const view = await db.runTransaction(async tx => {
        advanced = false;
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
        advanced = true;
        return quickPickView(quickPickId, next);
      });
      if (advanced) await metrics.add({ quickPickRerolls: 1 });
      return view;
    },

    // Whether this build of the app is too old to use. Purely a courtesy to
    // people on old installs; every callable still validates its own input.
    // Asked before sign-up: can the address's domain receive mail at all?
    // Takes only the domain, so the address itself never reaches the server.
    async checkEmailDomain(request) {
      const actor = identity(request);
      const { domain } = input(request, { domain: /^[^\s@]{1,253}$/ });
      await limit(actor.uid, 'email-domain', 30, 60000);
      return { deliverable: await canReceiveMail(domain) };
    },

    // Any signed-in session, guests included, can report an app error.
    async reportClientError(request) {
      const reported = await reportError(identity(request).uid, request.data);
      await metrics.add({ clientErrors: 1 });
      return reported;
    },

    // A tap the server never sees, from the fixed list in metrics.js. The app
    // sends none when the person has turned usage counts off.
    async countEvent(request) {
      const actor = identity(request);
      const { name } = input(request, { name: /^[A-Za-z]{1,40}$/ });
      if (!CLIENT_EVENTS.includes(name)) invalid();
      await limit(actor.uid, 'countEvent', 300, 3600000);
      await metrics.add({ [`tap_${name}`]: 1 });
      return { counted: true };
    },

    // Daily totals for the owner's insights page, plus the provider ledger
    // and the live search settings they are read against.
    async insightsReport(request) {
      const actor = identity(request);
      if (!ownsInsights(actor)) {
        log({ event: 'insights_denied' });
        deny();
      }
      const range = parseRange(request.data);
      if (!range) invalid();
      await limit(actor.uid, 'insights', 120, 3600000);
      const months = [];
      for (let at = Date.parse(`${range.from.slice(0, 7)}-01`); at <= Date.parse(range.to);) {
        months.push(monthOf(at));
        const next = new Date(at);
        at = Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 1);
      }
      const [days, ledgers, config] = await Promise.all([metrics.report(range.from, range.to),
        db.getAll(...months.map(month => db.doc(`usageMonths/${provider.id}_${month}`))),
        db.doc('config/liveSearch').get()]);
      const live = config.data() ?? {};
      return {
        days,
        months: Object.fromEntries(ledgers.map((ledger, i) => [months[i], {
          providerCalls: (ledger.data()?.callsCompleted ?? 0) + (ledger.data()?.callsReserved ?? 0),
          decks: ledger.data()?.generationsCompleted ?? 0,
        }])),
        live: { enabled: live.enabled === true, weeklyCap: live.weeklyCaps?.free ?? null,
          monthlyCallStop: live.monthlyCallStop ?? null, provider: provider.id },
      };
    },

    // Asked once when the app opens, so it also marks the session active for
    // the day: only dates and yes/no flags, kept with the account.
    async appStatus(request) {
      const actor = identity(request);
      const value = request.data ?? {};
      const keys = typeof value === 'object' && value !== null && !Array.isArray(value)
        ? Object.keys(value).sort().join() : '';
      if (!['build', 'build,platform'].includes(keys) ||
        !Number.isInteger(value.build) || value.build < 0 || value.build > 1e9 ||
        (value.platform !== undefined && !PLATFORMS.includes(value.platform))) {
        invalid();
      }
      const [config] = await Promise.all([db.doc('config/liveSearch').get(),
        metrics.recordActivity({ uid: actor.uid, registered: isRegistered(actor), platform: value.platform,
          build: value.build })]);
      const minimum = config.data()?.minimumClientBuild;
      return { updateRequired: Number.isInteger(minimum) && value.build < minimum };
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

    // Whether this member votes without a card timer, for a screen reader or
    // by their own choice. The room learns only that someone does, never who
    // or why, so the lobby can say voting may take longer.
    async setNoTimer(request) {
      const actor = identity(request);
      const value = request.data ?? {};
      if (typeof value !== 'object' || Array.isArray(value) ||
        Object.keys(value).sort().join() !== 'noTimer,roomId' || typeof value.roomId !== 'string' ||
        !ROOM_ID.test(value.roomId) || typeof value.noTimer !== 'boolean') {
        invalid();
      }
      await limit(actor.uid, 'noTimer', 30, 60000);
      return db.runTransaction(async tx => {
        const { room, state } = await memberView(tx, value.roomId, actor.uid);
        if (state.status === 'closed') return { untimed: state.untimed === true };
        const others = await tx.get(room.collection('members').where('active', '==', true)
          .where('noTimer', '==', true));
        const untimed = value.noTimer || others.docs.some(member => member.id !== actor.uid);
        tx.update(room.collection('members').doc(actor.uid), { noTimer: value.noTimer });
        if ((state.untimed === true) !== untimed) tx.update(room, { untimed });
        return { untimed };
      });
    },

    // A verified account's nickname, shown to people in the same room. An
    // empty one clears it. Lobbies the person is waiting in show the change.
    async setNickname(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      const value = request.data ?? {};
      if (typeof value !== 'object' || Array.isArray(value) || Object.keys(value).join() !== 'nickname') invalid();
      await limit(actor.uid, 'nickname', 20, 3600000);
      let nickname;
      try {
        nickname = parseNickname(value.nickname);
      } catch (error) {
        if (error instanceof InvalidNickname) {
          throw new HttpsError('invalid-argument', 'Invalid nickname.', { reason: 'nickname-format' });
        }
        if (error instanceof BlockedNickname) {
          throw new HttpsError('invalid-argument', 'Nickname not allowed.', { reason: 'nickname-blocked' });
        }
        throw error;
      }
      if (nickname) {
        await profileRef(actor.uid).set({ nickname, updatedAt: FieldValue.serverTimestamp() });
      } else {
        await profileRef(actor.uid).delete();
      }
      const name = nickname || null;
      const memberships = await db.collectionGroup('members').where('uid', '==', actor.uid).get();
      for (const membership of memberships.docs) {
        if (membership.data().active !== true) continue;
        const room = membership.ref.parent.parent;
        await retryTransient(() => db.runTransaction(async tx => {
          const [snapshot, current] = await Promise.all([tx.get(room), tx.get(membership.ref)]);
          if (!snapshot.exists || !current.exists || current.data().active !== true) return;
          const state = stateOf(snapshot);
          if (state.status !== 'lobby' || state.expiresAt <= now()) return;
          seatIn(tx, room, state, membership.ref, current.data(), name);
        }));
      }
      return { nickname: name };
    },

    async closeRoom(request) {
      const actor = identity(request);
      const { roomId } = input(request, { roomId: ROOM_ID });
      await limit(actor.uid, 'close', 30, 60000);
      let closed = null;
      const view = await db.runTransaction(async tx => {
        closed = null;
        const { room, state } = await memberView(tx, roomId, actor.uid);
        if (state.creator !== actor.uid) deny();
        if (state.status === 'closed') return { roomId, status: 'closed', results: state.results ?? null };
        const outcome = state.status === 'voting' ? await tally(tx, room, state) : null;
        closed = closeInto(tx, room, state, outcome);
        return { roomId, status: 'closed', results: outcome?.results ?? null };
      });
      await afterClose(closed);
      return view;
    },

    // Members ask for results; the room closes itself here once everyone has voted
    // on every candidate or the voting window has passed, so no scheduler is needed.
    async roomResults(request) {
      const actor = identity(request);
      const { roomId, view: look, finish } = input(request, { roomId: ROOM_ID }, { roomId: ROOM_ID, view: /^room$/ },
        { roomId: ROOM_ID, finish: /^inactive$/ });
      await limit(actor.uid, 'results', 60, 60000);
      // A phone's live connection can deliver room changes late. The app then
      // asks for the room as it is now, with the deck once voting has started,
      // over this plain call instead. Nothing is counted or closed here.
      if (look) {
        return db.runTransaction(async tx => {
          const { state } = await memberView(tx, roomId, actor.uid);
          const deck = state.status === 'voting' && state.deckId ? (await tx.get(deckRef(state.deckId))).data() : null;
          return {
            roomId,
            status: state.status,
            results: state.status === 'closed' ? state.results ?? null : null,
            room: {
              status: state.status,
              creator: state.creator,
              memberCount: state.memberCount ?? 1,
              deckId: state.deckId ?? null,
              untimed: state.untimed === true,
              votingEndsAt: state.votingEndsAt ? state.votingEndsAt.toMillis() : null,
              expiresAt: state.expiresAt,
            },
            deck: deck ? { candidates: deck.candidates, ...(deck.notices?.length ? { notices: deck.notices } : {}) } : null,
          };
        });
      }
      let closed = null;
      const view = await db.runTransaction(async tx => {
        closed = null;
        const { room, state } = await memberView(tx, roomId, actor.uid);
        if (state.status === 'closed') return { roomId, status: 'closed', results: state.results ?? null };
        if (state.status !== 'voting') return { roomId, status: state.status, results: null };
        const host = state.creator === actor.uid;
        if (finish && !host) deny();
        const outcome = await tally(tx, room, state, finish ? { awayAfter: INACTIVE_MS } : {});
        const ended = state.votingEndsAt && state.votingEndsAt.toMillis() <= now();
        if (!outcome.complete && !ended) {
          return { roomId, status: 'voting', results: null, voters: outcome.results.voters,
            ...(host ? { progress: progressView(state, outcome) } : {}) };
        }
        if (finish) log({ event: 'finished_without_inactive' });
        closed = closeInto(tx, room, state, outcome);
        return { roomId, status: 'closed', results: outcome.results };
      });
      await afterClose(closed);
      return view;
    },

    // Scheduled: closes rooms whose voting ended with nobody asking for results,
    // deletes expired decks and settles deck generations that never finished.
    // TTL deletion can lag by a day; this does not.
    async sweep() {
      let closed = 0;
      const stale = await db.collection('rooms').where('status', '==', 'voting')
        .where('votingEndsAt', '<=', Timestamp.fromMillis(now())).limit(SWEEP_BATCH).get();
      for (const snapshot of stale.docs) {
        const swept = await retryTransient(() => db.runTransaction(async tx => {
          const current = await tx.get(snapshot.ref);
          const state = current.exists ? stateOf(current) : null;
          if (state?.status !== 'voting' || !(state.votingEndsAt?.toMillis() <= now())) return null;
          return closeInto(tx, current.ref, state, await tally(tx, current.ref, state));
        }));
        if (swept) {
          closed++;
          await afterClose(swept);
        }
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
      // Favorites keep a place's details only while it keeps turning up.
      let detailsDropped = 0;
      const lapsed = await db.collection('userPlaces').where('detailsExpireAt', '<=', Timestamp.fromMillis(now()))
        .limit(SWEEP_BATCH).get();
      for (const snapshot of lapsed.docs) {
        detailsDropped += await retryTransient(() => db.runTransaction(async tx => {
          const current = await tx.get(snapshot.ref);
          if (!current.exists || !(current.data().detailsExpireAt?.toMillis() <= now())) return 0;
          const favorites = withoutStaleDetails(current.data().favorites, now());
          tx.update(snapshot.ref, { favorites, detailsExpireAt: expiresField(detailsExpireAt(favorites)) });
          return 1;
        }));
      }
      // Places hidden as closed keep their name and address for 30 days.
      const flagged = await db.collection('placeFlags').where('detailsExpireAt', '<=', Timestamp.fromMillis(now()))
        .limit(SWEEP_BATCH).get();
      if (!flagged.empty) {
        await retryTransient(async () => {
          const batch = db.batch();
          flagged.forEach(flag => batch.update(flag.ref, { name: FieldValue.delete(), address: FieldValue.delete(),
            detailsExpireAt: FieldValue.delete() }));
          await batch.commit();
        });
      }
      detailsDropped += flagged.size;
      log({ event: 'rooms_swept', roomsClosed: closed, decksDeleted: expired.size, leasesSettled, detailsDropped });
      return { roomsClosed: closed, decksDeleted: expired.size, leasesSettled, detailsDropped };
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
          tx.update(room, { memberCount: Math.max(1, state.memberCount - 1), ...unseated(membership.data()) });
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

    // A verified account's own list for We'll Decide What We Want, replaced
    // whole on each save.
    async saveOwnList(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      let spots;
      try {
        spots = parseOwnList(request.data);
      } catch (error) {
        if (error instanceof InvalidList) invalid();
        throw error;
      }
      await limit(actor.uid, 'ownList', 30, 60000);
      await db.doc(`userLists/${actor.uid}`).set({ spots, updatedAt: FieldValue.serverTimestamp() });
      return { saved: spots.length };
    },

    // A verified account's favorites and never list, replaced whole on each
    // save. Guests keep theirs on the device.
    async saveMyPlaces(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      let places;
      try {
        places = parsePlaces(request.data, now());
      } catch (error) {
        if (error instanceof InvalidPlaces) invalid();
        throw error;
      }
      await limit(actor.uid, 'myPlaces', 30, 60000);
      // An older app sends no closed list; the one already saved stays.
      if (!places.closed) {
        const kept = (await placesRef(actor.uid).get()).data()?.closed ?? [];
        const listed = new Set([...places.favorites, ...places.never].map(place => place.id));
        places.closed = kept.filter(place => !listed.has(place.id));
      }
      const expires = detailsExpireAt(places.favorites);
      await placesRef(actor.uid).set({ ...places, ...(expires === null ? {} : { detailsExpireAt: Timestamp.fromMillis(expires) }),
        updatedAt: FieldValue.serverTimestamp() });
      return { saved: places.favorites.length + places.never.length + places.closed.length };
    },

    // Each member, guests included, shares the card IDs from their own lists
    // while the room waits; the deck is built from them at the start. Nobody
    // else in the room can read them.
    async shareRoomLists(request) {
      const actor = identity(request);
      let shared;
      try {
        shared = parseRoomLists(request.data ?? {});
      } catch (error) {
        if (error instanceof InvalidPlaces) invalid();
        throw error;
      }
      if (typeof shared.roomId !== 'string' || !ROOM_ID.test(shared.roomId)) invalid();
      await limit(actor.uid, 'shareLists', 30, 60000);
      return db.runTransaction(async tx => {
        const { room, snapshot, state } = await memberView(tx, shared.roomId, actor.uid);
        if (state.status !== 'lobby') return { shared: false };
        tx.set(room.collection('lists').doc(actor.uid), { favorites: shared.favorites, never: shared.never,
          closed: shared.closed, expiresAt: snapshot.data().expiresAt });
        return { shared: true };
      });
    },

    // A verified account says a place it was shown is closed or has wrong
    // details. Only the winner or backup of a room the account was in, or a
    // card its own Quick Pick revealed, while that result still exists. Guests
    // hide a closed place on their own device only; their reports do not count.
    async reportPlace(request) {
      const actor = identity(request);
      if (!authorize('create', actor)) deny();
      let report;
      try {
        report = parseReport(request.data);
      } catch (error) {
        if (error instanceof InvalidReport) invalid();
        throw error;
      }
      await limit(actor.uid, 'reportPlace', 10, 24 * 3600000);
      await limitNetwork(request, 'reportPlace', 30, 24 * 3600000);
      const { cardId, kind } = report;
      const entry = db.doc(`placeReports/${cardId}/byAccount/${digest(`${actor.uid}:${kind}`)}`);
      const flagRef = db.doc(`placeFlags/${cardId}`);
      const reported = await retryTransient(() => db.runTransaction(async tx => {
        const card = report.from === 'room' ? await shownInRoom(tx, report.targetId, actor.uid, cardId)
          : await shownInPick(tx, report.targetId, actor.uid, cardId);
        if (!reportable(card, kind)) deny();
        const [previous, others, flag] = await Promise.all([tx.get(entry),
          tx.get(entry.parent.where('kind', '==', kind)), tx.get(flagRef)]);
        const at = now();
        if (previous.exists && previous.data().at.toMillis() > at - REPORT_WINDOW_MS) return { counted: false };
        tx.set(entry, { kind, uidHash: digest(actor.uid), at: Timestamp.fromMillis(at),
          expiresAt: Timestamp.fromMillis(at + REPORT_WINDOW_MS) });
        const recent = others.docs.filter(other => other.id !== entry.id &&
          other.data().at.toMillis() > at - REPORT_WINDOW_MS).length + 1;
        const field = KINDS[kind];
        if (!field || recent < REPORTS_TO_HIDE) return { counted: true, hidden: false };
        const until = at + HIDDEN_MS;
        const longest = Math.max(until, ...Object.values(KINDS).filter(Boolean)
          .map(name => flag.data()?.[name]?.toMillis?.() ?? 0));
        tx.set(flagRef, { [field]: Timestamp.fromMillis(until), expiresAt: Timestamp.fromMillis(longest),
          updatedAt: FieldValue.serverTimestamp(),
          // The owner passes closed places on to HERE by hand; the name and
          // address say which place it was, and go after 30 days.
          ...(kind === 'closed' ? { name: card.name, address: card.address ?? '', hiddenAt: Timestamp.fromMillis(at),
            detailsExpireAt: Timestamp.fromMillis(at + FLAG_DETAILS_MS) } : {}) }, { merge: true });
        log({ event: 'place_hidden', kind });
        return { counted: true, hidden: true };
      }));
      if (reported.counted) {
        await metrics.add({ [`placeReports_${kind}`]: 1, ...(reported.hidden ? { placesHidden: 1 } : {}) });
      }
      return { counted: reported.counted };
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
          tx.delete(room.collection('lists').doc(actor.uid));
          if (!current.exists) return;
          tx.delete(membership.ref);
          if (current.data().active === true && !hostedIds.has(room.id)) {
            tx.update(room, { memberCount: FieldValue.increment(-1), ...unseated(current.data()) });
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
      // Place reports stop counting once the account is gone.
      const reports = await db.collectionGroup('byAccount').where('uidHash', '==', digest(actor.uid)).get();
      if (!reports.empty) {
        await retryTransient(async () => {
          const batch = db.batch();
          reports.forEach(record => batch.delete(record.ref));
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
      await retryTransient(() => db.doc(`userSettings/${actor.uid}`).delete());
      await retryTransient(() => db.doc(`userLists/${actor.uid}`).delete());
      await retryTransient(() => placesRef(actor.uid).delete());
      await retryTransient(() => profileRef(actor.uid).delete());
      await retryTransient(() => db.doc(`userActivity/${actor.uid}`).delete());
      try {
        await deleteAuthUser(actor.uid);
      } catch (error) {
        if (error?.code !== 'auth/user-not-found') throw error;
      }
      // No UID, email or ballot content in the record.
      log({ event: 'account_deleted', hostedRooms: hosted.size, memberships: memberships.size, decks: decks.size });
      await metrics.add({ [actor.provider === 'anonymous' ? 'guestsDeleted' : 'accountsDeleted']: 1 });
      return { deleted: true };
    },
  };

  // Each callable first passes the network check; the network rides along on
  // the request for the stored limits above. Scheduled work such as the sweep
  // has no caller and is left as it is.
  const guarded = { ...callables };
  for (const name of CALLABLES) {
    const handler = callables[name];
    guarded[name] = async request => {
      const network = request ? checkNetwork(request, name) : null;
      return handler(network ? { ...request, network } : request);
    };
  }
  return guarded;
}

const CALLABLES = ['createRoom', 'joinRoom', 'startRoom', 'closeRoom', 'roomResults',
  'revokeMember', 'rotateJoinCode', 'deleteAccount', 'liveSearchStatus', 'createQuickPick', 'rerollQuickPick',
  'appStatus', 'reportClientError', 'checkEmailDomain', 'saveOwnList',
  'startRoomFromList', 'saveMyPlaces', 'shareRoomLists', 'setNoTimer', 'setNickname', 'reportPlace',
  'countEvent', 'insightsReport'];

module.exports = { createRoomHandlers, CALLABLES, CODE_ALPHABET, CAPACITY };
