// The public site's moving parts: the hero phone's lean, the room story and
// the why tiles. All optional; the page reads fully without them.

const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
document.documentElement.classList.add('js');

// ---- Hero: the phone leans a little toward the pointer and settles flat when
// it leaves. Only where a pointer hovers, and never under reduced motion.
function leanPhone() {
  const phone = document.getElementById('hero-phone');
  if (!phone || reduceMotion || !matchMedia('(hover: hover)').matches) return;
  const hero = phone.closest('section');
  hero.addEventListener('pointermove', event => {
    const box = phone.getBoundingClientRect();
    const x = (event.clientX - (box.left + box.width / 2)) / hero.offsetWidth;
    const y = (event.clientY - (box.top + box.height / 2)) / hero.offsetHeight;
    phone.style.setProperty('--ry', `${(x * 22).toFixed(1)}deg`);
    phone.style.setProperty('--rx', `${(-y * 14).toFixed(1)}deg`);
  });
  hero.addEventListener('pointerleave', () => {
    phone.style.removeProperty('--ry');
    phone.style.removeProperty('--rx');
  });
}

// ---- Room story: the step crossing the middle of the screen lights up and
// sets the scene. The scene is decorative; the steps carry the words.
function followStory() {
  const steps = [...document.querySelectorAll('.steps li')];
  const scenes = [...document.querySelectorAll('.scene')];
  if (!steps.length || !('IntersectionObserver' in window)) return;
  const show = step => {
    steps.forEach(item => item.classList.toggle('on', item === step));
    scenes.forEach(scene => scene.classList.toggle('on', scene.dataset.scene === step.dataset.step));
  };
  show(steps[0]);
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) if (entry.isIntersecting) show(entry.target);
  }, { rootMargin: '-45% 0px -45% 0px' });
  steps.forEach(step => observer.observe(step));
}

// ---- Why tiles: the opened tile grows into a panel with its fuller
// explanation, and shrinks back into place when closed. On wide screens the
// panel fills the grid; on phones it opens downward from the tile.
function openTiles() {
  const grid = document.getElementById('tiles');
  if (!grid) return;
  const stacked = matchMedia('(max-width: 760px)');
  const round = 'round 22px';
  // The panel's closed shape: exactly the tile it came from.
  const tileShape = (tile, panel) => {
    if (stacked.matches) return `inset(0 0 ${Math.max(0, panel.offsetHeight - tile.offsetHeight)}px 0 ${round})`;
    const g = grid.getBoundingClientRect();
    const t = tile.getBoundingClientRect();
    return `inset(${t.top - g.top}px ${g.right - t.right}px ${g.bottom - t.bottom}px ${t.left - g.left}px ${round})`;
  };
  let current = null;

  const close = () => {
    if (!current) return;
    const { button, panel, tile } = current;
    current = null;
    button.setAttribute('aria-expanded', 'false');
    const finish = () => {
      panel.hidden = true;
      panel.style.clipPath = '';
      panel.style.top = '';
      grid.style.minHeight = '';
      button.focus();
    };
    panel.classList.remove('shown');
    grid.classList.remove('open');
    if (reduceMotion) return finish();
    panel.style.clipPath = tileShape(tile, panel);
    setTimeout(finish, 450);
  };

  for (const button of grid.querySelectorAll('.tile-open')) {
    const tile = button.closest('.tile');
    const panel = document.getElementById(button.getAttribute('aria-controls'));
    // Panels sit on the grid itself so they can cover every tile.
    const colors = getComputedStyle(tile);
    panel.style.background = colors.backgroundColor;
    panel.style.color = colors.color;
    grid.append(panel);
    const head = Object.assign(document.createElement('div'), { className: 'tile-more-head' });
    const title = Object.assign(document.createElement('h3'), { textContent: tile.querySelector('h3').textContent });
    title.setAttribute('aria-hidden', 'true');
    const done = Object.assign(document.createElement('button'), { type: 'button', className: 'tile-close', textContent: 'Close' });
    done.addEventListener('click', close);
    head.append(title, done);
    panel.prepend(head);

    button.addEventListener('click', () => {
      current = { button, panel, tile };
      button.setAttribute('aria-expanded', 'true');
      if (stacked.matches) panel.style.top = `${tile.offsetTop}px`;
      panel.hidden = false;
      // The grid grows if the explanation needs more room than the tiles took.
      const needed = (stacked.matches ? tile.offsetTop : 0) + panel.scrollHeight;
      if (needed > grid.offsetHeight) grid.style.minHeight = `${needed}px`;
      grid.classList.add('open');
      const top = (stacked.matches ? tile : grid).getBoundingClientRect().top;
      if (top < 72) window.scrollBy({ top: top - 80 });
      done.focus({ preventScroll: true });
      if (reduceMotion) return panel.classList.add('shown');
      panel.style.clipPath = tileShape(tile, panel);
      // Two frames: the browser must draw the starting shape before it can grow.
      requestAnimationFrame(() => requestAnimationFrame(() => {
        panel.style.clipPath = `inset(0 ${round})`;
        panel.classList.add('shown');
      }));
    });
  }
  grid.addEventListener('keydown', event => { if (event.key === 'Escape') close(); });
}

// ---- Account menu: recognizes someone signed in to the web app on this
// site. The app and the site share an origin, so they share the sign-in; the
// SDK version matches the one the web app loads.
const SDK = 'https://www.gstatic.com/firebasejs/12.19.0';

function initials(user) {
  const source = user.displayName || user.email || '';
  return (source.match(/[A-Za-z]/g) || ['?']).slice(0, 2).join('').toUpperCase();
}

function menuItems(user) {
  if (user.isAnonymous) {
    return {
      title: 'Playing as a guest',
      note: 'Create an account to host rooms and save your lists.',
      items: [['Create an account or sign in', '/app/account'], ['Open the app', '/app']],
    };
  }
  return {
    title: `Signed in as ${user.displayName || user.email || 'you'}`,
    note: user.emailVerified ? 'Verified host' : 'Verify your email to host rooms.',
    items: [['Your account', '/app/account'], ['Open the app', '/app']],
    signOut: true,
  };
}

async function startAccountMenu() {
  const config = window.wdywFirebaseConfig;
  const root = document.getElementById('account');
  if (!config || !root) return;
  const [{ initializeApp }, { getAuth, onAuthStateChanged, signOut }] = await Promise.all([
    import(`${SDK}/firebase-app.js`), import(`${SDK}/firebase-auth.js`)]);
  const auth = getAuth(initializeApp(config));
  const button = document.getElementById('account-button');
  const menu = document.getElementById('account-menu');
  const close = () => { menu.hidden = true; button.setAttribute('aria-expanded', 'false'); };

  button.addEventListener('click', () => {
    const open = menu.hidden;
    menu.hidden = !open;
    button.setAttribute('aria-expanded', String(open));
    if (open) menu.querySelector('a, button')?.focus();
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && !menu.hidden) { close(); button.focus(); }
  });
  document.addEventListener('click', event => { if (!root.contains(event.target)) close(); });

  onAuthStateChanged(auth, user => {
    root.hidden = !user;
    document.getElementById('sign-in').hidden = Boolean(user);
    if (!user) return;
    const view = menuItems(user);
    document.getElementById('account-initials').textContent = user.isAnonymous ? 'G' : initials(user);
    document.getElementById('account-label').textContent = view.title;
    menu.innerHTML = '';
    const title = Object.assign(document.createElement('p'), { textContent: view.title });
    title.style.fontWeight = '800';
    const note = Object.assign(document.createElement('p'), { textContent: view.note, className: 'muted' });
    const list = document.createElement('ul');
    for (const [label, href] of view.items) {
      const item = document.createElement('li');
      item.append(Object.assign(document.createElement('a'), { textContent: label, href }));
      list.append(item);
    }
    if (view.signOut) {
      const item = document.createElement('li');
      const out = Object.assign(document.createElement('button'), { type: 'button', textContent: 'Sign out' });
      out.addEventListener('click', async () => { await signOut(auth); close(); });
      item.append(out);
      list.append(item);
    }
    menu.append(title, note, list);
  });
}

leanPhone();
followStory();
openTiles();
startAccountMenu().catch(() => {});
