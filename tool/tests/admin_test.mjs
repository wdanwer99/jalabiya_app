// Loads admin/index.html in jsdom with a recording stand-in for supabase-js,
// then signs in and drives every section the way an admin would: it checks
// what is drawn, that each action calls the right admin_* function with the
// right arguments, that both languages have every word, and that text typed
// by app users is never turned into HTML. (The database side of those
// functions is tested in db_test.mjs.)
import { JSDOM, VirtualConsole } from 'jsdom';
import fs from 'fs';

const read = (p) => fs.readFileSync(new URL(`../../admin/${p}`, import.meta.url), 'utf8');
const html = read('index.html');
const i18nJs = read('i18n.js');
const appJs = read('app.js');

const results = [];
const check = (ok, msg) => results.push((ok ? 'PASS  ' : 'FAIL  ') + msg);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 2000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    try { const v = fn(); if (v) return v; } catch (_) { /* not yet */ }
    await sleep(15);
  }
  return null;
}

// ---------- data the stand-in serves ----------
const NOW = Date.now();
const iso = (msAgo) => new Date(NOW - msAgo).toISOString();
const DAY = 864e5;
const A1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const T1 = '11111111-1111-4111-8111-111111111111';
const T2 = '22222222-2222-4222-8222-222222222222';
const C1 = '33333333-3333-4333-8333-333333333333';
const O1 = 'abcd1234-0000-4000-8000-000000000001';
const O2 = 'beef5678-0000-4000-8000-000000000002';
const EVIL = '<img src=x onerror="window.__pwned=1">';

function fixtures() {
  const owner1 = { full_name: 'Abdelrahim', phone: '0911111111', whatsapp: null, created_at: iso(90 * DAY) };
  const owner2 = { full_name: 'Babiker', phone: '0922222222', whatsapp: null, created_at: iso(2 * DAY) };
  const shops = [
    { tailor_id: T1, shop_name: 'Abdelrahim Tailoring', bio: 'Since 1998', city: 'omdurman', neighbourhood: 'Souq',
      address_details: 'Row 3', base_price: 25000, currency: 'SDG', lead_time_days: 7, accepts_orders: true,
      approved: true, review_status: 'approved', review_note: null, reviewed_at: iso(5 * DAY), created_at: iso(60 * DAY),
      updated_at: iso(5 * DAY), cloth_options: [{ id: 'navy', name: 'Navy', color: 0x1F2A44, price: 2000 }],
      thread_options: [], owner: owner1 },
    { tailor_id: T2, shop_name: EVIL, bio: null, city: 'Wad Hamid', neighbourhood: 'Shambat',
      address_details: 'By the bridge', base_price: 20000, currency: 'SDG', lead_time_days: 10, accepts_orders: true,
      approved: false, review_status: 'pending', review_note: null, reviewed_at: null, created_at: iso(2 * DAY),
      updated_at: iso(2 * DAY), cloth_options: [], thread_options: [], owner: owner2 },
  ];
  const delivery = { name: 'Osman Ali', phone: '0912345678', whatsapp: null, city: 'khartoum', neighbourhood: 'Riyadh',
    address_details: 'Street 15, near the mosque' };
  const design = { cut: 'regular', collar: 'band', emb: 'neck', cloth: 'navy', thread: 'gold', hem: 4, cuff: 34,
    cloth_option: { id: 'navy', name: 'Navy', color: 0x1F2A44, price: 2000 },
    thread_option: { id: 'gold', name: null, color: 13148746, price: 0 } };
  const shopEmbed = { shop_name: 'Abdelrahim Tailoring', tailor_id: T1, owner: owner1 };
  const customer = { full_name: 'Osman Ali', phone: '0912345678', whatsapp: null };
  const measurements = { height: 178, chest: 104, waist: 94, hip: 102, shoulder: 47, arm: 61, neck: 40 };
  return {
    tailor_shops: shops,
    // T1 was blocked once and unblocked: the row stays, with lifted_at set
    account_blocks: [{ user_id: T1, reason: 'Old complaint', lifted_at: iso(30 * DAY) }],
    shop_events: [
      { id: 1, tailor_id: T2, actor_id: T2, kind: 'opened', from_status: null, to_status: 'pending', note: null, changes: null, created_at: iso(2 * DAY) },
      { id: 2, tailor_id: T1, actor_id: T1, kind: 'opened', from_status: null, to_status: 'pending', note: null, changes: null, created_at: iso(60 * DAY) },
      { id: 3, tailor_id: T1, actor_id: A1, kind: 'review', from_status: 'pending', to_status: 'approved', note: 'Welcome', changes: null, created_at: iso(59 * DAY) },
      { id: 4, tailor_id: T1, actor_id: A1, kind: 'edited', from_status: null, to_status: null, note: 'Typo',
        changes: { base_price: { from: 24000, to: 25000 }, city: { from: 'khartoum', to: 'omdurman' } }, created_at: iso(5 * DAY) },
    ],
    orders: [
      { id: O1, status: 'submitted', wearer_label: 'Ahmed (son)', quantity: 2, price: null, estimate: 54000, currency: 'SDG',
        due_date: null, created_at: iso(4 * DAY), updated_at: iso(4 * DAY), customer_id: C1, tailor_id: T1, delivery,
        measurements, design, customer_notes: 'Wide sleeves please', tailor_note: null, shop: shopEmbed, customer },
      { id: O2, status: 'delivered', wearer_label: 'Me', quantity: 1, price: 30000, estimate: 27000, currency: 'SDG',
        due_date: '2026-10-01', created_at: iso(20 * DAY), updated_at: iso(9 * DAY), customer_id: C1, tailor_id: T1, delivery,
        measurements, design, customer_notes: null, tailor_note: 'Thanks', shop: shopEmbed, customer },
    ],
    order_events: [
      { id: 1, order_id: O1, actor_id: C1, from_status: null, to_status: 'submitted', kind: 'status', note: null, created_at: iso(4 * DAY) },
      { id: 2, order_id: O2, actor_id: C1, from_status: null, to_status: 'submitted', kind: 'status', note: null, created_at: iso(20 * DAY) },
      { id: 3, order_id: O2, actor_id: T1, from_status: 'ready', to_status: 'delivered', kind: 'status', note: null, created_at: iso(9 * DAY) },
    ],
    admin_actions: [
      { id: 1, admin_id: A1, admin_email: 'admin@x.sd', action: 'shop.edited', target_id: T1, target_label: 'Abdelrahim Tailoring',
        note: 'Typo', details: { base_price: { from: 24000, to: 25000 } }, created_at: iso(5 * DAY) },
      { id: 2, admin_id: A1, admin_email: 'admin@x.sd', action: 'shop.approved', target_id: T1, target_label: 'Abdelrahim Tailoring',
        note: 'Welcome', details: null, created_at: iso(59 * DAY) },
    ],
    profiles: [
      { id: C1, full_name: 'Osman Ali' }, { id: T1, full_name: 'Abdelrahim' }, { id: T2, full_name: 'Babiker' },
    ],
    users: [
      { id: C1, email: 'osman@x.sd', role: 'customer', is_admin: false, full_name: 'Osman Ali', phone: '0912345678', whatsapp: null,
        city: 'khartoum', neighbourhood: 'Riyadh', address_details: 'Street 15', created_at: iso(30 * DAY), last_sign_in_at: iso(DAY),
        blocked: false, block_reason: null, blocked_at: null, shop_name: null, review_status: null, orders_count: 2 },
      { id: T1, email: 'tailor@x.sd', role: 'tailor', is_admin: false, full_name: 'Abdelrahim', phone: '0911111111', whatsapp: null,
        city: 'omdurman', neighbourhood: 'Souq', address_details: 'Row 3', created_at: iso(90 * DAY), last_sign_in_at: iso(2 * DAY),
        blocked: false, block_reason: null, blocked_at: null, shop_name: 'Abdelrahim Tailoring', review_status: 'approved', orders_count: 2 },
      { id: T2, email: 'new@x.sd', role: 'tailor', is_admin: false, full_name: 'Babiker', phone: '0922222222', whatsapp: null,
        city: 'Wad Hamid', neighbourhood: 'Shambat', address_details: 'By the bridge', created_at: iso(2 * DAY), last_sign_in_at: null,
        blocked: true, block_reason: 'Fake shop', blocked_at: iso(DAY), shop_name: EVIL, review_status: 'pending', orders_count: 0 },
      { id: A1, email: 'admin@x.sd', role: 'customer', is_admin: true, full_name: 'Site admin', phone: '', whatsapp: null,
        city: null, neighbourhood: null, address_details: null, created_at: iso(100 * DAY), last_sign_in_at: iso(0),
        blocked: false, block_reason: null, blocked_at: null, shop_name: null, review_status: null, orders_count: 0 },
    ],
  };
}

function stats() {
  return {
    customers: 1, tailors: 2, blocked: 1, new_users_7d: 2, listed: 1, taking_orders: 1,
    shops: { approved: 1, pending: 1 }, orders: { submitted: 1, delivered: 1 }, orders_7d: 1,
    delivered_value: { SDG: 30000 }, open_value: {},
    per_day: Array.from({ length: 30 }, (_, i) => ({
      day: new Date(NOW - (29 - i) * DAY).toISOString().slice(0, 10), orders: i === 25 ? 7 : i % 3, users: i % 2,
    })),
  };
}

// ---------- a stand-in for supabase-js that records every call ----------
function fakeSupabase({ isAdmin = true, adminError = null, session = false } = {}) {
  const data = fixtures();
  const calls = [];
  const failing = {};
  let signedIn = session;
  const authListeners = [];
  class Query {
    constructor(table) { this.table = table; this.filters = []; this.opts = {}; this.one = false; }
    select(cols, opts) { this.opts = opts || {}; return this; }
    eq(c, v) { calls.push(['eq', this.table, c, v]); this.filters.push((r) => r[c] === v); return this; }
    in(c, vs) { calls.push(['in', this.table, c, vs]); this.filters.push((r) => vs.includes(r[c])); return this; }
    lt(c, v) { this.filters.push((r) => String(r[c]) < String(v)); return this; }
    is(c, v) { calls.push(['is', this.table, c, v]); this.filters.push((r) => (r[c] ?? null) === v); return this; }
    gte(c, v) { calls.push(['gte', this.table, c, v]); this.filters.push((r) => String(r[c]) >= String(v)); return this; }
    lte(c, v) { calls.push(['lte', this.table, c, v]); this.filters.push((r) => String(r[c]) <= String(v)); return this; }
    like(c, p) { calls.push(['like', this.table, c, p]); const pre = p.replace(/%$/, ''); this.filters.push((r) => String(r[c]).startsWith(pre)); return this; }
    or(s) { calls.push(['or', this.table, s]); return this; }
    order() { return this; }
    range(a, b) { calls.push(['range', this.table, a, b]); return this; }
    limit() { return this; }
    maybeSingle() { this.one = true; return this; }
    then(ok, bad) { return Promise.resolve(this.run()).then(ok, bad); }
    run() {
      const rows = (data[this.table] || []).filter((r) => this.filters.every((f) => f(r)));
      if (this.opts.head) return { data: null, count: rows.length, error: null };
      if (this.one) return { data: rows[0] ? structuredClone(rows[0]) : null, error: null };
      return { data: structuredClone(rows), count: rows.length, error: null };
    }
  }
  const rpcs = {
    is_admin: () => isAdmin,
    admin_stats: () => stats(),
    admin_users: (a) => {
      let rows = data.users.filter((u) => (!a.p_user || u.id === a.p_user)
        && (!a.p_role || (a.p_role === 'admin' ? u.is_admin : u.role === a.p_role))
        && (a.p_blocked == null || u.blocked === a.p_blocked));
      rows = rows.map((u) => ({ ...u, total_count: rows.length }));
      return structuredClone(rows);
    },
  };
  const client = {
    calls,
    data,
    setAdmin: (v) => { isAdmin = v; },
    failRpc: (name, message) => { failing[name] = message; },
    setSignedIn: (v) => { signedIn = v; },
    from: (table) => new Query(table),
    rpc: async (name, args) => {
      calls.push(['rpc', name, args]);
      if (name === 'is_admin' && adminError) return { data: null, error: adminError };
      if (failing[name]) return { data: null, error: { message: failing[name], code: 'P0001' } };
      const fn = rpcs[name];
      return { data: fn ? fn(args || {}) : null, error: null };
    },
    auth: {
      getSession: async () => ({ data: { session: signedIn ? { user: { id: A1, email: 'admin@x.sd' } } : null }, error: null }),
      signInWithPassword: async ({ email, password }) => {
        calls.push(['signIn', email]);
        if (password !== 'right') return { data: {}, error: { message: 'Invalid login credentials', status: 400 } };
        signedIn = true;
        return { data: { user: { id: A1, email }, session: { user: { id: A1, email } } }, error: null };
      },
      signOut: async (opts) => { signedIn = false; calls.push(['signOut', opts]); authListeners.forEach((f) => f('SIGNED_OUT', null)); return { error: null }; },
      onAuthStateChange: (f) => { authListeners.push(f); return { data: { subscription: { unsubscribe() {} } } }; },
    },
    channel: () => {
      const ch = { on: () => ch, subscribe: (cb) => { setTimeout(() => cb('SUBSCRIBED'), 0); return ch; } };
      return ch;
    },
    removeChannel: () => {},
  };
  return client;
}

// ---------- the page ----------
// [since] / [active]: the stored sign-in time and last activity (a session
// kept from earlier); null leaves them out. [clock]: a fixed Date.now() the
// test moves by hand with advance().
function boot(fake, { lang, config = true, since = Date.now(), active = since, clock = null } = {}) {
  const errors = [];
  const vc = new VirtualConsole();
  vc.on('error', (e) => errors.push('console.error: ' + e));
  vc.on('jsdomError', (e) => errors.push('jsdom: ' + e.message));
  const dom = new JSDOM(html, { url: 'http://localhost/admin/index.html', runScripts: 'outside-only', pretendToBeVisual: true, virtualConsole: vc });
  const w = dom.window;
  w.addEventListener('error', (e) => errors.push('error: ' + e.message));
  w.addEventListener('unhandledrejection', (e) => errors.push('unhandled: ' + (e.reason && e.reason.stack || e.reason)));
  if (lang) w.localStorage.setItem('jalabiya.admin.lang', lang);
  if (config) w.localStorage.setItem('jalabiya.admin.config', JSON.stringify({ url: 'https://demo.supabase.co', anonKey: 'x'.repeat(40) }));
  if (since != null) w.localStorage.setItem('jalabiya.admin.signedInAt', String(since));
  if (active != null) w.localStorage.setItem('jalabiya.admin.activity', String(active));
  let now = clock;
  if (clock != null) w.Date.now = () => now;
  w.supabase = { createClient: () => fake };
  w.eval(i18nJs);
  w.eval(appJs);
  const $ = (s) => w.document.querySelector(s);
  const $$ = (s) => [...w.document.querySelectorAll(s)];
  const text = () => w.document.body.textContent;
  const type = (el, v) => { el.value = v; el.dispatchEvent(new w.Event('input', { bubbles: true })); };
  const button = (label) => $$('button, a.btn').find((b) => b.textContent.trim() === label);
  const go = async (hash) => { w.location.hash = hash; await sleep(40); };
  const advance = (ms) => { now += ms; };
  const tick = async () => { w.JalabiyaAdmin.tick(); await sleep(30); };
  return { w, dom, errors, $, $$, text, type, button, go, advance, tick };
}

const rpcCalls = (fake, name) => fake.calls.filter((c) => c[0] === 'rpc' && c[1] === name).map((c) => c[2]);

// ---------- translations ----------
{
  const w = new JSDOM('', { runScripts: 'outside-only' }).window;
  w.eval(i18nJs);
  const S = w.ADMIN_STRINGS;
  const ar = Object.keys(S.ar).sort();
  const en = Object.keys(S.en).sort();
  const onlyAr = ar.filter((k) => !(k in S.en));
  const onlyEn = en.filter((k) => !(k in S.ar));
  check(!onlyAr.length && !onlyEn.length, `Arabic and English define the same keys${onlyAr.length || onlyEn.length ? ` (ar only: ${onlyAr}; en only: ${onlyEn})` : ''}`);
  // whole keys only: t('city.' + c) is a prefix, checked by using the page below
  const literal = [...appJs.matchAll(/\bt\('([a-zA-Z0-9_.]+)'\s*[,)]/g)].map((m) => m[1]);
  const absent = [...new Set(literal)].filter((k) => !(k in S.ar));
  check(!absent.length, `every fixed text key in app.js exists${absent.length ? ': missing ' + absent.join(', ') : ''}`);
  const holes = Object.keys(S.ar).filter((k) => {
    const names = (s) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join();
    return names(S.ar[k]) !== names(S.en[k]);
  });
  check(!holes.length, `placeholders match between the languages${holes.length ? ': ' + holes.join(', ') : ''}`);
}

// ---------- first visit: connect, then sign in ----------
{
  const fake = fakeSupabase();
  const p = boot(fake, { config: false, since: null });
  await until(() => p.$('form'));
  check(p.text().includes('اربط اللوحة بمشروع Supabase') && p.w.document.documentElement.dir === 'rtl',
    'a first visit asks for the Supabase project, in Arabic and right-to-left');
  const [url, key] = p.$$('form input');
  url.value = 'https://demo.supabase.co';
  key.value = 'short';
  p.$('form button[type=submit]').click();
  check(p.$('.form-error').textContent.length > 0, 'a wrong URL or key is caught before saving');
  url.value = 'https://demo.supabase.co/';
  key.value = 'k'.repeat(40);
  p.$('form button[type=submit]').click();
  await until(() => p.$('input[type=password]'));
  check(JSON.parse(p.w.localStorage.getItem('jalabiya.admin.config')).url === 'https://demo.supabase.co' && !!p.$('input[type=password]'),
    'the project is remembered and the sign-in form follows');

  const [email, pass] = p.$$('form input');
  email.value = 'admin@x.sd';
  pass.value = 'wrong';
  p.$('form button[type=submit]').click();
  await until(() => p.$('.form-error').textContent);
  check(p.$('.form-error').textContent.includes('غير صحيحة'), 'a wrong password says so');
  pass.value = 'right';
  p.$('form button[type=submit]').click();
  await until(() => p.$('.shell'));
  check(!!p.$('.shell') && rpcCalls(fake, 'is_admin').length === 1, 'signing in checks is_admin() and opens the dashboard');
  check(Number(p.w.localStorage.getItem('jalabiya.admin.signedInAt')) > NOW - 60e3,
    'signing in records when the session started, for the 12-hour limit');
  check(!p.errors.length, 'no script errors while connecting and signing in' + (p.errors.length ? ': ' + p.errors.join(' | ') : ''));
}

// ---------- not an admin, or admin.sql missing ----------
{
  const p = boot(fakeSupabase({ isAdmin: false, session: true }));
  await until(() => p.$('pre'));
  check(p.text().includes('ليس حساب إدارة') && p.$('pre').textContent.includes("email = 'admin@x.sd'") && !p.$('.shell'),
    'an account that is not an admin sees how to make it one, and no data');
  const q = boot(fakeSupabase({ session: true, adminError: { code: 'PGRST202', message: 'Could not find the function public.is_admin' } }));
  await until(() => q.text().includes('admin.sql'));
  check(q.text().includes('شغّل admin.sql أولاً'), 'a project without admin.sql says to run it');
}

// ---------- the dashboard, signed in ----------
const fake = fakeSupabase({ session: true });
const p = boot(fake, { lang: 'en' });
await until(() => p.$('.shell'));
await until(() => p.$$('.tile').length);

// overview
check(p.$$('.tile').length === 5 && p.text().includes('Orders per day') && p.text().includes('New accounts per day'),
  'the overview shows the stat tiles and both charts');
check(p.$$('.chart')[0].querySelectorAll('path.bar').length === 30 && p.$$('.chart')[0].querySelector('.peak-text').textContent === '7',
  'a chart draws a column per day and labels only its peak');
const svg = p.$$('.chart svg')[0];
svg.dispatchEvent(new p.w.FocusEvent('focus'));
svg.dispatchEvent(new p.w.KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }));
const tip = p.$$('.chart .tooltip')[0];
check(!tip.hidden && tip.querySelector('b').textContent === '1', 'the chart reads out a day by keyboard (value first)');
check(p.$$('.chart')[0].querySelectorAll('details tbody tr').length === 30, 'every chart value is also in a table');
check(p.$('[data-badge="shops"]').textContent === '1', 'the menu shows how many shops wait for review');
check(p.$('.attention a').getAttribute('href') === '#/shops?tab=pending', 'the attention row links to the review queue');

// shops
await p.go('#/shops');
await until(() => p.$('table.data'));
check(p.$$('table.data tbody tr').length === 1 && p.$$('.tabs [role=tab]').length === 5,
  'the shops page opens on the review queue, with a tab per review status');
check(!p.w.document.querySelector('table.data img') && p.$('table.data tbody tr').textContent.includes(EVIL) && !p.w.__pwned,
  "a shop name typed by a tailor is shown as text, never run as HTML");
p.$('table.data tbody tr').click();
await until(() => p.$('.drawer .actions'));
check(p.$('.drawer h2').textContent === EVIL && p.text().includes('New shop') && p.button('Approve') && p.button('Send back'),
  'opening a waiting shop shows it with Approve and Send back');
check(p.text().includes('Wad Hamid') && p.text().includes('Standard palette, no extra') && p.text().includes('Shop opened'),
  'the shop panel shows its details, colours and history');

p.button('Send back').click();
await until(() => p.$('.modal'));
p.$('.modal button[type=submit]').click();
check(p.$('.modal .form-error').textContent.length > 0 && rpcCalls(fake, 'admin_review_shop').length === 0,
  'sending a shop back without a reason is stopped before anything is sent');
p.$('.modal textarea').value = 'Add your street and shop number';
p.$('.modal button[type=submit]').click();
await until(() => rpcCalls(fake, 'admin_review_shop').length);
const rej = rpcCalls(fake, 'admin_review_shop')[0];
check(rej && rej.p_tailor === T2 && rej.p_to === 'rejected' && rej.p_note === 'Add your street and shop number' && !p.$('.modal'),
  'sending back calls admin_review_shop with the reason');
await until(() => p.$('.toast'));
check(!!p.$('.toast'), 'the result is confirmed in a toast');

p.button('Approve').click();
await until(() => p.$('.modal'));
p.$('.modal button[type=submit]').click();
await until(() => rpcCalls(fake, 'admin_review_shop').length === 2);
const appr = rpcCalls(fake, 'admin_review_shop')[1];
check(appr.p_to === 'approved' && appr.p_note === null, 'approving needs no note and sends none');

// the approved shop: suspend and edit
await p.go('#/shops/' + T1 + '?tab=approved');
await until(() => p.$('.drawer h2') && p.$('.drawer h2').textContent === 'Abdelrahim Tailoring' && p.button('Suspend'));
check(!!p.button('Suspend') && !p.button('Approve') && p.text().includes('Navy') && p.text().includes('+2,000'),
  'an approved shop offers Suspend, and shows its own colours with their extra price');
check(!p.$$('table.data tbody tr').some((tr) => tr.textContent.includes('Abdelrahim') && tr.textContent.includes('Blocked'))
      && fake.calls.some((c) => c[0] === 'is' && c[1] === 'account_blocks' && c[2] === 'lifted_at' && c[3] === null),
  'a block that was lifted does not mark the owner as blocked');
check(p.text().includes('Details edited by an admin') && p.text().includes('Khartoum') && p.text().includes('Omdurman'),
  "an admin edit appears in the shop's history with what changed");
p.button('Edit details').click();
await until(() => p.$('.modal form'));
p.$('.modal button[type=submit]').click();
check(p.$('.modal .form-error').textContent === 'Nothing changed.', 'saving an unchanged shop says nothing changed');
const price = p.$('.modal input[type=number]');
price.value = '26000';
p.$('.modal button[type=submit]').click();
await until(() => rpcCalls(fake, 'admin_update_shop').length);
const upd = rpcCalls(fake, 'admin_update_shop')[0];
check(upd && upd.p_tailor === T1 && JSON.stringify(upd.p_shop) === '{"base_price":26000}',
  'editing sends only the fields that changed');
p.button('Suspend').click();
await until(() => p.$('.modal'));
p.$('.modal').dispatchEvent(new p.w.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
await sleep(20);
check(!p.$('.modal') && !!p.$('.drawer') && rpcCalls(fake, 'admin_review_shop').length === 2,
  'Escape closes a dialog without acting, and keeps the panel open');
p.w.document.dispatchEvent(new p.w.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
await sleep(40);
check(!p.$('.drawer') && p.w.location.hash === '#/shops?tab=approved', 'Escape again closes the panel and keeps the list');

// orders
await p.go('#/orders');
await until(() => p.$('table.data'));
check(p.$$('table.data tbody tr').length === 2 && p.text().includes('#ABCD1234') && p.text().includes('≈ 54,000 SDG'),
  'the orders page lists orders with their reference and amount');
const search = p.$('.search input');
p.type(search, '#abcd1234');
await until(() => fake.calls.some((c) => c[0] === 'gte' && c[2] === 'id'));
check(fake.calls.some((c) => c[0] === 'gte' && c[3] === 'abcd1234-0000-0000-0000-000000000000')
      && fake.calls.some((c) => c[0] === 'lte' && c[3] === 'abcd1234-ffff-ffff-ffff-ffffffffffff')
      && p.$('.search input') === search,
  'a reference search looks up the order by its id, without redrawing the search box');
p.type(search, 'Osman, (evil)');
await until(() => fake.calls.some((c) => c[0] === 'or' && c[1] === 'orders'));
const orFilter = fake.calls.filter((c) => c[0] === 'or' && c[1] === 'orders').pop()[2];
check(orFilter === 'wearer_label.ilike.*Osman evil*,delivery->>name.ilike.*Osman evil*',
  'a name search matches wearer or customer, with filter characters removed');
p.type(search, '');
await sleep(450);
await p.go('#/orders/' + O1);
await until(() => p.button('Cancel order'));
check(p.text().includes('Wide sleeves please') && p.text().includes('Mandarin band') && p.$$('.measures div').length === 7,
  'the order panel shows notes, design and all seven measurements');
p.button('Cancel order').click();
await until(() => p.$('.modal'));
p.$('.modal textarea').value = 'Tailor closed this month';
p.$('.modal button[type=submit]').click();
await until(() => rpcCalls(fake, 'admin_cancel_order').length);
check(rpcCalls(fake, 'admin_cancel_order')[0].p_order === O1, 'cancelling calls admin_cancel_order for that order');
await p.go('#/orders/' + O2);
await until(() => p.$('.drawer h2') && p.$('.drawer h2').textContent.includes('BEEF5678'));
check(!p.button('Cancel order'), 'a delivered order cannot be cancelled');
await p.go('#/orders?shop=' + T1 + '&status=open');
await until(() => p.$('.filter-chip'));
check(p.$('.filter-chip').textContent.includes('Abdelrahim Tailoring') && fake.calls.some((c) => c[0] === 'in' && c[1] === 'orders' && c[3].length === 7),
  "an order list filtered by shop names the shop and asks only for open orders");

// people
await p.go('#/users');
await until(() => p.$('table.data'));
check(p.$$('table.data tbody tr').length === 4 && p.text().includes('osman@x.sd'), 'the accounts page lists everyone with their email');
p.$$('.tabs [role=tab]')[2].click();
await until(() => rpcCalls(fake, 'admin_users').some((a) => a.p_role === 'tailor'));
await until(() => p.$$('table.data tbody tr').length === 2);
check(p.$$('table.data tbody tr').length === 2, 'the Tailors tab asks the server for tailors only');
await p.go('#/users/' + C1);
await until(() => p.button('Block account'));
p.button('Block account').click();
await until(() => p.$('.modal'));
p.$('.modal textarea').value = 'Fake orders';
p.$('.modal button[type=submit]').click();
await until(() => rpcCalls(fake, 'admin_block_user').length);
check(JSON.stringify(rpcCalls(fake, 'admin_block_user')[0]) === JSON.stringify({ p_user: C1, p_reason: 'Fake orders' }),
  'blocking calls admin_block_user with the reason');
await p.go('#/users/' + T2);
await until(() => p.button('Unblock'));
check(p.text().includes('Fake shop') && !p.button('Block account'), 'a blocked account shows why, and offers Unblock');
await p.go('#/users/' + A1);
await until(() => p.$('.drawer .banner.nile'));
check(!p.button('Block account') && !p.button('Unblock'), 'an admin account cannot be blocked from here');

// admin log
await p.go('#/activity');
await until(() => p.$('.rows'));
check(p.text().includes("Edited a shop's details") && p.text().includes('admin@x.sd') && p.$('.changes'),
  'the admin log lists each action, who did it, and what an edit changed');

// language
const before = p.$('.nav a').textContent;
p.$$('.side-foot button')[0].click();
await until(() => p.w.document.documentElement.dir === 'rtl');
check(p.w.document.documentElement.dir === 'rtl' && p.$('.nav a').textContent !== before && p.$('.nav a').textContent.includes('نظرة عامة'),
  'switching language redraws the dashboard in Arabic, right-to-left');
await sleep(80);
check(p.w.localStorage.getItem('jalabiya.admin.lang') === 'ar', 'the language choice is remembered');

// sign out
p.$$('.side-foot button')[1].click();
await until(() => p.$('input[type=password]'));
const out = fake.calls.filter((c) => c[0] === 'signOut').pop();
check(!!p.$('input[type=password]') && !p.$('.shell') && out && out[1] && out[1].scope === 'local'
      && !p.$('.session-note') && p.w.localStorage.getItem('jalabiya.admin.signedInAt') === null,
  'signing out ends only this browser’s session (the phone app stays signed in) and returns to the sign-in form');

// ---------- the admin's session ----------
const MIN = 60e3;
const HOUR = 60 * MIN;
const note = (q) => (q.$('.session-note') ? q.$('.session-note').textContent : '');
const lastSignOut = (f) => f.calls.filter((c) => c[0] === 'signOut').pop();
const sessionPages = [];

{
  // sessions kept in the browser from earlier still follow the rules
  const old = boot(fakeSupabase({ session: true }), { lang: 'en', since: NOW - 13 * HOUR, active: NOW });
  const idle = boot(fakeSupabase({ session: true }), { lang: 'en', since: NOW - HOUR, active: NOW - 31 * MIN });
  const legacy = boot(fakeSupabase({ session: true }), { lang: 'en', since: null, active: null });
  await until(() => old.$('.session-note') && idle.$('.session-note') && legacy.$('.session-note'));
  check(note(old).includes('every 12 hours') && note(idle).includes('30 minutes') && note(legacy).includes('every 12 hours')
        && ![old, idle, legacy].some((q) => q.$('.shell')),
    'reopening the page after 12 hours, after 30 idle minutes, or with no recorded sign-in asks to sign in again');
  sessionPages.push(old, idle, legacy);
}

{
  const f = fakeSupabase({ session: true });
  const q = boot(f, { lang: 'en', since: NOW, clock: NOW });
  await until(() => q.$$('.tile').length);
  q.advance(29 * MIN + 30e3);
  await q.tick();
  const warn = q.$('.session-warning');
  check(!!warn && warn.textContent.includes('Still there?') && warn.textContent.includes('30 seconds') && !!q.$('.shell'),
    'after 29½ idle minutes a warning counts down the last seconds');
  q.w.document.dispatchEvent(new q.w.Event('pointerdown'));
  await q.tick();
  check(!q.$('.session-warning') && !!q.$('.shell'), 'any activity keeps the session and closes the warning');

  await q.go('#/users/' + C1);
  await until(() => q.button('Block account'));
  q.button('Block account').click();
  await until(() => q.$('.modal'));
  q.advance(30 * MIN + 1e3);
  await q.tick();
  check(!!q.$('input[type=password]') && note(q).includes('30 minutes without activity') && !q.$('.modal')
        && !q.$('.drawer') && rpcCalls(f, 'admin_block_user').length === 0 && lastSignOut(f)[1].scope === 'local'
        && q.w.localStorage.getItem('jalabiya.admin.signedInAt') === null,
    '30 idle minutes sign out this browser, closing any open dialog without acting');
  sessionPages.push(q);
}

{
  const f = fakeSupabase({ session: true });
  const q = boot(f, { lang: 'en', since: NOW, clock: NOW });
  await until(() => q.$$('.tile').length);
  q.advance(11 * HOUR + 56 * MIN);
  q.w.document.dispatchEvent(new q.w.Event('keydown'));
  await q.tick();
  check(!!q.$('.shell') && [...q.$$('.toast')].some((el) => el.textContent.includes('in 5 minutes')),
    'five minutes before the 12-hour limit, a busy admin is told they will be asked to sign in again');
  q.advance(4 * MIN);
  q.w.document.dispatchEvent(new q.w.Event('keydown'));
  await q.tick();
  check(!!q.$('input[type=password]') && note(q).includes('every 12 hours'),
    'after 12 hours the admin signs in again, even while active');
  sessionPages.push(q);
}

{
  const f = fakeSupabase({ session: true });
  const q = boot(f, { lang: 'en', since: NOW, clock: NOW });
  await until(() => q.$$('.tile').length);
  f.setAdmin(false);
  q.advance(11e3);
  q.w.document.dispatchEvent(new q.w.Event('visibilitychange'));
  await until(() => q.$('input[type=password]'));
  check(note(q).includes('no longer an admin') && !q.$('.shell'),
    'an admin removed from app_admins is signed out when the tab is looked at again');

  const f2 = fakeSupabase({ session: true });
  const q2 = boot(f2, { lang: 'en', since: NOW, clock: NOW });
  await until(() => q2.$$('.tile').length);
  f2.failRpc('admin_stats', 'NOT_AN_ADMIN');
  q2.button('Refresh').click();
  await until(() => q2.$('input[type=password]'));
  check(note(q2).includes('no longer an admin') && !q2.$('.toast.error'),
    'the server answering NOT_AN_ADMIN signs out at once, instead of showing errors');

  const f3 = fakeSupabase({ session: true });
  const q3 = boot(f3, { lang: 'en', since: NOW, clock: NOW });
  await until(() => q3.$$('.tile').length);
  f3.setAdmin(false);
  q3.advance(61e3);
  await q3.tick();
  await until(() => q3.$('input[type=password]'));
  check(note(q3).includes('no longer an admin'), 'and is checked again every minute while the page is open');
  sessionPages.push(q, q2, q3);
}

{
  const f = fakeSupabase({ session: true });
  const q = boot(f, { lang: 'en', since: NOW, clock: NOW });
  await until(() => q.$$('.tile').length);
  q.w.localStorage.removeItem('jalabiya.admin.signedInAt');
  q.w.dispatchEvent(new q.w.StorageEvent('storage', { key: 'jalabiya.admin.signedInAt', oldValue: String(NOW), newValue: null }));
  await until(() => q.$('input[type=password]'));
  check(note(q).includes('another tab') && !q.$('.shell'), 'signing out in another tab signs out this one too');

  f.setSignedIn(true);
  q.w.localStorage.setItem('jalabiya.admin.signedInAt', String(NOW));
  q.w.localStorage.setItem('jalabiya.admin.activity', String(NOW));
  q.w.dispatchEvent(new q.w.StorageEvent('storage', { key: 'jalabiya.admin.signedInAt', oldValue: null, newValue: String(NOW) }));
  await until(() => q.$('.shell'));
  check(!!q.$('.shell'), 'signing in in another tab opens the dashboard here too');

  q.advance(20 * MIN);
  q.w.dispatchEvent(new q.w.StorageEvent('storage', { key: 'jalabiya.admin.activity', newValue: String(NOW + 20 * MIN) }));
  q.advance(20 * MIN);
  await q.tick();
  check(!!q.$('.shell') && !q.$('.session-warning'), 'working in another tab keeps this one signed in');
  sessionPages.push(q);
}
const sessionErrors = sessionPages.flatMap((q) => q.errors);
check(!sessionErrors.length, 'no script errors in the session checks' + (sessionErrors.length ? ': ' + sessionErrors.slice(0, 3).join(' | ') : ''));

const missing = [...p.w.JalabiyaAdmin.missing];
check(!missing.length, 'no text key was missing while using every section' + (missing.length ? ': ' + missing.join(', ') : ''));
check(!p.errors.length, 'no script errors while using every section' + (p.errors.length ? ': ' + p.errors.slice(0, 5).join(' | ') : ''));

console.log(results.join('\n'));
const fails = results.filter((r) => r.startsWith('FAIL')).length;
console.log(`\n${results.length - fails}/${results.length} passed`);
process.exit(fails ? 1 : 0);
