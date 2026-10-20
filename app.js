import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// ---------- הגדרות ----------
const SUPABASE_URL = 'https://fckpmdhcqbotnluflzpw.supabase.co';
const SUPABASE_KEY = 'sb_publishable_eG2bmu0PIEFFNu93ndOiqw_NA-K6nhB'; // מפתח ציבורי, מוגן ע"י הרשאות בשרת

const SPORTS = ["פוצ'יוולי", 'מטקות', 'כדורעף', 'פאדל', 'טניס'];
const DEFAULT_SIZE = { "פוצ'יוולי": 4, 'מטקות': 2, 'כדורעף': 6, 'פאדל': 4, 'טניס': 2 };
const COURT_SPORTS = ['פאדל', 'טניס'];
const LEVELS = ['מתחיל', 'מתחמם', 'סולידי', 'חזק', 'מפלצת'];
const TAGS = ['אווירה טובה', 'משחק הוגן', 'דיוק בזמנים'];
const KINDS = ['פארק', 'חוף', 'מגרש', 'אחר'];
const WHEN = ['עכשיו', 'עוד חצי שעה', 'בשקיעה'];

const SITE = 'https://galcohen1509-maker.github.io/maagal/';
const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce' } });
const ss = { get(k) { try { return sessionStorage.getItem(k); } catch { return null; } }, set(k, v) { try { sessionStorage.setItem(k, v); } catch {} }, del(k) { try { sessionStorage.removeItem(k); } catch {} } };
const isAnon = () => !!S.session?.user?.is_anonymous;
const authLabel = () => { const u = S.session?.user; if (!u || u.is_anonymous) return null;
  const g = (u.identities || []).some((i) => i.provider === 'google'); return g ? `Google · ${u.email || ''}` : (u.email || 'חשבון'); };
const authError = (e) => { const m = (e?.message || '').toLowerCase();
  if (m.includes('invalid login')) return 'מייל או סיסמה לא נכונים';
  if (m.includes('already registered') || m.includes('already been registered') || m.includes('already exists')) return 'המייל הזה כבר רשום. נסה "יש לי כבר חשבון"';
  if (m.includes('password')) return 'סיסמה של לפחות 6 תווים';
  if (m.includes('email')) return 'בדוק את כתובת המייל';
  return 'משהו השתבש. נסה שוב.'; };

// ---------- מצב ----------
const S = {
  session: null, profile: null, coords: null, locState: 'unknown',
  spots: [], circles: [], pending: [], after: null,
  channels: [], timers: [], form: null, rate: null, onboard: { sports: [] },
};
const $ = (id) => document.getElementById(id);

// ---------- כלים ----------
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const initials = (n) => esc((n || '?').trim().slice(0, 2));
const ago = (t) => {
  const m = Math.max(0, Math.round((Date.now() - new Date(t).getTime()) / 60000));
  if (m < 1) return 'עכשיו'; if (m < 60) return `לפני ${m} דק׳`;
  const h = Math.round(m / 60); return h < 24 ? `לפני ${h} שע׳` : `לפני ${Math.round(h / 24)} ימים`;
};
const meters = (m) => (m >= 1000 ? `${(m / 1000).toFixed(1)} ק״מ` : `${m} מטר`);
const place = (sp) => (sp.kind === 'מגרש' && sp.name.includes(', ') ? sp.name.split(', ')[1] : sp.short);
const statusClass = (s) => (s === 'בוער' ? 'b-hot' : s === 'מתחמם' ? 'b-warm' : 'b-quiet');
const ring = (m) => `<div class="match" style="background:conic-gradient(var(--sun) ${Math.max(0, Math.min(100, m)) * 3.6}deg,var(--sand) 0)"><span>${m}%</span></div>`;
const kmTo = (lat, lng) => { const c = S.coords; if (!c || lat == null) return null; const r = Math.PI / 180;
  const a = Math.sin((lat - c.lat) * r / 2) ** 2 + Math.cos(c.lat * r) * Math.cos(lat * r) * Math.sin((lng - c.lng) * r / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(a)); };
const navButtons = (lat, lng) => (lat == null ? '' : `<div class="chips">
  <a class="btn line" style="flex:1" href="https://waze.com/ul?ll=${lat},${lng}&navigate=yes" target="_blank" rel="noopener">${I.pin} Waze</a>
  <a class="btn line" style="flex:1" href="https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}" target="_blank" rel="noopener">${I.pin} מפות</a></div>`);
const store = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch {} } };

let toastT;
function toast(t) { const e = $('toast'); e.textContent = t; e.classList.add('show'); clearTimeout(toastT); toastT = setTimeout(() => e.classList.remove('show'), 3200); }

async function rpc(fn, args = {}) {
  const { data, error } = await sb.rpc(fn, args);
  if (error) { console.error(fn, error); throw error; }
  return data;
}
function fail(e) { console.error(e); toast('משהו השתבש. בדוק חיבור ונסה שוב.'); }

const I = {
  sun: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
  crew: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.5 3.4-5.5 6.5-5.5s5.7 2 6.5 5.5"/><circle cx="17" cy="9" r="2.5"/><path d="M17 14c2.3 0 4 1.5 4.6 4"/></svg>',
  me: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4.2-6 8-6s7 2 8 6"/></svg>',
  pin: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s7-6.2 7-12a7 7 0 1 0-14 0c0 5.8 7 12 7 12z"/><circle cx="12" cy="10" r="2.5"/></svg>',
  share: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.6 13.5 6.8 4M15.4 6.5l-6.8 4"/></svg>',
  google: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path fill="#4285F4" d="M22.6 12.2c0-.8-.1-1.5-.2-2.2H12v4.2h5.9a5 5 0 0 1-2.2 3.3v2.7h3.6c2.1-1.9 3.3-4.8 3.3-8z"/><path fill="#34A853" d="M12 23c3 0 5.5-1 7.3-2.7l-3.6-2.8c-1 .7-2.2 1.1-3.7 1.1-2.9 0-5.3-1.9-6.2-4.5H2.1v2.8A11 11 0 0 0 12 23z"/><path fill="#FBBC05" d="M5.8 14.1a6.6 6.6 0 0 1 0-4.2V7.1H2.1a11 11 0 0 0 0 9.8z"/><path fill="#EA4335" d="M12 5.4c1.6 0 3 .6 4.2 1.6l3.1-3.1A11 11 0 0 0 2.1 7.1l3.7 2.8C6.7 7.3 9.1 5.4 12 5.4z"/></svg>',
  lock: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>',
};

// ---------- מיקום ----------
function getLocation({ ask = false } = {}) {
  return new Promise((resolve) => {
    if (!('geolocation' in navigator)) { S.locState = 'none'; return resolve(null); }
    if (!ask && store.get('loc') !== '1') return resolve(S.coords);
    navigator.geolocation.getCurrentPosition(
      (p) => { S.coords = { lat: p.coords.latitude, lng: p.coords.longitude }; S.locState = 'ok'; store.set('loc', '1'); resolve(S.coords); },
      () => { S.locState = 'denied'; resolve(S.coords); },
      { enableHighAccuracy: true, timeout: 12000, maximumAge: 60000 });
  });
}

// ---------- ניווט ----------
function clearLive() {
  S.channels.forEach((c) => sb.removeChannel(c)); S.channels = [];
  S.timers.forEach(clearInterval); S.timers = [];
}
function go(hash) { if (location.hash === hash) route(); else location.hash = hash; }
window.addEventListener('hashchange', route);

function setTabs(active) {
  const tb = $('tabbar');
  if (!active) { tb.classList.add('hide'); return; }
  tb.classList.remove('hide');
  const pend = S.pending.length;
  tb.innerHTML = [['home', 'אקשן', I.sun, '#/'], ['crew', "החבר'ה", I.crew, '#/crew'], ['profile', 'פרופיל', I.me, '#/me']]
    .map(([id, l, ic, h]) => `<button class="tab ${active === id ? 'on' : ''}" data-go="${h}" aria-label="${l}">${ic}<span>${l}</span>${id === 'profile' && pend ? `<b class="cnt">${pend}</b>` : ''}</button>`).join('');
}
function screen(html, { tabs = null } = {}) {
  const el = $('screen');
  el.className = 'screen' + (tabs ? '' : ' notabs');
  el.innerHTML = html;
  setTabs(tabs);
  window.scrollTo(0, 0);
  el.style.animation = 'none'; void el.offsetWidth; el.style.animation = '';
}
function loading() { screen('<div class="spin" aria-label="טוען"></div>'); }

async function route() {
  clearLive(); closeSheet(); $('toast').classList.remove('show');
  const h = location.hash || '#/';
  const [, a, b] = h.split('/');
  if (!S.session || !S.profile) { S.after = h; return renderOnboard(); }
  if (a === 'c' && b) return renderCircle(b);
  if (a === 'rate' && b) return renderRate(b);
  if (a === 'spot' && b) return renderSpot(b);
  if (a === 'crew') return renderCrew();
  if (a === 'me') return renderProfile();
  return renderHome();
}

// ---------- כניסה ראשונה ----------
function renderOnboard() {
  const o = S.onboard; o.mode = o.mode || 'pick';
  const signed = S.session && !isAnon();
  const login = o.mode === 'login';
  const acct = signed
    ? `<div class="card"><div class="row start">${I.lock}<div style="flex:1"><b>מחובר</b><div class="muted small">${esc(authLabel())}</div></div></div></div>`
    : `<div class="card">
        <h2>${login ? 'כניסה לחשבון' : 'איך נכנסים?'}</h2>
        <button class="btn line" data-act="google">${I.google} המשך עם Google</button>
        ${o.mode === 'pick' ? `<button class="btn ghost" data-act="ob-mode" data-v="signup">או עם מייל וסיסמה</button>` : `
          <input id="email" class="field" type="email" inputmode="email" autocomplete="email" dir="ltr" placeholder="מייל" value="${esc(o.email || '')}">
          <input id="pass" class="field" type="password" autocomplete="${login ? 'current-password' : 'new-password'}" dir="ltr" placeholder="סיסמה, לפחות 6 תווים">
          <button class="linkbtn" data-act="ob-mode" data-v="${login ? 'signup' : 'login'}">${login ? 'אין לי חשבון, להירשם' : 'יש לי כבר חשבון'}</button>`}
        ${o.mode === 'pick' ? `<p class="muted small">אפשר גם בלי חשבון: רק כינוי, למטה. שומרים את הפרופיל מתי שבא לך.</p>` : ''}
      </div>`;
  screen(`
    <div class="row"><div class="brand">maagal</div></div>
    <h1>${login ? 'ברוך השב' : 'בא לך לשחק עכשיו?<br>יש מעגל שמחכה לך.'}</h1>
    ${login ? '' : '<p class="muted" style="font-size:16px">רואים מי בחוף ובמגרש, קופצים, משחקים. בלי טפסים ובלי מבחני רמה.</p>'}
    ${acct}
    ${login ? '' : `
    <div class="card">
      <label for="nick"><h2>איך קוראים לך בחוף?</h2></label>
      <input id="nick" class="field" maxlength="20" autocomplete="nickname" placeholder="כינוי, 2–20 אותיות" value="${esc(o.nick || '')}">
    </div>
    <div class="card">
      <h2>מה אתה משחק?</h2>
      <div class="chips">${SPORTS.map((s) => `<button class="chip pill ${o.sports.includes(s) ? 'on' : ''}" data-act="ob-sport" data-v="${esc(s)}" aria-pressed="${o.sports.includes(s)}">${esc(s)}</button>`).join('')}</div>
    </div>
    <div class="card">
      <div class="row start">${I.pin}<div style="flex:1"><b>מיקום</b><div class="muted small">נצטרך את המיקום המדויק שלך בשביל לדעת לאילו מקומות ומעגלים אתה קרוב.</div></div></div>
      <button class="btn line ${S.locState === 'ok' ? 'on' : ''}" data-act="ob-loc">${S.locState === 'ok' ? 'המיקום פועל' : S.locState === 'denied' ? 'המיקום חסום. אפשר להפעיל בהגדרות הדפדפן' : 'אפשר מיקום'}</button>
    </div>
    <p class="muted small">הרמה שלך? נגלה במגרש. אחרי 3 משחקים עם דירוגים מכל הצדדים, תקבל רמה אמיתית.</p>`}
    <div class="bottom low"><button class="btn sun" data-act="ob-go">${login ? 'כניסה' : signed || o.mode === 'signup' ? 'יאללה, תראו לי מה פתוח' : 'יאללה, רק עם כינוי'}</button></div>`);
  $('nick')?.addEventListener('input', (e) => { o.nick = e.target.value; });
  $('email')?.addEventListener('input', (e) => { o.email = e.target.value; });
}

async function googleSignIn(link) {
  ss.set('after', S.after || location.hash || '#/');
  if (S.onboard.nick) ss.set('nick', S.onboard.nick);
  if (S.onboard.sports.length) ss.set('sports', JSON.stringify(S.onboard.sports));
  const opts = { provider: 'google', options: { redirectTo: SITE } };
  const { error } = link ? await sb.auth.linkIdentity(opts) : await sb.auth.signInWithOAuth(opts);
  if (error) toast(authError(error));
}

async function finishOnboard(btn) {
  const o = S.onboard;
  const email = ($('email')?.value || '').trim(), pass = $('pass')?.value || '';
  btn.disabled = true;
  try {
    if (o.mode === 'login') {
      const { data, error } = await sb.auth.signInWithPassword({ email, password: pass });
      if (error) { btn.disabled = false; return toast(authError(error)); }
      S.session = data.session;
      S.profile = await rpc('my_profile');
      if (!S.profile) { o.mode = 'pick'; btn.disabled = false; toast('נכנסת. עכשיו רק כינוי וספורט.'); return renderOnboard(); }
    } else {
      const nick = (o.nick || '').trim();
      if (nick.length < 2) { btn.disabled = false; toast('כינוי של לפחות 2 אותיות'); $('nick')?.focus(); return; }
      if (!S.session) {
        if (o.mode === 'signup') {
          const { data, error } = await sb.auth.signUp({ email, password: pass });
          if (error) { btn.disabled = false; return toast(authError(error)); }
          if (!data.session) { btn.disabled = false; return toast('נרשמת. נכנס עם המייל והסיסמה.'); }
          S.session = data.session;
        } else {
          const { data, error } = await sb.auth.signInAnonymously();
          if (error) throw error;
          S.session = data.session;
        }
      }
      await rpc('save_profile', { p_nickname: nick, p_sports: o.sports });
      S.profile = await rpc('my_profile');
    }
    const target = S.after && S.after !== '#/' ? S.after : '#/';
    S.after = null; go(target);
  } catch (e) { btn.disabled = false; fail(e); }
}

// ---------- המסך הראשי ----------
async function loadHome() {
  const c = S.coords || {};
  const [spots, circles, pending] = await Promise.all([
    rpc('spot_feed', { p_lat: c.lat ?? null, p_lng: c.lng ?? null }),
    rpc('circle_feed', { p_lat: c.lat ?? null, p_lng: c.lng ?? null, p_spot: null }),
    rpc('pending_ratings'),
  ]);
  S.spots = spots || []; S.circles = circles || []; S.pending = pending || [];
}

function spotCard(sp) {
  return `<div class="card ${sp.status === 'בוער' ? 'hot' : ''}">
    <div class="row link" data-go="#/spot/${esc(sp.id)}" style="cursor:pointer">
      <div><div style="font-size:18px;font-weight:700">${esc(sp.name)} <span class="muted">›</span></div>
      <div class="muted small">${esc(sp.kind)}${sp.minutes != null ? ` · ${sp.minutes} דק׳ נסיעה` : ''}</div></div>
      <span class="badge ${statusClass(sp.status)}">${esc(sp.status)}</span></div>
    <div style="font-size:14px"><b>${sp.people}</b> שם עכשיו · <b>${sp.open_circles}</b> מעגלים פתוחים</div>
    ${sp.crew_here.length ? `<div class="chips" style="gap:6px"><span class="tag warm">${sp.crew_here.map(esc).join(', ')} שם</span></div>` : ''}
    <button class="btn line ${sp.i_am_here ? 'on' : ''}" data-act="${sp.i_am_here ? 'checkout' : 'checkin'}" data-v="${esc(sp.id)}">${sp.i_am_here ? 'אתה כאן · לחץ ליציאה' : 'אני פה'}</button>
  </div>`;
}
function circleCard(c) {
  return `<div class="card link" data-go="#/c/${c.id}">
    <div class="row start">${ring(c.match)}
      <div style="flex:1"><b>${esc(c.sport)} · ${esc(c.spot_short)}</b>
        <div class="muted small">${esc(c.organizer_nick)} מארגן · ${esc(c.starts_label)} · רמה ${esc(c.avg_label || '')}</div>
        <div style="font-size:13px;margin-top:2px"><b>${c.members}/${c.size}</b> · ${c.status === 'full' ? 'מלא' : `חסרים ${c.size - c.members}`}${c.minutes != null ? ` · ${c.minutes} דק׳` : ''}</div>
        ${c.court_info ? `<div class="small" style="color:var(--sea);font-weight:500;margin-top:3px">${esc(c.court_info)}</div>` : ''}
      </div>${c.i_am_in ? '<span class="badge b-warm">אתה בפנים</span>' : ''}</div></div>`;
}

async function renderHome() {
  if (!S.spots.length) loading();
  try { await loadHome(); } catch (e) { return fail(e); }
  const mine = S.circles.filter((c) => c.i_am_in);
  const forMe = S.circles.filter((c) => !c.i_am_in && c.status === 'open');
  const crewSeen = S.spots.filter((s) => s.crew_here.length);
  const near = S.spots[0];
  screen(`
    <div class="row" style="align-items:flex-end">
      <div><div class="muted small">${S.coords ? (near ? `הכי קרוב: ${esc(near.short)}` : '') : 'בלי מיקום, הרשימה לא ממוינת'}</div>
      <h1>איפה יש אקשן עכשיו</h1></div>
      <div class="brand" style="font-size:18px">maagal</div>
    </div>
    ${!S.coords ? `<div class="banner sea">${I.pin}<span>תן מיקום ונראה לך מה הכי קרוב</span><button class="chip sm" data-act="loc">הפעל</button></div>` : ''}
    ${S.pending.length ? `<div class="banner"><span><b>איך היה ב${esc(S.pending[0].spot_short)}?</b> 10 שניות לדרג</span><button class="chip sm on" data-go="#/rate/${S.pending[0].id}">לדרג</button></div>` : ''}
    ${crewSeen.map((s) => `<div class="banner"><span><b>${s.crew_here.map(esc).join(' ו')}</b> ב${esc(s.short)} עכשיו</span></div>`).join('')}
    ${mine.length ? `<h2>המעגלים שלך</h2>${mine.map(circleCard).join('')}` : ''}
    <div class="row"><h2>מעגלים פתוחים בשבילך</h2><span class="muted small">לפי התאמה</span></div>
    ${forMe.length ? forMe.slice(0, 5).map(circleCard).join('') : `<div class="card"><p>אין כרגע מעגל פתוח. תהיה הראשון להרים, החבר'ה יראו את זה.</p></div>`}
    <h2>מקומות</h2>
    ${S.spots.map(spotCard).join('')}
    <div class="card"><b>אתה במקום טוב לשחק שלא ברשימה?</b><p class="muted small">פארק, גינה, מגרש שכונתי. סמן אותו, והחבר'ה יראו.</p>
      <button class="btn line" data-act="new-spot">${I.pin} מקום חדש כאן</button></div>
    <p class="muted small">"אני פה" עובד רק כשאתה באמת ליד המקום. ככה המספרים אמיתיים.</p>
    <div class="bottom"><button class="btn sun" data-act="new-circle">מרים מעגל</button></div>`, { tabs: 'home' });

  // עדכונים חיים: כל שינוי במעגלים מרענן
  let t;
  const refresh = () => { clearTimeout(t); t = setTimeout(() => { if ((location.hash || '#/') === '#/') renderHomeSilent(); }, 600); };
  S.channels.push(sb.channel('home')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'circles' }, refresh)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'circle_members' }, refresh)
    .subscribe());
  S.timers.push(setInterval(refresh, 45000));
}
async function renderHomeSilent() { const y = window.scrollY; clearLive(); await renderHome(); window.scrollTo(0, y); }

async function doCheckin(spotId, btn) {
  btn.disabled = true; btn.textContent = 'בודק מיקום...';
  const c = await getLocation({ ask: true });
  if (!c) { btn.disabled = false; btn.textContent = 'אני פה'; return toast('צריך מיקום כדי לאמת שאתה פה. אפשר להפעיל בהגדרות הדפדפן.'); }
  try {
    const r = await rpc('check_in', { p_spot: spotId, p_lat: c.lat, p_lng: c.lng });
    if (!r.ok) { btn.disabled = false; btn.textContent = 'אני פה'; return toast(`אתה ${meters(r.meters)} מהמקום. "אני פה" נפתח כשאתה ממש שם.`); }
    toast('סימנו אותך. החבר\'ה שלך יראו.'); route();
  } catch (e) { btn.disabled = false; btn.textContent = 'אני פה'; fail(e); }
}

// ---------- עמוד מקום ----------
async function renderSpot(id) {
  loading();
  const c = S.coords || {};
  let spots, circles;
  try {
    [spots, circles] = await Promise.all([
      rpc('spot_feed', { p_lat: c.lat ?? null, p_lng: c.lng ?? null }),
      rpc('circle_feed', { p_lat: c.lat ?? null, p_lng: c.lng ?? null, p_spot: id }),
    ]);
  } catch (e) { return fail(e); }
  const sp = (spots || []).find((s) => s.id === id);
  if (!sp) return screen('<p class="empty">המקום לא נמצא</p><button class="btn ghost" data-go="#/">חזרה</button>');
  screen(`
    <button class="linkbtn" data-go="#/" style="align-self:flex-start">חזרה</button>
    <div class="row"><div><h1>${esc(sp.name)}</h1><div class="muted small">${esc(sp.kind)}${sp.minutes != null ? ` · ${sp.minutes} דק׳ נסיעה` : ''}</div></div>
      <span class="badge ${statusClass(sp.status)}">${esc(sp.status)}</span></div>
    <div class="grid3">
      <div class="stat"><b>${sp.people}</b><span class="muted small">שם עכשיו</span></div>
      <div class="stat"><b>${(circles || []).length}</b><span class="muted small">מעגלים</span></div>
      <div class="stat"><b>${sp.crew_here.length}</b><span class="muted small">מהחבר'ה</span></div>
    </div>
    <div class="chips" style="gap:6px">${sp.sports.map((s) => `<span class="tag" style="background:var(--card)">${esc(s)}</span>`).join('')}</div>
    ${navButtons(sp.lat, sp.lng)}
    <h2>מעגלים פתוחים</h2>
    ${(circles || []).length ? circles.map(circleCard).join('') + '<p class="muted small">האחוז = כמה המעגל מתאים לך: רמה, מרחק, חבר\'ה ואמינות המארגן.</p>'
      : `<div class="card"><p>אין פה מעגל פתוח כרגע.</p><button class="btn sun" style="min-height:48px;font-size:15px" data-act="new-circle" data-v="${esc(sp.id)}">תהיה הראשון להרים</button></div>`}
    <button class="btn line ${sp.i_am_here ? 'on' : ''}" data-act="${sp.i_am_here ? 'checkout' : 'checkin'}" data-v="${esc(sp.id)}">${sp.i_am_here ? 'אתה כאן · לחץ ליציאה' : 'אני פה'}</button>
    <div class="bottom low"><button class="btn sun" data-act="new-circle" data-v="${esc(sp.id)}">מרים מעגל פה</button></div>`);
}

// ---------- מרים מעגל ----------
function openSheet(html) { $('sheet').innerHTML = `<div class="handle"></div>${html}`; $('app').classList.add('open'); }
function closeSheet() { $('app').classList.remove('open'); }
$('backdrop').addEventListener('click', closeSheet);

async function startNewCircle(spotId) {
  if (!S.spots.length) { try { await loadHome(); } catch (e) { return fail(e); } }
  const here = S.spots.find((s) => s.i_am_here);
  const firstSport = (S.profile?.sports || []).find((s) => SPORTS.includes(s)) || SPORTS[0];
  const spot = spotId || here?.id || S.spots.find((s) => s.sports.includes(firstSport))?.id || S.spots[0]?.id;
  const sport = S.spots.find((s) => s.id === spot)?.sports.includes(firstSport) ? firstSport : (S.spots.find((s) => s.id === spot)?.sports[0] || firstSport);
  // אין מקום מוכר לידך: ברירת המחדל היא לפתוח איפה שאתה עומד
  const farFromAll = S.coords && !spotId && !here && !(S.spots[0]?.km != null && S.spots[0].km <= 0.3);
  S.form = { spot, sport, size: DEFAULT_SIZE[sport] || 4, label: 'עכשיו', open: false, court: '', newSpot: farFromAll ? { name: '', kind: 'פארק' } : null };
  renderSheet();
}
function renderSheet() {
  const f = S.form;
  const spotsFor = S.spots.filter((s) => s.sports.includes(f.sport) || !s.sports.length || s.id === f.spot);
  if (!spotsFor.find((s) => s.id === f.spot)) f.spot = spotsFor[0]?.id;
  const sp = f.newSpot ? null : S.spots.find((s) => s.id === f.spot);
  const court = COURT_SPORTS.includes(f.sport);
  openSheet(`
    <h1 style="font-size:26px">מרים מעגל${sp ? ` ב${esc(place(sp))}` : f.newSpot ? ' איפה שאתה עומד' : ''}</h1>
    <div><h3 style="margin-bottom:8px">משחקים</h3><div class="chips">${SPORTS.map((s) => `<button class="chip ${f.sport === s ? 'on' : ''}" data-act="f-sport" data-v="${esc(s)}">${esc(s)}</button>`).join('')}</div></div>
    <div><h3 style="margin-bottom:8px">איפה</h3><div class="chips">${spotsFor.slice(0, 6).map((s) => `<button class="chip sm ${!f.newSpot && f.spot === s.id ? 'on' : ''}" data-act="f-spot" data-v="${esc(s.id)}">${esc(s.short)}${s.minutes != null ? ` · ${s.minutes} דק׳` : ''}</button>`).join('')}
      <button class="chip sm ${f.newSpot ? 'on' : ''}" data-act="f-newspot">${I.pin} איפה שאני עומד</button></div>
      ${f.newSpot ? newSpotFields(f.newSpot) : ''}</div>
    <div class="row"><div><h3>כמה חסרים?</h3><div class="muted small">סה״כ ${f.size} במגרש, כולל אותך</div></div>
      <div class="stepper"><button class="round" data-act="f-size" data-v="-1" aria-label="פחות">−</button><b style="font-size:24px">${f.size - 1}</b><button class="round on" data-act="f-size" data-v="1" aria-label="יותר">+</button></div></div>
    <div><h3 style="margin-bottom:8px">מי מוזמן?</h3><div class="chips">
      <button class="chip ${!f.open ? 'on' : ''}" style="flex:1" data-act="f-open" data-v="0">בערך ברמה שלי</button>
      <button class="chip ${f.open ? 'on' : ''}" style="flex:1" data-act="f-open" data-v="1">פתוח לכולם</button></div></div>
    <div><h3 style="margin-bottom:8px">מתי?</h3><div class="grid3">${WHEN.map((w) => `<button class="chip ${f.label === w ? 'on' : ''}" data-act="f-when" data-v="${esc(w)}">${esc(w)}</button>`).join('')}</div></div>
    ${court ? `<div><label for="court"><h3 style="margin-bottom:8px">מגרש</h3></label>
      <input id="court" class="field" maxlength="80" placeholder="למשל: מגרש 2 שמור, 19:00, ₪60 לשחקן" value="${esc(f.court)}">
      <p class="muted small" style="margin-top:6px">הזמנת מגרש מתוך האפליקציה תגיע בהמשך. בינתיים כתוב פה מה שמור.</p></div>` : ''}
    <button class="btn sun" data-act="f-create">תרים את המעגל</button>
    <p class="muted small" style="text-align:center">המעגל נסגר לבד כשמתמלא או אחרי שעה</p>`);
  const ci = $('court'); if (ci) ci.addEventListener('input', (e) => { f.court = e.target.value; });
  $('nsname')?.addEventListener('input', (e) => { f.newSpot.name = e.target.value; });
}
function newSpotFields(ns) {
  return `<div class="card" style="background:var(--sand);margin-top:10px;gap:8px">
    <label for="nsname" class="small"><b>איך קוראים למקום?</b> <span class="muted">(לא חובה)</span></label>
    <input id="nsname" class="field" maxlength="30" placeholder="למשל: גינת הכלנית, מגרש הדשא ליד הבית" value="${esc(ns.name || '')}">
    <div class="chips">${KINDS.map((k) => `<button class="chip sm ${ns.kind === k ? 'on' : ''}" data-act="ns-kind" data-v="${esc(k)}">${esc(k)}</button>`).join('')}</div>
    <p class="muted small">הנקודה נקבעת לפי המיקום שלך עכשיו. מי שבסביבה יראה אותה ויוכל לנווט אליה. אם כבר יש מקום ממש קרוב, נשתמש בו.</p></div>`;
}
async function placeSpotHere(ns, sport) {
  let name = (ns.name || '').trim();
  if (name.length === 1) { toast('שם של לפחות 2 אותיות, או בלי שם בכלל'); return null; }
  if (!name) name = `הנקודה של ${S.profile?.nickname || 'שחקן'}`.slice(0, 30);
  const c = await getLocation({ ask: true });
  if (!c) { toast('צריך מיקום כדי ליצור מקום. אפשר להפעיל בהגדרות הדפדפן.'); return null; }
  const r = await rpc('add_spot', { p_name: name, p_kind: ns.kind || 'פארק', p_sports: sport ? [sport] : (S.profile?.sports || []), p_lat: c.lat, p_lng: c.lng });
  if (!r.ok) { toast(r.reason === 'limit' ? 'הגעת למגבלה של 5 מקומות חדשים היום' : 'תן שם למקום, לפחות 2 אותיות'); return null; }
  if (r.existing) toast(`כבר יש פה מקום: ${r.name}. השתמשנו בו.`);
  return r.id;
}
function openNewSpotSheet() {
  S.ns = S.ns || { name: '', kind: 'פארק' };
  openSheet(`<h1 style="font-size:26px">מקום חדש כאן</h1>
    <p class="muted">בפארק, בגינה, או בכל מקום טוב לקפיצות. החבר'ה יראו שיש פה אקשן.</p>
    ${newSpotFields(S.ns)}
    <button class="btn sun" data-act="ns-save">סמן אותי פה</button>`);
  $('nsname')?.addEventListener('input', (e) => { S.ns.name = e.target.value; });
}
async function createCircle(btn) {
  const f = S.form; if (!f.spot && !f.newSpot) return toast('בחר מקום');
  btn.disabled = true;
  try {
    if (f.newSpot) { const sid = await placeSpotHere(f.newSpot, f.sport); if (!sid) { btn.disabled = false; return; } f.spot = sid; f.newSpot = null; }
    const id = await rpc('create_circle', { p_spot: f.spot, p_sport: f.sport, p_size: f.size, p_label: f.label, p_open: f.open, p_court: f.court.trim() || null });
    closeSheet(); S.justCreated = id; go(`#/c/${id}`);
  } catch (e) { btn.disabled = false; fail(e); }
}

// ---------- מעגל ----------
async function copyLink(url) {
  try { await navigator.clipboard.writeText(url); }
  catch { const t = document.createElement('textarea'); t.value = url; document.body.appendChild(t); t.select();
    try { document.execCommand('copy'); } catch {} t.remove(); }
  toast('הלינק הועתק. אפשר להדביק בכל מקום.');
}
function inviteUrl(id) { return `${location.origin}${location.pathname}#/c/${id}`; }
async function invite(c) {
  const url = inviteUrl(c.id);
  const text = `בוא למעגל ${c.sport} ב${place(c.spot)} (${c.starts_label}). חסרים ${c.size - c.members.length}:\n${url}`;
  if (navigator.share) { try { await navigator.share({ title: 'maagal', text }); return; } catch (e) { if (e.name === 'AbortError') return; } }
  window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, '_blank', 'noopener');
}

async function renderCircle(id) {
  loading();
  let c, msgs = [];
  try {
    c = await rpc('circle_detail', { p_circle: id });
    if (c?.i_am_in) { const r = await sb.from('messages').select('*').eq('circle_id', id).order('id'); msgs = r.data || []; }
  } catch (e) { return fail(e); }
  if (!c) return screen('<p class="empty">המעגל לא נמצא. אולי הלינק לא שלם?</p><button class="btn ghost" data-go="#/">למסך הראשי</button>');
  S.circle = c; S.msgs = msgs;
  drawCircle();

  const reload = async () => { try { S.circle = await rpc('circle_detail', { p_circle: id }); drawCircle(true); } catch {} };
  const ch = sb.channel(`c-${id}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'circle_members', filter: `circle_id=eq.${id}` }, reload)
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'circles', filter: `id=eq.${id}` }, reload);
  if (c.i_am_in) ch.on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages', filter: `circle_id=eq.${id}` }, (p) => {
    if (!S.msgs.find((m) => m.id === p.new.id)) { S.msgs.push(p.new); drawChat(); }
  });
  S.channels.push(ch.subscribe());
  if (S.justCreated === id) { S.justCreated = null; setTimeout(() => toast('המעגל באוויר. שלח לחבר\'ה את הלינק.'), 300); }
}

function drawCircle(keepScroll) {
  const c = S.circle; const me = S.session.user.id;
  const n = c.members.length; const missing = Math.max(0, c.size - n);
  const isOrg = c.organizer === me;
  const status = c.status === 'cancelled' ? 'המעגל בוטל' : c.status === 'done' ? 'המשחק נגמר' : c.status === 'full' ? 'המעגל מלא' : 'המעגל באוויר';
  const y = window.scrollY;
  let actions = '';
  if (c.status === 'done') actions = c.i_am_in && !c.i_rated ? `<button class="btn sea" data-go="#/rate/${c.id}">לדירוג</button>` : `<button class="btn mute" data-go="#/">למסך הראשי</button>`;
  else if (c.status === 'cancelled') actions = `<button class="btn mute" data-go="#/">למסך הראשי</button>`;
  else if (!c.i_am_in) actions = c.status === 'open' ? `<button class="btn sun" data-act="join">הצטרף</button>` : `<button class="btn mute" disabled>המעגל מלא</button>`;
  else actions = `<button class="btn wa" data-act="invite">${I.share} הזמן חבר</button>${n >= 2 ? `<button class="btn sea" data-act="finish">המשחק נגמר</button>` : ''}`;

  screen(`
    <button class="linkbtn" data-go="#/" style="align-self:flex-start">חזרה</button>
    <div class="live"><span class="dot"></span>${status}</div>
    <h1>${esc(c.sport)} ב${esc(place(c.spot))}</h1>
    ${c.court_info ? `<div class="banner sea" style="padding:10px 14px">${esc(c.court_info)}</div>` : ''}
    <p class="muted">${esc(c.starts_label)} · ${c.open_to_all ? 'פתוח לכולם' : 'בערך באותה רמה'} · ${c.status === 'open' ? `חסרים עוד ${missing}` : `${n} שחקנים`}</p>
    ${['open', 'full'].includes(c.status) && c.spot.lat != null ? `<div class="card" style="gap:8px">
      <div class="row"><b>איך מגיעים</b>${kmTo(c.spot.lat, c.spot.lng) != null ? `<span class="muted small">${meters(Math.round(kmTo(c.spot.lat, c.spot.lng) * 1000))} ממך</span>` : ''}</div>
      ${navButtons(c.spot.lat, c.spot.lng)}</div>` : ''}
    <div class="card">${c.members.map((m) => `<div class="row start"><div class="avatar">${initials(m.nickname)}</div>
        <div style="flex:1;font-weight:500">${esc(m.nickname)}${m.id === me ? ' (אתה)' : ''}${m.level ? ` <span class="tag lvl">${esc(m.level)}</span>` : ''}</div>
        <span class="muted small">${m.is_organizer ? 'מארגן' : 'בפנים'}</span></div>`).join('')}
      ${c.status === 'open' ? Array.from({ length: missing }).map(() => `<div class="row start" style="opacity:.5"><div class="avatar" style="background:var(--sand);color:var(--muted)">?</div><div>מחכים לשחקן...</div></div>`).join('') : ''}
    </div>
    ${c.i_am_in && c.status !== 'cancelled' ? `<div class="card"><h3>צ'אט המעגל</h3><div class="feed" id="feed"></div>
      <div class="chips">${['אני 5 דק׳ מפה', 'איפה אתם בדיוק?', 'יש לי כדור', 'תחכו לי'].map((q) => `<button class="chip sm" data-act="say" data-v="${esc(q)}">${esc(q)}</button>`).join('')}</div>
      <form class="sendrow" data-form="chat"><input class="field" id="chatin" maxlength="300" placeholder="הודעה..." aria-label="הודעה"><button type="submit">שלח</button></form></div>` : ''}
    ${['open', 'full'].includes(c.status) ? `<button class="btn line" data-act="copy-link" data-v="${esc(inviteUrl(c.id))}">${I.share} העתק לינק למעגל</button>` : ''}
    ${c.i_am_in && ['open', 'full'].includes(c.status) ? `<button class="linkbtn mute" data-act="leave" style="align-self:center">${isOrg ? 'בטל את המעגל' : 'יצאתי מהמעגל'}</button>` : ''}
    <div class="bottom low">${actions}</div>`);
  drawChat();
  if (keepScroll) window.scrollTo(0, y);
}
function drawChat() {
  const f = $('feed'); if (!f) return; const me = S.session.user.id;
  f.innerHTML = S.msgs.length ? S.msgs.map((m) => `<div class="msg ${m.user_id === me ? 'me' : 'them'}">${m.user_id === me ? '' : `<b>${esc(m.nickname)}</b>`}${esc(m.body)}</div>`).join('')
    : '<p class="muted small">עוד אין הודעות. זרוק משהו:</p>';
  f.scrollTop = f.scrollHeight;
}
async function say(text) {
  text = (text || '').trim(); if (!text) return;
  try { await rpc('send_message', { p_circle: S.circle.id, p_body: text }); } catch (e) { fail(e); }
}

// ---------- דירוג ----------
async function renderRate(id) {
  loading();
  let c; try { c = await rpc('circle_detail', { p_circle: id }); } catch (e) { return fail(e); }
  if (!c || !c.i_am_in) return screen('<p class="empty">אפשר לדרג רק משחק ששיחקת בו.</p><button class="btn ghost" data-go="#/">חזרה</button>');
  if (c.status !== 'done') return go(`#/c/${id}`);
  const me = S.session.user.id;
  S.rate = { c, happened: true, noShows: [], items: Object.fromEntries(c.members.filter((m) => m.id !== me).map((m) => [m.id, { level: null, tags: [], again: false }])) };
  drawRate();
}
function drawRate() {
  const r = S.rate; const c = r.c; const me = S.session.user.id;
  const others = c.members.filter((m) => m.id !== me);
  screen(`
    <div class="live">${esc(c.sport)} · ${esc(c.spot.short)}</div>
    <h1>נגמר המשחק. איך היה?</h1>
    <div class="card"><h2>המשחק באמת קרה?</h2><div class="chips">
      <button class="chip ${r.happened ? 'on' : ''}" style="flex:1" data-act="r-happened" data-v="1">כן, שיחקנו</button>
      <button class="chip ${!r.happened ? 'on' : ''}" style="flex:1" data-act="r-happened" data-v="0">לא, בוטל</button></div></div>
    ${r.happened ? `
      <div class="card"><h3>מישהו הבריז?</h3><div class="chips">${others.map((m) => `<button class="chip sm ${r.noShows.includes(m.id) ? 'on' : ''}" data-act="r-noshow" data-v="${m.id}">${esc(m.nickname)}</button>`).join('')}</div>
      <p class="muted small">מי שמבריז הרבה יורד בעדיפות. מי שמסומן לא מדורג.</p></div>
      ${others.filter((m) => !r.noShows.includes(m.id)).map((m) => { const it = r.items[m.id]; return `<div class="card">
        <div class="row start"><div class="avatar">${initials(m.nickname)}</div><b style="flex:1">${esc(m.nickname)}</b>
          <button class="linkbtn mute small" data-act="report" data-v="${m.id}">דווח</button></div>
        <div style="font-size:14px;font-weight:500">איך הייתה הרמה היום?</div>
        <div class="grid5">${LEVELS.map((l, i) => `<button class="chip ${it.level === i + 1 ? 'on' : ''}" style="padding:0 2px;font-size:12px" data-act="r-level" data-v="${m.id}:${i + 1}">${l}</button>`).join('')}</div>
        <div class="chips" style="gap:6px">${TAGS.map((t) => `<button class="chip sm pill" style="${it.tags.includes(t) ? 'background:var(--sunL);border-color:var(--sunL)' : ''}" data-act="r-tag" data-v="${m.id}:${esc(t)}">${esc(t)}</button>`).join('')}</div>
        <label class="tog"><span>בא לי עוד משחק ביחד</span><input type="checkbox" data-act="r-again" data-v="${m.id}" ${it.again ? 'checked' : ''}></label>
      </div>`; }).join('')}` : ''}
    <p class="row start muted small" style="gap:8px">${I.lock}אף אחד לא רואה מי נתן מה. הדירוגים נכנסים רק אחרי שכולם דירגו, או אחרי 24 שעות.</p>
    <div class="bottom low"><button class="btn sun" data-act="r-send">שלח</button></div>`);
}
async function sendRating(btn) {
  const r = S.rate;
  const items = Object.entries(r.items).filter(([id, it]) => !r.noShows.includes(id) && it.level).map(([ratee, it]) => ({ ratee, level: it.level, tags: it.tags, again: it.again }));
  if (r.happened && !items.length && Object.keys(r.items).length > r.noShows.length) return toast('דרג לפחות שחקן אחד');
  btn.disabled = true;
  try {
    await rpc('submit_ratings', { p_circle: r.c.id, p_happened: r.happened, p_no_shows: r.noShows, p_items: items });
    S.pending = S.pending.filter((p) => p.id !== r.c.id);
    toast(r.happened ? 'תודה, זה נכנס. הרמה מתעדכנת כשכולם דירגו.' : 'רשמנו שהמשחק בוטל.');
    go('#/');
  } catch (e) { btn.disabled = false; fail(e); }
}

// ---------- החבר'ה ----------
async function renderCrew() {
  loading();
  let crew; try { crew = await rpc('my_crew'); } catch (e) { return fail(e); }
  const here = (crew || []).filter((p) => p.spot_short), away = (crew || []).filter((p) => !p.spot_short);
  const row = (p) => `<div class="row start"><div class="avatar" style="${p.spot_short ? 'box-shadow:0 0 0 3px var(--sun)' : ''}">${initials(p.nickname)}</div>
    <div style="flex:1"><b>${esc(p.nickname)}</b><div class="muted small">${p.spot_short ? `ב${esc(p.spot_short)} · ${ago(p.since)}` : 'לא במקום כרגע'}</div></div></div>`;
  screen(`
    <h1>החבר'ה שלי</h1>
    <p class="muted">שחקנים שסימנת "בא לי עוד משחק ביחד". כשהם בחוף או במגרש, תראה את זה כאן ובמסך הראשי.</p>
    ${(crew || []).length ? `
      ${here.length ? `<div class="card"><h3>במקום עכשיו</h3>${here.map(row).join('')}</div>` : ''}
      ${away.length ? `<div class="card"><h3>לא במקום</h3>${away.map(row).join('')}</div>` : ''}`
      : `<div class="card"><p>עוד אין לך חבר'ה פה. אחרי משחק, בדירוג, סמן "בא לי עוד משחק ביחד" ליד מי שהיה כיף איתו.</p></div>`}
    <div class="card"><h3>מי רואה אותך במקום?</h3>
      <div class="seg">${[['all', 'כולם'], ['crew', "רק החבר'ה"], ['none', 'אף אחד']].map(([v, l]) => `<button class="${S.profile.visibility === v ? 'on' : ''}" data-act="vis" data-v="${v}">${l}</button>`).join('')}</div>
      <p class="muted small">${{ all: 'רואים את השם שלך רק החבר\'ה שלך. כל השאר רואים רק את מספר השחקנים.', crew: 'רק החבר\'ה שלך יראו שאתה במקום. כולם יראו רק את מספר השחקנים.', none: 'אף אחד לא יראה אותך. עדיין תיספר במספר השחקנים.' }[S.profile.visibility]}</p>
    </div>
    <div class="card"><h3>להביא את החבר'ה</h3><p class="muted small">שלח להם את הלינק לאפליקציה. נכנסים עם כינוי, בלי הרשמה.</p>
      <button class="btn line" data-act="copy-link" data-v="${esc(SITE)}">${I.share} העתק לינק לאפליקציה</button></div>`, { tabs: 'crew' });
}

// ---------- פרופיל ----------
async function renderProfile() {
  loading();
  try { await rpc('refresh_my_levels'); S.profile = await rpc('my_profile'); S.pending = (await rpc('pending_ratings')) || []; } catch (e) { return fail(e); }
  const p = S.profile; const need = Number(p.games_for_level) || 3;
  const lv = p.levels || [];
  const tags = Object.entries(p.tags || {});
  screen(`
    <div class="row start" style="gap:14px"><div class="avatar" style="width:68px;height:68px;font-size:24px;background:var(--sea);color:#fff">${initials(p.nickname)}</div>
      <div style="flex:1"><h1 style="font-size:28px">${esc(p.nickname)}</h1><div class="muted small">${(p.sports || []).map(esc).join(' · ') || 'בחר ספורט למטה'}</div></div></div>
    ${S.pending.map((x) => `<div class="banner"><span>מחכה לדירוג שלך: <b>${esc(x.sport)} ב${esc(x.spot_short)}</b></span><button class="chip sm on" data-go="#/rate/${x.id}">לדרג</button></div>`).join('')}
    <div class="grid3"><div class="stat"><b>${p.games}</b><span class="muted small">משחקים</span></div>
      <div class="stat"><b>${p.reliability}%</b><span class="muted small">הגעה</span></div>
      <div class="stat"><b>${p.crew_count}</b><span class="muted small">חבר'ה</span></div></div>
    ${lv.length ? lv.map((l) => `<div class="card"><div class="row"><b>${esc(l.sport)}</b>
        <span class="badge ${l.confirmed ? 'b-warm' : 'b-quiet'}">${l.confirmed ? esc(l.label) : 'בבנייה'}</span></div>
        <div class="bar"><div style="width:${l.confirmed ? Math.round(((l.level - 1) / 4) * 100) : Math.min(100, Math.round((l.games / need) * 100))}%;${l.confirmed ? '' : 'background:var(--sea)'}"></div></div>
        ${l.confirmed ? `<div class="row muted small"><span>מתחיל</span><span>מתחמם</span><span>סולידי</span><span>חזק</span><span>מפלצת</span></div>
          <p class="muted small">מבוסס על ${l.games} משחקים ו-${l.raters} מדרגים שונים</p>`
          : `<p class="muted small">${Math.min(l.games, need)} מתוך ${need} משחקים מדורגים. עוד קצת ויש לך רמה.</p>`}</div>`).join('')
      : `<div class="card"><b>הרמה שלך</b><p class="muted small">אחרי ${need} משחקים מדורגים תקבל רמה לכל ספורט. עד אז: לשחק ולדרג.</p></div>`}
    ${tags.length ? `<div class="card"><b>מה אומרים עליך</b><div class="chips" style="gap:6px">${tags.map(([t, n]) => `<span class="tag warm">${esc(t)} · ${n}</span>`).join('')}</div></div>` : ''}
    <details class="card"><summary style="font-weight:700;cursor:pointer;min-height:32px">איך הרמה שלי נקבעת?</summary>
      <ul style="margin:8px 0 0;padding-inline-start:18px;font-size:13px;line-height:1.7;color:var(--muted)">
        <li>רק מי ששיחק איתך באותו מעגל יכול לדרג, ורק אחרי שכולם אישרו שהמשחק קרה.</li>
        <li>דירוג של שחקן ותיק ועקבי שוקל יותר מדירוג של חדש.</li>
        <li>דירוג רחוק מכל השאר באותו משחק כמעט לא נספר.</li>
        <li>אותו שחקן שמדרג אותך שוב ושוב נספר פחות, כדי שחברים לא ינפחו.</li>
        <li>אתה לא רואה מי נתן מה, והרמה זזה לאט.</li></ul></details>
    <div class="card"><label for="pnick"><b>כינוי</b></label><input id="pnick" class="field" maxlength="20" value="${esc(p.nickname)}">
      <b>ספורט</b><div class="chips">${SPORTS.map((s) => `<button class="chip sm pill ${(p.sports || []).includes(s) ? 'on' : ''}" data-act="p-sport" data-v="${esc(s)}">${esc(s)}</button>`).join('')}</div>
      <button class="btn line" data-act="p-save">שמור</button></div>
    ${isAnon() ? `<div class="card"><b>שמור את הפרופיל שלך</b>
        <p class="muted small">כרגע הפרופיל שמור רק בטלפון הזה. מחבר חשבון, והרמה, החבר'ה וההיסטוריה נשארים איתך בכל מכשיר.</p>
        <button class="btn line" data-act="link-google">${I.google} שמור עם Google</button>
        ${S.showSave ? `<input id="semail" class="field" type="email" inputmode="email" dir="ltr" placeholder="מייל">
          <input id="spass" class="field" type="password" autocomplete="new-password" dir="ltr" placeholder="סיסמה, לפחות 6 תווים">
          <button class="btn sea" data-act="link-email">שמור עם מייל וסיסמה</button>` : `<button class="btn ghost" data-act="show-save">או עם מייל וסיסמה</button>`}
      </div>`
    : `<div class="card"><div class="row start">${I.lock}<div style="flex:1"><b>החשבון שלך</b><div class="muted small">${esc(authLabel())}</div></div>
        <button class="chip sm" data-act="logout">התנתק</button></div>
        <div class="row start muted small" style="gap:6px"><span class="tag">אימות זהות</span>בקרוב: וי כחול למי שאימת תעודה</div></div>`}
    <p class="muted small" style="text-align:center">טיפ: הוסף את maagal למסך הבית מתפריט השיתוף של הדפדפן, והיא תיפתח כמו אפליקציה.</p>`, { tabs: 'profile' });
}

// ---------- לחיצות ----------
document.addEventListener('click', async (e) => {
  const g = e.target.closest('[data-go]');
  const a = e.target.closest('[data-act]');
  if (a && (!g || g.contains(a))) {
    const act = a.dataset.act, v = a.dataset.v;
    if (a.type === 'checkbox') return; // handled on change
    e.preventDefault(); e.stopPropagation();
    switch (act) {
      case 'ob-sport': { const o = S.onboard.sports; S.onboard.sports = o.includes(v) ? o.filter((x) => x !== v) : [...o, v]; return renderOnboard(); }
      case 'ob-loc': await getLocation({ ask: true }); return renderOnboard();
      case 'ob-go': return finishOnboard(a);
      case 'ob-mode': S.onboard.mode = v; return renderOnboard();
      case 'google': return googleSignIn(false);
      case 'link-google': return googleSignIn(true);
      case 'show-save': S.showSave = true; return renderProfile();
      case 'link-email': { const email = $('semail').value.trim(), password = $('spass').value; a.disabled = true;
        const { error } = await sb.auth.updateUser({ email, password });
        a.disabled = false; if (error) return toast(authError(error));
        await sb.auth.refreshSession(); S.session = (await sb.auth.getSession()).data.session; S.showSave = false;
        toast(isAnon() ? 'כמעט: אשר את המייל ששלחנו' : 'הפרופיל נשמר. אפשר להיכנס מכל מכשיר.'); return renderProfile(); }
      case 'logout': if (!confirm('להתנתק?')) return; await sb.auth.signOut(); S.session = null; S.profile = null; S.onboard = { sports: [], mode: 'login' }; return go('#/');
      case 'loc': await getLocation({ ask: true }); if (!S.coords) toast('המיקום חסום. אפשר להפעיל בהגדרות הדפדפן.'); return route();
      case 'checkin': return doCheckin(v, a);
      case 'checkout': try { await rpc('check_out'); toast('יצאת מהמקום'); route(); } catch (err) { fail(err); } return;
      case 'new-circle': return startNewCircle(v);
      case 'new-spot': return openNewSpotSheet();
      case 'ns-kind': if (S.form?.newSpot && $('sheet').contains(a) && document.querySelector('[data-act="f-create"]')) { S.form.newSpot.kind = v; return renderSheet(); } S.ns.kind = v; return openNewSpotSheet();
      case 'ns-save': { a.disabled = true; const id = await placeSpotHere(S.ns, null); a.disabled = false; if (!id) return; S.ns = null; closeSheet(); toast('סימנו אותך במקום החדש'); return go(`#/spot/${id}`); }
      case 'f-newspot': S.form.newSpot = S.form.newSpot ? null : { name: '', kind: 'פארק' }; return renderSheet();
      case 'f-sport': S.form.sport = v; S.form.size = DEFAULT_SIZE[v] || 4; return renderSheet();
      case 'f-spot': S.form.spot = v; S.form.newSpot = null; return renderSheet();
      case 'f-size': S.form.size = Math.max(2, Math.min(12, S.form.size + Number(v))); return renderSheet();
      case 'f-open': S.form.open = v === '1'; return renderSheet();
      case 'f-when': S.form.label = v; return renderSheet();
      case 'f-create': return createCircle(a);
      case 'join': {
        a.disabled = true;
        try { const r = await rpc('join_circle', { p_circle: S.circle.id });
          if (!r.ok) { a.disabled = false; return toast(r.reason === 'full' ? 'המעגל התמלא. נסה מעגל אחר.' : 'המעגל כבר נסגר.'); }
          toast('אתה בפנים. המארגן רואה שהצטרפת.'); return route();
        } catch (err) { a.disabled = false; return fail(err); } }
      case 'invite': return invite(S.circle);
      case 'copy-link': return copyLink(v);
      case 'finish': if (!confirm('לסגור את המשחק ולעבור לדירוג?')) return; try { await rpc('finish_circle', { p_circle: S.circle.id }); go(`#/rate/${S.circle.id}`); } catch (err) { fail(err); } return;
      case 'leave': if (!confirm(S.circle.organizer === S.session.user.id ? 'לבטל את המעגל לכולם?' : 'לצאת מהמעגל?')) return;
        try { await rpc('leave_circle', { p_circle: S.circle.id }); go('#/'); } catch (err) { fail(err); } return;
      case 'say': return say(v);
      case 'r-happened': S.rate.happened = v === '1'; return drawRate();
      case 'r-noshow': { const n = S.rate.noShows; S.rate.noShows = n.includes(v) ? n.filter((x) => x !== v) : [...n, v]; return drawRate(); }
      case 'r-level': { const [id, l] = v.split(':'); S.rate.items[id].level = Number(l); return drawRate(); }
      case 'r-tag': { const i = v.indexOf(':'); const id = v.slice(0, i), t = v.slice(i + 1); const it = S.rate.items[id]; it.tags = it.tags.includes(t) ? it.tags.filter((x) => x !== t) : [...it.tags, t]; return drawRate(); }
      case 'r-send': return sendRating(a);
      case 'report': { const reason = prompt('מה קרה? (נשלח לבדיקה, השחקן לא יידע מי דיווח)'); if (!reason) return;
        try { await rpc('report_player', { p_circle: S.rate.c.id, p_player: v, p_reason: reason }); toast('הדיווח נשלח. תודה.'); } catch (err) { fail(err); } return; }
      case 'vis': try { await rpc('save_profile', { p_nickname: S.profile.nickname, p_sports: S.profile.sports, p_visibility: v }); S.profile.visibility = v; renderCrew(); } catch (err) { fail(err); } return;
      case 'p-sport': { const s = S.profile.sports || []; S.profile.sports = s.includes(v) ? s.filter((x) => x !== v) : [...s, v]; a.classList.toggle('on'); return; }
      case 'p-save': { const nick = $('pnick').value.trim(); if (nick.length < 2) return toast('כינוי של לפחות 2 אותיות');
        try { await rpc('save_profile', { p_nickname: nick, p_sports: S.profile.sports }); toast('נשמר'); renderProfile(); } catch (err) { fail(err); } return; }
    }
    return;
  }
  if (g) { e.preventDefault(); go(g.dataset.go); }
});
document.addEventListener('change', (e) => {
  const a = e.target.closest('[data-act="r-again"]');
  if (a) S.rate.items[a.dataset.v].again = a.checked;
});
document.addEventListener('submit', (e) => {
  if (e.target.dataset.form === 'chat') { e.preventDefault(); const i = $('chatin'); const t = i.value; i.value = ''; say(t); }
});

// ---------- התחלה ----------
(async function boot() {
  loading(); setTabs(null);
  const qs = new URLSearchParams(location.search);
  const oauthErr = qs.get('error_description');
  const { data } = await sb.auth.getSession();
  S.session = data.session;
  if (location.search) history.replaceState(null, '', location.pathname + (ss.get('after') || location.hash || ''));
  if (ss.get('nick')) S.onboard.nick = ss.get('nick');
  try { if (ss.get('sports')) S.onboard.sports = JSON.parse(ss.get('sports')); } catch {}
  ss.del('after'); ss.del('nick'); ss.del('sports');
  if (oauthErr) setTimeout(() => toast(oauthErr.includes('already') ? 'החשבון הזה כבר מחובר לפרופיל אחר' : 'ההתחברות לא הצליחה. נסה שוב.'), 500);
  sb.auth.onAuthStateChange((_e, session) => { S.session = session; });
  if (S.session) {
    try { S.profile = await rpc('my_profile'); } catch (e) { console.error(e); }
    if (!S.profile && !isAnon() && !S.onboard.nick) {
      const m = S.session.user.user_metadata || {}; S.onboard.nick = (m.full_name || m.name || '').split(' ')[0].slice(0, 20);
    }
  }
  if (store.get('loc') === '1') await getLocation({ ask: true });
  route();
})();
