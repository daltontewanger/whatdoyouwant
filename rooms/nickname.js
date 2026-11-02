// Nicknames are shown to everyone in the same room, so the server is the only
// place one is accepted. The format is narrow on purpose: letters, digits,
// spaces and a little punctuation, nothing that can carry a link, markup or
// hidden text. The word check catches the common cases; it cannot catch them
// all.
const MIN_LENGTH = 2;
const MAX_LENGTH = 20;

// Letters and marks from any language, ASCII digits, space and . _ ' -
const ALLOWED = /^[\p{L}\p{M}0-9 ._'-]+$/u;
// Stacked accents ("zalgo" text) spill over the lines around them. Counted
// on the decomposed letters: Vietnamese uses up to two on one letter.
const STACKED_MARKS = /\p{M}{3,}/u;
const HAS_LETTER_OR_DIGIT = /[\p{L}0-9]/u;
// Something.com, a.co and the like: a dot between letters with two or more after it.
const DOMAIN_LIKE = /[\p{L}\p{M}0-9]\.[\p{L}\p{M}0-9]{2,}/u;

class InvalidNickname extends Error {}
class BlockedNickname extends Error {}

// Matched anywhere in the name once spaces and punctuation are removed:
// these rarely turn up inside ordinary names.
const ANYWHERE = [
  'fuck', 'fck', 'shit', 'cunt', 'nigger', 'nigga', 'faggot', 'bitch', 'whore', 'slut',
  'pussy', 'asshole', 'bastard', 'wanker', 'twat', 'retard', 'rapist', 'kike', 'wetback', 'tranny',
  'nazi', 'hitler', 'kkk', 'porn', 'penis', 'vagina', 'dildo', 'jizz', 'boob', 'molest',
  'pedophile', 'paedophile', 'skank', 'douche', 'bollocks', 'bellend', 'piss', 'beaner',
  'raghead', 'towelhead', 'cocksuck', 'blowjob', 'handjob', 'motherf', 'orgasm',
  'testicle', 'clitoris', 'masturbat', 'jackoff', 'jerkoff', 'horny', 'milf', 'hentai',
];

// Matched only as a whole word (or the whole name), because each also hides
// inside innocent names: Dickens, Hancock, grape, Scunthorpe's neighbours.
const WHOLE_WORD = [
  'ass', 'arse', 'dick', 'cock', 'cum', 'tit', 'tits', 'titty', 'hoe', 'fag', 'rape', 'chink',
  'spic', 'dyke', 'coon', 'gook', 'paki', 'negro', 'sex', 'sexy', 'anal', 'anus', 'pedo', 'nonce',
  'prick', 'heil', 'nude', 'nudes', 'xxx', 'jap', 'homo', 'lesbo', 'thot', 'fuk', 'wank',
  'semen',
];

// Names that would pass for the app, its staff, or a role in the room.
const RESERVED = [
  'host', 'guest', 'guests', 'admin', 'administrator', 'moderator', 'mod', 'support', 'staff',
  'official', 'system', 'whatdoyouwant', 'you', 'everyone', 'anonymous', 'owner', 'help',
];

// Digits and symbols people swap in for letters.
const LOOK_ALIKES = { 0: 'o', 1: 'i', 3: 'e', 4: 'a', 5: 's', 7: 't', 8: 'b', 9: 'g', '@': 'a', $: 's', '!': 'i', '|': 'i' };

// Each letter may repeat ("fuuuck"), so a word written with doubled letters
// is still found; a word's own double letters must be there at least twice.
const pattern = word => [...word].map(letter => `${letter}+`).join('');
const ANYWHERE_PATTERN = new RegExp(ANYWHERE.map(pattern).join('|'));
const WORD_PATTERN = new RegExp(`^(?:${WHOLE_WORD.map(pattern).join('|')})(?:e?s)?$`);

/** Lowercase ASCII-ish words: accents and fancy letters folded, look-alikes swapped. */
function words(text) {
  const folded = text.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase()
    .replace(/[0-9@$!|]/g, character => LOOK_ALIKES[character] ?? character);
  return folded.split(/[^a-z]+/).filter(Boolean);
}

function blocked(text) {
  const parts = words(text);
  const joined = parts.join('');
  if (!joined) return false;
  if (ANYWHERE_PATTERN.test(joined) || joined.includes('www') || joined.includes('http')) return true;
  if (RESERVED.includes(joined)) return true;
  // Single letters spaced out ("a s s") are read as one word.
  return [...parts, joined].some(part => WORD_PATTERN.test(part));
}

/**
 * The nickname as it will be stored and shown, or '' to clear it. Throws
 * InvalidNickname for the wrong length or characters and BlockedNickname for
 * a blocked word or a reserved name.
 */
function parseNickname(raw) {
  if (typeof raw !== 'string' || raw.length > 200) throw new InvalidNickname();
  // NFKC turns styled letters (bold, circled, full-width) into plain ones.
  const text = raw.normalize('NFKC').replace(/\s+/g, ' ').trim();
  if (!text) return '';
  const length = [...text].length;
  if (length < MIN_LENGTH || length > MAX_LENGTH || !ALLOWED.test(text) || STACKED_MARKS.test(text.normalize('NFD')) ||
    !HAS_LETTER_OR_DIGIT.test(text) || DOMAIN_LIKE.test(text)) {
    throw new InvalidNickname();
  }
  if (blocked(text)) throw new BlockedNickname();
  return text;
}

module.exports = { parseNickname, InvalidNickname, BlockedNickname, MIN_LENGTH, MAX_LENGTH };
