/*!
 * WDYW homepage avatars
 * Animated SVG character scenes (duo + solo) for the "What Do You Want?!" homepage.
 * - 10-person cast, random combo on every page load (no repeats on one page)
 * - Gentle blink + bob animation, respects prefers-reduced-motion
 * - No dependencies. ~20 KB. Works as a plain <script> tag or via bundler import.
 *
 * Usage:
 *   <div data-wdyw-scene="duo"></div>
 *   <div data-wdyw-scene="solo"></div>
 *   a script tag pointing at /avatars.js (with defer), anywhere on the page
 * The script fills every [data-wdyw-scene] element on DOMContentLoaded.
 * Optional attributes: data-bg="#DCEDE3"  data-people="maya,theo"  data-holder="left|right"
 */
(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.WDYWAvatars = api;
  if (typeof document !== 'undefined') {
    var go = function () { if (!api._mounted) api.mountAll(); };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', go);
    else go();
  }
})(typeof window !== 'undefined' ? window : null, function () {
  'use strict';

  /* ---------- palettes ---------- */
  var SKIN = {
    fair:  { base: '#F4D3BC', shade: '#E2B497', light: '#FBE4D3', lip: '#D27A6C', line: '#9A4A40', blush: '#EE8B76', mouth: '#7E2F28' },
    light: { base: '#F0C8A8', shade: '#DBAA88', light: '#F8DAC2', lip: '#C9705E', line: '#8E4639', blush: '#E8846E', mouth: '#772C24' },
    olive: { base: '#E3B691', shade: '#CA9670', light: '#F0CAA8', lip: '#BC6B5C', line: '#874537', blush: '#E08872', mouth: '#6E2A22' },
    tan:   { base: '#C99368', shade: '#AF7A51', light: '#DCA87F', lip: '#A45A4A', line: '#6E3328', blush: '#D0705A', mouth: '#5E241C' },
    brown: { base: '#A86E48', shade: '#8E5835', light: '#BE865E', lip: '#84443A', line: '#5A2A20', blush: '#C0604A', mouth: '#4E1E18' },
    deep:  { base: '#8A5A3C', shade: '#72462D', light: '#A7714E', lip: '#74392E', line: '#4A2219', blush: '#B5523F', mouth: '#3E1712' },
    rich:  { base: '#6E4630', shade: '#583623', light: '#875A3F', lip: '#5E2E24', line: '#3A1A12', blush: '#9E4A38', mouth: '#30120D' }
  };
  var HAIR = {
    black:     { base: '#251D19', shade: '#15100D', light: '#4A3B33' },
    darkBrown: { base: '#3A2A20', shade: '#271B14', light: '#5E4636' },
    brown:     { base: '#6B4630', shade: '#4F3220', light: '#8E6447' },
    auburn:    { base: '#A44E2C', shade: '#82381C', light: '#C86C44' },
    silver:    { base: '#CDC8C2', shade: '#A39D96', light: '#EDEAE6' }
  };
  var CLOTH = {
    yellow: { main: '#F4C04A', shade: '#DBA532', light: '#F9D57A' },
    green:  { main: '#2F7A5A', shade: '#245F46', light: '#3F936D' },
    sky:    { main: '#6CB4E4', shade: '#529BCB', light: '#91C9EE' },
    coral:  { main: '#EF7B5E', shade: '#D4634A', light: '#F59C84' },
    sage:   { main: '#86B596', shade: '#6C9C7D', light: '#A3CBB0' },
    charcoal: { main: '#3E4C5E', shade: '#2F3B4A', light: '#58697E' },
    blush:  { main: '#F2A7A0', shade: '#DD8B84', light: '#F8C3BD' },
    denim:  { main: '#4A7FB0', shade: '#3A6894', light: '#6C9CC9' },
    lilac:  { main: '#B6A3D8', shade: '#9C88C3', light: '#CDC0E8' },
    terracotta: { main: '#D9774F', shade: '#BC5F39', light: '#E8946E' },
    cream:  { main: '#FFF9EC', shade: '#EADFC6', light: '#FFFFFF' },
    white:  { main: '#FFFDF7', shade: '#E7DFCF', light: '#FFFFFF' }
  };
  var BACKDROPS = [
    ['#DCEDE3', '#EAF5EF'], ['#DCEAF7', '#EBF3FB'], ['#FBEFD0', '#FDF6E3'], ['#FBE3DA', '#FDF0EA']
  ];
  var CASES = ['#EF7B5E', '#F4C04A', '#2F7A5A', '#6CB4E4', '#2B2F36', '#B6A3D8'];

  /* ---------- the cast ---------- */
  var CAST = [
    { id: 'maya',   name: 'Maya',   skin: 'deep',  hair: 'curls',        hairColor: 'black',     iris: '#2A1B15', outfit: 'crew',      cloth: 'yellow', expr: 'grin',  lashes: true,  build: 0.95, height: 2,  earrings: 'hoop' },
    { id: 'theo',   name: 'Theo',   skin: 'olive', hair: 'shortTextured', hairColor: 'darkBrown', iris: '#4A2E22', outfit: 'overshirt', cloth: 'green',  inner: 'white', expr: 'grin', square: true, build: 1.06, height: -6, beard: 'full', beardColor: '#47342A' },
    { id: 'june',   name: 'June',   skin: 'fair',  hair: 'bob',          hairColor: 'auburn',    iris: '#4E6B3E', outfit: 'cardigan',  cloth: 'sky',    inner: 'cream', expr: 'smile', lashes: true, build: 0.93, height: 4, glasses: '#1F2A24', freckles: true },
    { id: 'amira',  name: 'Amira',  skin: 'brown', hair: 'hijab',        hairColor: 'sage',      iris: '#2E1E16', outfit: 'crew',      cloth: 'coral',  expr: 'smile', lashes: true,  build: 0.94, height: 2 },
    { id: 'kenji',  name: 'Kenji',  skin: 'light', hair: 'sidePart',     hairColor: 'black',     iris: '#2A1B15', outfit: 'hoodie',    cloth: 'charcoal', inner: 'white', expr: 'smirk', square: true, build: 1.02, height: -3 },
    { id: 'priya',  name: 'Priya',  skin: 'tan',   hair: 'longStraight', hairColor: 'black',     iris: '#2E1E16', outfit: 'vneck',     cloth: 'blush',  expr: 'laugh', lashes: true,  build: 0.93, height: 3, earrings: 'stud', noseStud: true },
    { id: 'marcus', name: 'Marcus', skin: 'rich',  hair: 'bald',         hairColor: 'black',     iris: '#24160F', outfit: 'jacket',    cloth: 'denim',  inner: 'white', expr: 'grin', square: true, build: 1.08, height: -6, beard: 'short', beardColor: '#1E1612' },
    { id: 'sofia',  name: 'Sofia',  skin: 'light', hair: 'bun',          hairColor: 'brown',     iris: '#5A3A22', outfit: 'crew',      cloth: 'lilac',  expr: 'smile', lashes: true,  build: 0.93, height: 3, earrings: 'stud' },
    { id: 'diego',  name: 'Diego',  skin: 'tan',   hair: 'wavy',         hairColor: 'darkBrown', iris: '#3A2418', outfit: 'overshirt', cloth: 'terracotta', inner: 'cream', expr: 'grin', square: true, build: 1.04, height: -2, beard: 'mustache', beardColor: '#2E2119' },
    { id: 'grace',  name: 'Grace',  skin: 'brown', hair: 'coily',        hairColor: 'silver',    iris: '#2E1E16', outfit: 'cardigan',  cloth: 'sage',   inner: 'white', expr: 'smile', lashes: true, build: 0.96, height: 1, glasses: '#7A5520', earrings: 'hoopSilver', mature: true }
  ];
  var HIJAB = { sage: { base: '#86B596', shade: '#6C9C7D', light: '#A3CBB0' } };

  /* ---------- helpers ---------- */
  var n = function (v) { return Math.round(v * 100) / 100; };
  function P(d, fill, extra) { return '<path d="' + d + '" fill="' + fill + '"' + (extra || '') + '/>'; }
  function S(d, stroke, w, extra) { return '<path d="' + d + '" fill="none" stroke="' + stroke + '" stroke-width="' + w + '" stroke-linecap="round" stroke-linejoin="round"' + (extra || '') + '/>'; }
  function C(cx, cy, r, fill, extra) { return '<circle cx="' + n(cx) + '" cy="' + n(cy) + '" r="' + n(r) + '" fill="' + fill + '"' + (extra || '') + '/>'; }
  function E(cx, cy, rx, ry, fill, extra) { return '<ellipse cx="' + n(cx) + '" cy="' + n(cy) + '" rx="' + n(rx) + '" ry="' + n(ry) + '" fill="' + fill + '"' + (extra || '') + '/>'; }
  function mulberry(seed) { return function () { seed |= 0; seed = seed + 0x6D2B79F5 | 0; var t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
  function hairCol(c) { return c.hair === 'hijab' ? HIJAB[c.hairColor] : HAIR[c.hairColor]; }

  /* ---------- face ---------- */
  function faceD(f, sq) {
    var cx = n(f * 5);
    if (sq) return 'M -46,-14 C -47,-48 -24,-66 0,-66 C 24,-66 47,-48 46,-14 C 45,12 41,33 31,47 C 21,58 ' + n(cx + 10) + ',64 ' + cx + ',64 C ' + n(cx - 10) + ',64 -21,58 -31,47 C -41,33 -45,12 -46,-14 Z';
    return 'M -44,-14 C -45,-46 -24,-64 0,-64 C 24,-64 45,-46 44,-14 C 43,12 37,33 26,48 C 17,58 ' + n(cx + 7) + ',63 ' + cx + ',63 C ' + n(cx - 7) + ',63 -17,58 -26,48 C -37,33 -43,12 -44,-14 Z';
  }
  function faceShadeD(sq) {
    var k = sq ? 46 / 44 : 1, x = function (v) { return n(v * k); };
    return 'M ' + x(-44) + ',-14 C ' + x(-44) + ',6 ' + x(-40) + ',26 ' + x(-30) + ',42 C ' + x(-24) + ',51 ' + x(-16) + ',57 ' + x(-8) + ',61 C ' + x(-19) + ',50 ' + x(-27) + ',30 ' + x(-30) + ',8 C ' + x(-32) + ',-14 ' + x(-29) + ',-36 ' + x(-19) + ',-57 C ' + x(-34) + ',-51 ' + x(-44) + ',-34 ' + x(-44) + ',-14 Z';
  }

  function eyes(c, sk, fx, f, blink) {
    var out = '', ey = 2, ix = n(f * 1.6), squint = c.expr === 'laugh';
    var lid = squint ? 3 : 0, lash = '#22160F';
    var xs = [fx - 18, fx + 18];
    var iris = '';
    xs.forEach(function (x) {
      iris += E(x + ix, ey + 3.6, 4.6, 4.6, c.iris) + C(x + ix, ey + 4.4, 2.2, '#120B08') + C(x + ix + 1.5, ey + 5.4, 1.05, '#FFFFFF');
    });
    out += '<g class="wdyw-blink" style="--b:' + blink[0] + 's;--bd:' + blink[1] + 's">' + iris + '</g>';
    xs.forEach(function (x, i) {
      var s = i === 0 ? -1 : 1;
      out += P('M ' + n(x - 10.5) + ',' + (ey + lid) + ' Q ' + n(x) + ',' + (ey + lid + 5.5) + ' ' + n(x + 10.5) + ',' + (ey + lid) + ' Q ' + n(x) + ',' + (ey - 7) + ' ' + n(x - 10.5) + ',' + (ey + lid) + ' Z', sk.base);
      out += S('M ' + n(x - 9.5) + ',' + (ey + lid + 0.4) + ' Q ' + n(x) + ',' + (ey + lid + 6) + ' ' + n(x + 9.5) + ',' + (ey + lid + 0.4), lash, 2.6);
      out += S('M ' + n(x - 8) + ',' + (ey - 5.5) + ' Q ' + n(x) + ',' + (ey - 9) + ' ' + n(x + 8) + ',' + (ey - 5.5), sk.shade, 1.5);
      out += S('M ' + n(x - 5.5) + ',' + (ey + 10.5) + ' Q ' + n(x) + ',' + (ey + 12) + ' ' + n(x + 5.5) + ',' + (ey + 10.5), sk.shade, 1.3, ' opacity=".8"');
      if (c.lashes) out += S('M ' + n(x + s * 9.5) + ',' + (ey + lid + 0.4) + ' L ' + n(x + s * 13) + ',' + (ey + lid - 2.6), lash, 2);
      if (c.mature) out += S('M ' + n(x + s * 13) + ',' + (ey + 4) + ' L ' + n(x + s * 17) + ',' + (ey + 2) + ' M ' + n(x + s * 13) + ',' + (ey + 7.5) + ' L ' + n(x + s * 17) + ',' + (ey + 8), sk.shade, 1.3);
    });
    return out;
  }

  function brows(c, sk, fx) {
    var col = c.hair === 'bald' || c.hair === 'hijab' ? '#2A1B15' : (c.hairColor === 'silver' ? '#7D7670' : HAIR[c.hairColor].shade);
    if (c.hairColor === 'auburn') col = '#7A3820';
    var raise = (c.expr === 'grin' || c.expr === 'laugh') ? 2.5 : 0;
    var by = -14 - raise, th = c.square ? 1.4 : 0, out = '';
    var lx = fx - 18, rx = fx + 18;
    out += P('M ' + n(lx - 11) + ',' + n(by + 3) + ' Q ' + n(lx - 3) + ',' + n(by - 4 - th) + ' ' + n(lx + 9) + ',' + n(by - 0.5) + ' Q ' + n(lx - 1) + ',' + n(by - 1 + th) + ' ' + n(lx - 11) + ',' + n(by + 5 + th) + ' Z', col);
    if (c.expr === 'smirk') by -= 3;
    out += P('M ' + n(rx + 11) + ',' + n(by + 3) + ' Q ' + n(rx + 3) + ',' + n(by - 4 - th) + ' ' + n(rx - 9) + ',' + n(by - 0.5) + ' Q ' + n(rx + 1) + ',' + n(by - 1 + th) + ' ' + n(rx + 11) + ',' + n(by + 5 + th) + ' Z', col);
    return out;
  }

  function nose(sk, nx) {
    return S('M ' + n(nx - 2.5) + ',0 C ' + n(nx - 3) + ',9 ' + n(nx - 6) + ',15 ' + n(nx - 8) + ',20.5', sk.shade, 2, ' opacity=".85"') +
      P('M ' + n(nx - 8.5) + ',21 C ' + n(nx - 9.5) + ',26 ' + n(nx - 3) + ',28.5 ' + n(nx) + ',27.5 C ' + n(nx + 3) + ',28.5 ' + n(nx + 9.5) + ',26 ' + n(nx + 8.5) + ',21 C ' + n(nx + 5) + ',24 ' + n(nx + 2) + ',24.5 ' + n(nx) + ',23.5 C ' + n(nx - 2) + ',24.5 ' + n(nx - 5) + ',24 ' + n(nx - 8.5) + ',21 Z', sk.shade) +
      E(nx + 1.5, 19, 2.8, 2.1, sk.light, ' opacity=".9"');
  }

  function mouth(c, sk, mx) {
    var my = 40, o = '';
    if (c.expr === 'smile') {
      o += P('M ' + n(mx - 8.5) + ',' + (my + 2.5) + ' Q ' + n(mx) + ',' + (my + 10) + ' ' + n(mx + 8.5) + ',' + (my + 2.5) + ' Q ' + n(mx) + ',' + (my + 5) + ' ' + n(mx - 8.5) + ',' + (my + 2.5) + ' Z', sk.lip);
      o += S('M ' + n(mx - 12) + ',' + (my - 1) + ' Q ' + n(mx) + ',' + (my + 5) + ' ' + n(mx + 12) + ',' + (my - 1), sk.line, 2.4);
      o += E(mx, my + 13.5, 5.5, 1.8, sk.shade, ' opacity=".7"');
    } else if (c.expr === 'smirk') {
      o += P('M ' + n(mx - 6) + ',' + (my + 3) + ' Q ' + n(mx + 2) + ',' + (my + 9) + ' ' + n(mx + 9) + ',' + (my + 2) + ' Q ' + n(mx + 1) + ',' + (my + 5) + ' ' + n(mx - 6) + ',' + (my + 3) + ' Z', sk.lip);
      o += S('M ' + n(mx - 10) + ',' + (my + 1.5) + ' Q ' + n(mx + 1) + ',' + (my + 5) + ' ' + n(mx + 12) + ',' + (my - 2.5), sk.line, 2.4);
      o += E(mx + 1, my + 13, 5, 1.7, sk.shade, ' opacity=".7"');
    } else {
      var big = c.expr === 'laugh' ? 2.5 : 0;
      o += P('M ' + n(mx - 12 - big) + ',' + (my - 2) + ' Q ' + n(mx) + ',' + (my + 2) + ' ' + n(mx + 12 + big) + ',' + (my - 2) + ' Q ' + n(mx + 9 + big) + ',' + n(my + 10 + big * 1.6) + ' ' + n(mx) + ',' + n(my + 10 + big * 1.6) + ' Q ' + n(mx - 9 - big) + ',' + n(my + 10 + big * 1.6) + ' ' + n(mx - 12 - big) + ',' + (my - 2) + ' Z', sk.mouth);
      if (big) o += E(mx, my + 10, 6, 2.8, '#D46A62');
      o += P('M ' + n(mx - 10 - big) + ',' + (my - 1) + ' Q ' + n(mx) + ',' + (my + 2) + ' ' + n(mx + 10 + big) + ',' + (my - 1) + ' L ' + n(mx + 9 + big) + ',' + (my + 3) + ' Q ' + n(mx) + ',' + (my + 5) + ' ' + n(mx - 9 - big) + ',' + (my + 3) + ' Z', '#FFFFFF');
      o += S('M ' + n(mx - 6) + ',' + n(my + 12.5 + big * 1.6) + ' Q ' + n(mx) + ',' + n(my + 14.5 + big * 1.6) + ' ' + n(mx + 6) + ',' + n(my + 12.5 + big * 1.6), sk.lip, 2.6);
    }
    return o;
  }

  function beard(c, sk, fx, mx) {
    if (!c.beard) return '';
    var col = c.beardColor, o = '';
    var sh = function (d) { return d.replace(/(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/g, function (_, a, b) { return n(+a + fx * 0.6) + ',' + b; }); };
    if (c.beard === 'full' || c.beard === 'short') {
      var top = c.beard === 'full' ? 6 : 14;
      o += P(sh('M -46,' + top + ' C -44,34 -30,56 -10,64 C -4,66 4,66 10,64 C 30,56 44,34 46,' + top + ' C 42,24 32,32 20,33 C 12,28 -12,28 -20,33 C -32,32 -42,24 -46,' + top + ' Z'), col);
      o += S(sh('M -30,46 C -20,56 -6,60 8,58 M 14,52 C 22,50 30,44 34,36'), '#FFFFFF', 1.6, ' opacity=".12"');
    } else if (c.beard === 'mustache') {
      o += P(sh('M -40,14 C -38,36 -26,54 -8,61 C 0,64 8,62 14,60 C 30,54 40,36 42,14 C 36,30 26,40 0,40 C -24,40 -34,30 -40,14 Z'), col, ' opacity=".16"');
      o += P('M ' + n(mx - 14) + ',37.5 C ' + n(mx - 8) + ',30.5 ' + n(mx + 8) + ',30.5 ' + n(mx + 14) + ',37.5 C ' + n(mx + 8) + ',35.5 ' + n(mx - 8) + ',35.5 ' + n(mx - 14) + ',37.5 Z', col);
    }
    return o;
  }

  function ears(c, sk, f) {
    if (c.hair === 'hijab') return '';
    var o = '', xs = [];
    if (f <= 0.3) xs.push(c.square ? 46 : 44);
    if (f >= -0.3) xs.push(c.square ? -46 : -44);
    xs.forEach(function (x) {
      var s = x < 0 ? -1 : 1;
      o += E(x + s * 1, 4, 7.5, 12.5, x < 0 ? sk.shade : sk.base);
      o += S('M ' + n(x - s * 1) + ',-4 Q ' + n(x + s * 5) + ',3 ' + n(x) + ',11', x < 0 ? '#00000022' : sk.shade, 2.2);
      if (c.earrings === 'hoop' || c.earrings === 'hoopSilver') o += C(x + s * 1, 21, 5.5, 'none', ' stroke="' + (c.earrings === 'hoop' ? '#E2AE36' : '#C9CDD2') + '" stroke-width="2.6"');
      else if (c.earrings === 'stud') o += C(x + s * 1, 15, 2.4, '#F1D27A');
    });
    return o;
  }

  function glasses(c, fx) {
    if (!c.glasses) return '';
    var g = c.glasses, o = '';
    [fx - 18, fx + 18].forEach(function (x) {
      o += '<rect x="' + n(x - 14.5) + '" y="-8" width="29" height="22" rx="9" fill="#FFFFFF" fill-opacity=".14" stroke="' + g + '" stroke-width="2.8"/>';
      o += S('M ' + n(x + 3) + ',-4 L ' + n(x + 9) + ',-4', '#FFFFFF', 2, ' opacity=".7"');
    });
    o += S('M ' + n(fx - 3.5) + ',0 Q ' + n(fx) + ',-3.5 ' + n(fx + 3.5) + ',0', g, 2.8);
    o += S('M ' + n(fx - 32.5) + ',-1 L -44,-3 M ' + n(fx + 32.5) + ',-1 L 44,-3', g, 2.6);
    return o;
  }

  /* ---------- hair ---------- */
  function hair(c, sk) {
    var h = hairCol(c), r = { back: '', front: '', drapeHead: '', drapeBody: '' };
    switch (c.hair) {
      case 'curls': {
        var cloud = [[-52, -36, 40], [-14, -62, 42], [30, -60, 40], [62, -30, 36], [-70, 4, 34], [70, 8, 32], [-66, 44, 30], [64, 46, 28], [-60, 78, 24], [56, 78, 22], [0, -30, 52]];
        cloud.forEach(function (p) { r.back += C(p[0], p[1], p[2], h.base); });
        r.back += S('M -78,-30 C -82,-50 -70,-66 -54,-70 M 76,-36 C 84,-20 84,-4 78,8 M 86,42 C 90,54 86,66 78,72 M 22,-96 C 36,-96 50,-88 58,-76', h.light, 3.5);
        [[-46, -30, 13], [-34, -46, 16], [-14, -56, 17], [8, -58, 17], [30, -52, 16], [44, -36, 13]].forEach(function (p) { r.front += C(p[0], p[1], p[2], h.base); });
        r.front += S('M -24,-66 C -14,-74 2,-76 16,-72 M 30,-64 C 38,-60 44,-52 48,-44', h.light, 3.5);
        break;
      }
      case 'shortTextured':
        r.front += P('M -49,-8 C -56,-56 -28,-84 4,-84 C 38,-84 58,-58 50,-8 C 47,-26 40,-38 28,-45 C 12,-52 -12,-52 -28,-44 C -40,-37 -46,-24 -49,-8 Z', h.base);
        r.front += P('M -49,-8 C -54,-40 -44,-62 -26,-74 C -36,-58 -40,-40 -40,-28 C -44,-22 -47,-16 -49,-8 Z', h.shade);
        r.front += S('M -30,-62 C -20,-72 -4,-77 10,-74 M -10,-54 C 2,-64 18,-67 32,-62 M 22,-78 C 34,-74 44,-64 48,-50', h.light, 3);
        r.front += P('M 44,-12 L 50,-10 L 47,14 L 43,13 Z', h.base) + P('M -45,-12 L -50,-10 L -47,14 L -44,13 Z', h.base);
        break;
      case 'sidePart':
        r.front += P('M -49,-6 C -55,-58 -24,-86 6,-84 C 38,-84 57,-58 50,-6 C 47,-24 42,-36 32,-44 C 18,-40 0,-42 -14,-52 C -22,-42 -36,-30 -49,-6 Z', h.base);
        r.front += P('M -49,-6 C -54,-40 -44,-64 -24,-76 C -34,-58 -38,-40 -38,-30 C -42,-22 -46,-14 -49,-6 Z', h.shade);
        r.front += S('M -14,-52 C -18,-64 -19,-74 -16,-82', h.shade, 2.2);
        r.front += S('M -6,-60 C 8,-70 26,-70 40,-58 M 0,-48 C 14,-54 28,-52 40,-44 M -28,-66 C -32,-56 -38,-46 -42,-34', h.light, 2.8);
        r.front += P('M 44,-12 L 50,-10 L 47,10 L 43,9 Z', h.base) + P('M -45,-12 L -50,-10 L -47,10 L -44,9 Z', h.base);
        break;
      case 'bob':
        r.back += P('M -58,-10 C -62,-62 -26,-82 2,-82 C 32,-82 64,-60 60,-10 C 60,20 63,44 68,62 C 52,70 38,68 28,60 L -28,60 C -40,68 -56,70 -66,62 C -60,44 -58,20 -58,-10 Z', h.base);
        r.back += P('M -58,-10 C -58,20 -60,44 -66,62 C -58,66 -50,67 -44,66 C -50,44 -50,20 -50,-10 Z', h.shade);
        r.front += P('M -50,-16 C -52,-58 -22,-76 2,-76 C 30,-76 54,-58 52,-16 C 42,-28 32,-34 22,-28 C 12,-38 -4,-38 -12,-28 C -24,-36 -38,-32 -50,-16 Z', h.base);
        r.front += S('M -16,-67 C 0,-73 18,-70 32,-62 M -36,-50 C -30,-42 -24,-36 -16,-32 M 8,-42 C 14,-36 18,-32 22,-28', h.light, 3);
        r.front += S('M 54,0 C 55,22 57,40 60,54 M -52,4 C -52,24 -54,40 -58,52', h.light, 2.6, ' opacity=".8"');
        break;
      case 'longStraight':
        r.back += P('M -56,-14 C -60,-64 -26,-86 2,-86 C 34,-86 62,-64 58,-14 C 58,40 60,90 64,150 L -64,150 C -60,90 -56,40 -56,-14 Z', h.shade);
        r.drapeHead += P('M -46,-20 C -54,20 -58,70 -62,140 C -50,148 -38,146 -30,140 C -32,90 -34,40 -36,0 Z', h.base);
        r.drapeHead += P('M 46,-20 C 54,20 58,70 62,140 C 50,148 38,146 30,140 C 32,90 34,40 36,0 Z', h.base);
        r.drapeHead += S('M -50,20 C -54,60 -56,100 -54,136 M 52,20 C 55,60 56,100 54,136', h.light, 2.4, ' opacity=".8"');
        r.drapeHead += S('M -40,40 C -42,80 -42,110 -40,140 M 41,40 C 43,80 43,110 41,140', h.shade, 2);
        r.front += P('M -47,-10 C -50,-58 -18,-80 8,-80 C 36,-80 56,-58 50,-12 C 44,-34 32,-50 12,-54 C -8,-56 -28,-44 -40,-26 C -44,-20 -46,-15 -47,-10 Z', h.base);
        r.front += S('M -2,-79 C 4,-68 8,-60 12,-54', h.shade, 2);
        r.front += S('M 16,-72 C 32,-68 44,-56 48,-36 M -12,-68 C -26,-62 -36,-50 -42,-36', h.light, 3);
        break;
      case 'bun':
        r.back += C(6, -86, 22, h.base) + P('M -12,-96 C -6,-108 18,-110 26,-96 C 20,-102 2,-104 -12,-96 Z', h.light, ' opacity=".7"') + C(14, -78, 10, h.shade, ' opacity=".5"');
        r.front += P('M -45,-10 C -48,-56 -24,-74 0,-74 C 24,-74 48,-56 45,-10 C 42,-30 34,-46 18,-52 C 8,-50 -8,-50 -18,-52 C -34,-46 -42,-30 -45,-10 Z', h.base);
        r.front += P('M -45,-10 C -48,-40 -38,-60 -22,-70 C -32,-56 -36,-40 -38,-28 C -42,-22 -44,-16 -45,-10 Z', h.shade);
        r.front += S('M -30,-52 C -20,-64 -6,-71 4,-72 M 32,-52 C 24,-62 16,-68 8,-72 M -6,-50 C -2,-60 0,-66 2,-72', h.light, 2.6);
        r.front += S('M -45,-8 C -49,6 -47,18 -43,28', h.base, 2.6) + S('M 45,-8 C 48,4 47,14 44,22', h.base, 2.4);
        r.front += '<rect x="-8" y="-68" width="20" height="5" rx="2.5" fill="' + h.shade + '" transform="rotate(-6 2 -66)" opacity=".0"/>';
        break;
      case 'wavy':
        r.back += P('M -55,-12 C -62,-62 -28,-90 2,-90 C 38,-90 64,-62 57,-12 C 60,6 58,20 51,30 C 46,18 46,6 46,-6 L -46,-6 C -46,6 -46,18 -51,30 C -58,20 -58,6 -55,-12 Z', h.shade);
        r.front += P('M -48,-8 C -55,-52 -36,-84 -2,-88 C 36,-90 60,-64 52,-12 C 50,-30 43,-44 31,-50 C 21,-46 10,-50 2,-57 C -8,-50 -20,-50 -30,-46 C -40,-38 -46,-24 -48,-8 Z', h.base);
        r.front += P('M -48,-8 C -55,-46 -42,-74 -18,-84 C -32,-70 -38,-52 -36,-40 C -42,-30 -46,-20 -48,-8 Z', h.shade);
        r.front += S('M -26,-74 C -16,-82 -2,-82 6,-76 C 14,-70 24,-74 30,-80 M -20,-60 C -10,-68 2,-68 10,-62 C 18,-56 30,-60 38,-66 M 36,-52 C 44,-46 48,-36 50,-24', h.light, 2.6);
        r.front += S('M -49,-6 C -53,6 -49,16 -53,26 M 50,-8 C 54,4 51,14 54,24', h.base, 3.6);
        break;
      case 'coily': {
        var pts = [];
        for (var k = 0; k <= 10; k++) { var t = Math.PI + k * Math.PI / 10; pts.push([52 * Math.cos(t), -18 + 60 * Math.sin(t), 17]); }
        pts.push([-54, 6, 13], [54, 6, 13], [0, -36, 46]);
        pts.forEach(function (p) { r.back += C(p[0], p[1], p[2], h.base); });
        for (var j = 0; j < 7; j++) { var tt = Math.PI * 1.12 + j * Math.PI * 0.76 / 6; r.front += C(42 * Math.cos(tt), -22 + 44 * Math.sin(tt), 10, h.base); }
        r.front += S('M -32,-74 a 6,6 0 1 1 10,-4 M 6,-82 a 6,6 0 1 1 10,-2 M 34,-66 a 6,6 0 1 1 9,2 M -50,-46 a 5,5 0 1 1 8,-4', h.light, 2.4);
        break;
      }
      case 'hijab':
        r.back += P('M -60,-8 C -64,-66 -30,-90 0,-90 C 30,-90 64,-66 60,-8 C 60,24 56,50 64,76 L -64,76 C -56,50 -60,24 -60,-8 Z', h.base);
        r.back += P('M -60,-8 C -62,24 -58,50 -64,76 L -50,76 C -48,50 -52,24 -50,-8 C -50,-40 -40,-64 -22,-80 C -46,-74 -60,-44 -60,-8 Z', h.shade);
        r.drapeBody += P('M -64,66 C -60,36 -32,26 0,26 C 32,26 60,36 64,66 C 72,104 60,132 0,142 C -60,132 -72,104 -64,66 Z', h.base);
        r.drapeBody += P('M -64,66 C -60,36 -46,30 -36,28 C -48,48 -52,80 -46,128 C -66,118 -70,96 -64,66 Z', h.shade);
        r.drapeBody += S('M -36,86 C -14,104 16,104 40,86 M -26,112 C -6,124 14,124 32,112', h.shade, 2.6);
        r.drapeBody += S('M 40,40 C 52,50 58,62 60,74', h.light, 4);
        r.front += P('M -46,-22 C -44,-56 -22,-72 0,-72 C 22,-72 44,-56 46,-22 C 34,-40 18,-48 0,-48 C -18,-48 -34,-40 -46,-22 Z', h.base);
        r.front += S('M -44,-26 C -36,-38 -20,-46 0,-46 C 20,-46 36,-38 44,-26', h.shade, 2.6);
        r.front += S('M -26,-80 C -10,-88 12,-88 28,-80', h.light, 4.5);
        r.front += P('M -50,-20 C -50,10 -46,36 -36,54 C -44,52 -52,40 -54,20 C -56,4 -54,-10 -50,-20 Z', h.base);
        r.front += P('M 50,-20 C 50,10 46,36 36,54 C 44,52 52,40 54,20 C 56,4 54,-10 50,-20 Z', h.base);
        break;
      case 'bald':
        r.front += E(14, -46, 16, 8, sk.light, ' opacity=".6" transform="rotate(12 14 -46)"');
        r.front += P('M -45,-14 C -45,-26 -42,-36 -36,-44 C -40,-30 -41,-20 -40,-8 Z', sk.shade, ' opacity=".6"');
        break;
    }
    return r;
  }

  /* ---------- body ---------- */
  function torso(c, sk) {
    var w = c.build, cl = CLOTH[c.cloth], inr = CLOTH[c.inner || 'white'], o = '';
    var X = function (v) { return n(v * w); };
    o += P('M ' + X(-132) + ',330 L ' + X(-130) + ',190 C ' + X(-130) + ',150 ' + X(-118) + ',126 ' + X(-96) + ',120 C ' + X(-70) + ',112 -40,104 -20,97 L 20,97 C 40,104 ' + X(70) + ',112 ' + X(96) + ',120 C ' + X(118) + ',126 ' + X(130) + ',150 ' + X(130) + ',190 L ' + X(132) + ',330 Z', cl.main);
    o += P('M ' + X(-132) + ',330 L ' + X(-130) + ',190 C ' + X(-130) + ',150 ' + X(-118) + ',126 ' + X(-96) + ',120 C ' + X(-106) + ',150 ' + X(-108) + ',200 ' + X(-102) + ',330 Z', cl.shade);
    o += S('M ' + X(60) + ',112 C ' + X(84) + ',118 ' + X(104) + ',128 ' + X(116) + ',146', cl.light, 7);
    o += S('M ' + X(96) + ',156 C ' + X(100) + ',200 ' + X(100) + ',260 ' + X(98) + ',330', cl.shade, 2.6);
    o += S('M ' + X(-60) + ',200 C ' + X(-50) + ',214 ' + X(-46) + ',232 ' + X(-48) + ',250', cl.shade, 2.4, ' opacity=".8"');
    switch (c.outfit) {
      case 'crew':
        o += P('M -27,96 C -21,121 21,121 27,96 L 32,100 C 25,132 -25,132 -32,100 Z', cl.shade);
        break;
      case 'vneck':
        o += P('M -21,97 L 0,136 L 21,97 Z', sk.base) + P('M -12,98 L 0,120 L 12,98 Z', sk.shade, ' opacity=".5"');
        o += S('M -24,97 L 0,140 L 24,97', cl.shade, 5);
        break;
      case 'hoodie':
        o += P('M -27,96 C -19,118 19,118 27,96 L 33,99 C 24,128 -24,128 -33,99 Z', cl.shade);
        o += S('M -10,120 L -12,178 M 10,120 L 12,182', inr.main, 3.2);
        o += '<rect x="-15" y="176" width="6" height="11" rx="3" fill="' + inr.shade + '"/><rect x="9" y="180" width="6" height="11" rx="3" fill="' + inr.shade + '"/>';
        break;
      case 'overshirt':
      case 'jacket':
        o += P('M -20,97 C -12,112 12,112 20,97 L 17,330 L -17,330 Z', inr.main);
        o += S('M -19,98 C -11,112 11,112 19,98', inr.shade, 4);
        o += P('M -20,96 C -32,98 -42,103 -49,108 C -43,127 -35,141 -27,153 C -22,143 -19,132 -18,118 Z', cl.shade);
        o += P('M 20,96 C 32,98 42,103 49,108 C 43,127 35,141 27,153 C 22,143 19,132 18,118 Z', cl.shade);
        o += S('M -17,152 L -17,330 M 17,152 L 17,330', cl.shade, 2.6);
        if (c.outfit === 'jacket') {
          o += S('M ' + X(-84) + ',172 L ' + X(-44) + ',172 L ' + X(-46) + ',192 L ' + X(-64) + ',198 L ' + X(-82) + ',192 Z M ' + X(84) + ',172 L ' + X(44) + ',172 L ' + X(46) + ',192 L ' + X(64) + ',198 L ' + X(82) + ',192 Z', cl.shade, 2.6);
          o += C(-64 * w, 186, 2.6, cl.light) + C(64 * w, 186, 2.6, cl.light);
        }
        break;
      case 'cardigan':
        o += P('M -22,97 C -14,112 14,112 22,97 L 31,100 L 15,330 L -15,330 L -31,100 Z', inr.main);
        o += S('M -21,98 C -13,113 13,113 21,98', inr.shade, 4);
        o += S('M -31,100 L -15,330 M 31,100 L 15,330', cl.shade, 3);
        [170, 215, 260].forEach(function (y) { o += C(-31 + 16 * (y - 100) / 230 + 4, y, 3.4, cl.light); });
        break;
    }
    return o;
  }

  function neck(c, sk) {
    var wd = c.square ? 19 : 16;
    return P('M ' + -wd + ',38 L ' + wd + ',38 L ' + (wd + 3) + ',108 L ' + -(wd + 3) + ',108 Z', sk.base) +
      P('M ' + -wd + ',42 C -6,64 6,64 ' + wd + ',42 L ' + (wd + 1) + ',72 C 5,82 -5,82 ' + -(wd + 1) + ',72 Z', sk.shade);
  }

  /* ---------- one person ---------- */
  function person(c, pose) {
    var sk = SKIN[c.skin], h = hair(c, sk), f = pose.facing, fx = n(f * 5);
    var tilt = pose.tilt, s = pose.scale, hx = pose.x, hy = pose.y + c.height;
    var rad = tilt * Math.PI / 180, bodyX = n(hx - Math.sin(rad) * 104 * s);
    var HT = 'translate(' + n(hx) + ' ' + n(hy) + ') rotate(' + tilt + ') scale(' + s + ')';
    var BT = 'translate(' + bodyX + ' ' + n(hy) + ') scale(' + s + ')';
    var nod = 'style="transform-origin:' + bodyX + 'px ' + n(hy + 100 * s) + 'px;--n:' + pose.nod[0] + 's;--nd:' + pose.nod[1] + 's"';
    var o = '<g class="wdyw-bob" style="--d:' + pose.bob[0] + 's;--dl:' + pose.bob[1] + 's">';
    o += '<g class="wdyw-nod" ' + nod + '><g transform="' + HT + '">' + h.back + neck(c, sk) + '</g></g>';
    o += '<g transform="' + BT + '">' + torso(c, sk) + h.drapeBody + '</g>';
    var face = '';
    face += h.drapeHead + ears(c, sk, f);
    face += P(faceD(f, c.square), sk.base) + P(faceShadeD(c.square), sk.shade);
    face += E(fx + 25, 10, 8, 4.5, sk.light, ' opacity=".65"');
    face += E(fx - 22, 22, 9, 5, sk.blush, ' opacity=".22"') + E(fx + 22, 22, 9, 5, sk.blush, ' opacity=".22"');
    if (c.freckles) [[-24, 17], [-18, 21], [-28, 23], [-21, 26], [21, 17], [27, 22], [16, 23], [23, 26]].forEach(function (p) { face += C(fx + p[0], p[1], 1.3, '#C98D6E'); });
    if (c.mature) face += S('M ' + n(fx - 13) + ',27 Q ' + n(fx - 17) + ',35 ' + n(fx - 14) + ',43 M ' + n(fx + 13) + ',27 Q ' + n(fx + 17) + ',35 ' + n(fx + 14) + ',43', sk.shade, 1.8);
    face += eyes(c, sk, fx, f, pose.blink) + brows(c, sk, fx);
    face += beard(c, sk, fx, fx + f * 1.5);
    face += nose(sk, fx + f * 2);
    if (c.noseStud) face += C(fx + f * 2 + 6, 23, 1.6, '#F2E6C8');
    face += mouth(c, sk, n(fx + f * 1.5));
    face += glasses(c, fx);
    face += h.front;
    o += '<g class="wdyw-nod" ' + nod + '><g transform="' + HT + '">' + face + '</g></g>';
    o += '</g>';
    return o;
  }

  /* ---------- phone + hand ---------- */
  function phoneHand(c, x, y, rot, s, palmSide, caseCol, bob) {
    var sk = SKIN[c.skin], o = '';
    var hand = '';
    hand += P('M -28,-24 C -38,-26 -43,-13 -39,-3 C -37,3 -31,6 -27,4 Z', sk.base, ' data-part="thumb"');
    var handFront = '';
    handFront += P('M -46,150 C -48,100 -50,50 -43,20 C -40,8 -36,2 -28,1 L 24,2 C 31,2 33,13 26,14 C 32,14 35,26 27,27 C 31,27 32,38 25,39 C 28,40 27,50 20,50 L 4,52 C 2,64 4,96 6,150 Z', sk.base);
    handFront += P('M 4,52 C 2,64 4,96 6,150 L -6,150 C -6,104 -6,70 -2,52 Z', sk.shade);
    handFront += P('M -43,20 C -49,50 -48,100 -46,150 L -38,150 C -42,100 -42,52 -37,24 Z', sk.shade, ' opacity=".55"');
    handFront += S('M -30,60 C -26,70 -18,74 -8,72', sk.shade, 1.6, ' opacity=".6"');
    handFront += S('M 25,14.5 L -6,15.5 M 26,27 L -4,28 M 24,39.5 L -3,40.5', sk.shade, 1.7);
    handFront += S('M -8,4 C -11,18 -11,36 -7,50', sk.shade, 1.5, ' opacity=".6"');
    handFront += E(21, 8, 3.4, 2.8, sk.light, ' opacity=".9"') + E(23, 20.5, 3.4, 2.8, sk.light, ' opacity=".9"') + E(21, 33, 3.3, 2.7, sk.light, ' opacity=".9"') + E(16, 44.5, 3, 2.5, sk.light, ' opacity=".9"');
    var mir = palmSide > 0 ? ' transform="scale(-1 1)"' : '';
    o += '<g class="wdyw-bob" style="--d:' + bob[0] + 's;--dl:' + bob[1] + 's"><g transform="translate(' + n(x) + ' ' + n(y) + ') rotate(' + rot + ') scale(' + s + ')">';
    o += '<g' + mir + '>' + hand + '</g>';
    o += '<rect x="-30" y="-60" width="60" height="120" rx="13" fill="' + caseCol + '"/>';
    o += '<rect x="-30" y="-60" width="60" height="120" rx="13" fill="none" stroke="#000" stroke-opacity=".12" stroke-width="2"/>';
    o += '<rect x="-23" y="-53" width="27" height="27" rx="8.5" fill="#22262B"/>';
    o += C(-15.5, -45.5, 4.4, '#0E1013', ' stroke="#4A5058" stroke-width="1.4"') + C(-15.5, -33.5, 4.4, '#0E1013', ' stroke="#4A5058" stroke-width="1.4"') + C(-4.5, -39.5, 2.3, '#F4EBD2');
    o += S('M 24,-50 L 24,-20', '#FFFFFF', 2.2, ' opacity=".28"');
    o += '<g' + mir + '>' + handFront + '</g>';
    o += '</g></g>';
    return o;
  }

  /* ---------- scenes ---------- */
  var CSS = '.wdyw-bob{animation:wdyw-bob var(--d,4.4s) ease-in-out infinite;animation-delay:var(--dl,0s)}' +
    '@keyframes wdyw-bob{0%,100%{transform:translateY(0)}50%{transform:translateY(-2.4px)}}' +
    '.wdyw-nod{transform-box:view-box;animation:wdyw-nod var(--n,5.6s) ease-in-out infinite;animation-delay:var(--nd,0s)}' +
    '@keyframes wdyw-nod{0%,100%{transform:rotate(0deg)}50%{transform:rotate(1.6deg)}}' +
    '.wdyw-blink{transform-box:fill-box;transform-origin:50% 0;animation:wdyw-blink var(--b,5s) infinite;animation-delay:var(--bd,0s)}' +
    '@keyframes wdyw-blink{0%,92%,100%{transform:scaleY(1)}94.5%{transform:scaleY(.06)}97%{transform:scaleY(1)}}' +
    '@media (prefers-reduced-motion:reduce){.wdyw-bob,.wdyw-nod,.wdyw-blink{animation:none}}';

  function rngOf(opts) { return opts && opts.seed != null ? mulberry(opts.seed) : Math.random; }
  function pickBg(rand, opts) {
    if (opts && opts.bg) return [opts.bg, opts.bg2 || '#FFFFFF66'];
    return BACKDROPS[Math.floor(rand() * BACKDROPS.length)];
  }
  function motion(rand) {
    return {
      bob: [n(3.8 + rand() * 1.4), n(-rand() * 4)],
      nod: [n(5 + rand() * 2), n(-rand() * 6)],
      blink: [n(4.2 + rand() * 2.4), n(-rand() * 5)]
    };
  }
  function frame(bg, body, label) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" width="100%" height="100%" preserveAspectRatio="xMidYMid slice" role="img" aria-label="' + label + '" style="display:block">' +
      '<style>' + CSS + '</style>' +
      '<rect width="400" height="300" fill="' + bg[0] + '"/>' +
      '<ellipse cx="200" cy="318" rx="250" ry="150" fill="' + bg[1] + '"/>' +
      body + '</svg>';
  }
  function byId(id) { for (var i = 0; i < CAST.length; i++) if (CAST[i].id === id) return CAST[i]; return null; }
  function asChar(x) { return typeof x === 'string' ? byId(x) : x; }

  function renderDuo(a, b, opts) {
    opts = opts || {}; var rand = rngOf(opts);
    a = asChar(a); b = asChar(b);
    var bg = pickBg(rand, opts);
    var holder = opts.holder || (rand() < 0.5 ? 'left' : 'right');
    var ma = motion(rand), mb = motion(rand);
    var body = person(a, { x: 126, y: 132, tilt: 7, facing: 0.8, scale: 0.94, bob: ma.bob, nod: ma.nod, blink: ma.blink });
    body += person(b, { x: 276, y: 126, tilt: -7, facing: -0.8, scale: 0.94, bob: mb.bob, nod: mb.nod, blink: mb.blink });
    var hc = holder === 'left' ? a : b, hm = holder === 'left' ? ma : mb;
    var caseCol = opts.phone || CASES[Math.floor(rand() * CASES.length)];
    body += phoneHand(hc, 202, 258, holder === 'left' ? 5 : -5, 0.72, holder === 'left' ? 1 : -1, caseCol, hm.bob);
    return frame(bg, body, a.name + ' and ' + b.name + ' looking at a phone together');
  }

  function renderSolo(c, opts) {
    opts = opts || {}; var rand = rngOf(opts);
    c = asChar(c);
    var bg = pickBg(rand, opts), m = motion(rand);
    var body = person(c, { x: 200, y: 134, tilt: -3, facing: 0, scale: 1.02, bob: m.bob, nod: m.nod, blink: m.blink });
    var caseCol = opts.phone || CASES[Math.floor(rand() * CASES.length)];
    body += phoneHand(c, 184, 264, 4, 0.76, -1, caseCol, m.bob);
    return frame(bg, body, c.name + ' smiling at their phone');
  }

  function shuffle(arr, rand) { var a = arr.slice(); for (var i = a.length - 1; i > 0; i--) { var j = Math.floor(rand() * (i + 1)); var t = a[i]; a[i] = a[j]; a[j] = t; } return a; }

  function mountAll(rootEl, opts) {
    if (typeof document === 'undefined') return;
    api._mounted = true;
    opts = opts || {};
    var rand = rngOf(opts);
    var els = (rootEl || document).querySelectorAll('[data-wdyw-scene]');
    var pool = shuffle(CAST, rand), used = 0;
    var next = function () { var c = pool[used % pool.length]; used++; return c; };
    Array.prototype.forEach.call(els, function (el) {
      var kind = el.getAttribute('data-wdyw-scene');
      var people = (el.getAttribute('data-people') || '').split(',').filter(Boolean).map(byId).filter(Boolean);
      var o = { bg: el.getAttribute('data-bg') || undefined, holder: el.getAttribute('data-holder') || undefined };
      if (kind === 'duo') el.innerHTML = renderDuo(people[0] || next(), people[1] || next(), o);
      else el.innerHTML = renderSolo(people[0] || next(), o);
    });
  }

  var api = { cast: CAST, renderDuo: renderDuo, renderSolo: renderSolo, mountAll: mountAll, _mounted: false };
  return api;
});
