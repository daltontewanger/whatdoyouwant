// The public site's two moving parts: the "See it in action" demo and the
// account menu. Both are optional; the page works fully without them.

const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

// ---- Demo: the phone cycles through a room from lobby to result.
const frames = [
  ['The lobby', `<strong>Room code</strong><span class="code">AB3 K7X</span>
    <span class="small">4 people joined</span><span>Distance: 5 mi</span><span>Cards: 10</span>
    <span class="cta">Start swiping</span>`],
  ['Swiping', `<div class="card" style="flex:1"><strong>Demo Thai Kitchen</strong>
    <div class="small">Thai · 2.4 mi · Open now</div></div>
    <div class="answers"><span class="no">No</span><span>Never</span><span class="yes">Yes</span></div>`],
  ['Waiting for votes', `<strong>Waiting for votes</strong><span class="small">3 of 4 done</span>
    <div style="height:10px;background:#e3ece7;border-radius:5px"><div style="width:75%;height:10px;background:#2f7a5c;border-radius:5px"></div></div>
    <span class="small" style="margin-top:auto">Results open when everyone finishes</span>`],
  ['The result', `<strong>The group picked</strong><div class="card"><strong>Demo Pho</strong>
    <div class="small">3 of 4 said yes</div></div>
    <span>Map and directions</span><span>Website</span><span>Call</span>`],
];

function startDemo() {
  const screen = document.getElementById('demo-screen');
  const dots = document.getElementById('demo-dots');
  const toggle = document.getElementById('demo-toggle');
  const step = document.getElementById('demo-step');
  const phone = document.getElementById('demo-phone');
  if (!screen) return;
  let index = 0;
  let timer = null;
  const buttons = frames.map(([name], i) => {
    const button = Object.assign(document.createElement('button'), { type: 'button' });
    button.setAttribute('aria-label', `Step ${i + 1}: ${name}`);
    // Picking a step stops the slideshow so it stays on what was chosen.
    button.addEventListener('click', () => { play(false); show(i); });
    dots.append(button);
    return button;
  });
  const show = next => {
    index = next;
    screen.innerHTML = frames[index][1];
    step.textContent = `Demo step ${index + 1} of ${frames.length}: ${frames[index][0]}`;
    buttons.forEach((button, i) => {
      if (i === index) button.setAttribute('aria-current', 'step');
      else button.removeAttribute('aria-current');
    });
  };
  const play = on => {
    clearInterval(timer);
    timer = on ? setInterval(() => show((index + 1) % frames.length), 2600) : null;
    toggle.textContent = on ? 'Pause demo' : 'Play demo';
  };
  show(0);
  play(!reduceMotion);
  toggle.addEventListener('click', () => play(!timer));

  // The phone leans a little toward the pointer, only where a pointer hovers.
  if (!reduceMotion && matchMedia('(hover: hover)').matches) {
    const band = phone.closest('section');
    band.addEventListener('pointermove', event => {
      const box = phone.getBoundingClientRect();
      const x = (event.clientX - (box.left + box.width / 2)) / window.innerWidth;
      const y = (event.clientY - (box.top + box.height / 2)) / window.innerHeight;
      phone.style.setProperty('--ry', `${(-10 + x * 24).toFixed(1)}deg`);
      phone.style.setProperty('--rx', `${(4 - y * 16).toFixed(1)}deg`);
    });
    band.addEventListener('pointerleave', () => {
      phone.style.removeProperty('--ry');
      phone.style.removeProperty('--rx');
    });
  }
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

startDemo();
startAccountMenu().catch(() => {});
