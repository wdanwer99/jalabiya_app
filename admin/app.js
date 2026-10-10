/* Jalabiya admin dashboard. Plain JavaScript, no build step.
 *
 * Reads with the signed-in admin's session: the RLS policies in
 * supabase/admin.sql let admins read every shop, order and profile. It changes
 * things only through the admin_* functions there, which check the caller is
 * listed in app_admins and log every step in admin_actions.
 *
 * Every piece of data reaches the page as text (textContent / text nodes),
 * never as HTML: shop names, notes and addresses are typed by app users. */
(function () {
  'use strict';

  const STRINGS = window.ADMIN_STRINGS || { ar: {}, en: {} };
  const NS = 'http://www.w3.org/2000/svg';

  // ---------- the app's rules, mirrored for display ----------
  const STATUSES = ['submitted', 'changes_requested', 'price_offered', 'confirmed', 'cutting', 'sewing', 'ready',
    'delivered', 'declined', 'cancelled'];
  const WAITING = ['submitted', 'changes_requested', 'price_offered'];
  const ACTIVE = ['confirmed', 'cutting', 'sewing', 'ready'];
  const OPEN = WAITING.concat(ACTIVE);
  const REVIEWS = ['pending', 'approved', 'rejected', 'suspended'];
  const CITIES = ['khartoum', 'omdurman', 'bahri', 'port_sudan', 'wad_madani', 'kassala', 'gedaref', 'atbara', 'shendi',
    'el_obeid', 'kosti', 'rabak', 'sennar', 'dongola', 'merowe', 'ed_damazin', 'nyala', 'el_fasher'];
  const MEASURES = ['height', 'chest', 'waist', 'hip', 'shoulder', 'arm', 'neck'];
  // the standard palette, as default_options() in supabase/shop_options.sql
  const STD_COLOURS = {
    cloth: { damuriya: 16118246, cream: 15589314, nile: 12176857, sand: 14468770, ash: 12830667, charcoal: 4870232 },
    thread: { gold: 13148746, white: 16184298, indigo: 2834275, henna: 10242607 },
  };
  const SERVER_CODES = ['NOT_AN_ADMIN', 'NOT_SIGNED_IN', 'NOTE_REQUIRED', 'REVIEW_NOT_ALLOWED', 'SHOP_NOT_FOUND',
    'INVALID_SHOP', 'USER_NOT_FOUND', 'CANNOT_BLOCK_ADMIN', 'NOT_BLOCKED', 'ORDER_NOT_FOUND', 'TRANSITION_NOT_ALLOWED'];
  const PAGE = 50;
  const STALE_DAYS = 3;
  const SHOP_SELECT = '*, owner:profiles!tailor_shops_tailor_id_fkey(full_name, phone, whatsapp, created_at)';
  const ORDER_LIST_SELECT = 'id, status, wearer_label, quantity, price, estimate, currency, due_date, created_at, '
    + 'updated_at, customer_id, tailor_id, delivery, shop:tailor_shops!orders_tailor_id_fkey(shop_name)';
  const ORDER_SELECT = '*, shop:tailor_shops!orders_tailor_id_fkey(shop_name, tailor_id, '
    + 'owner:profiles!tailor_shops_tailor_id_fkey(full_name, phone, whatsapp)), '
    + 'customer:profiles!orders_customer_id_fkey(full_name, phone, whatsapp)';
  const VIEWS = ['overview', 'shops', 'orders', 'users', 'activity'];
  const NAV_ICONS = { overview: 'overview', shops: 'shop', orders: 'orders', users: 'users', activity: 'activity' };
  const SHOP_TABS = ['pending', 'approved', 'rejected', 'suspended', 'all'];
  const USER_TABS = ['all', 'customer', 'tailor', 'admin'];

  // ---------- small helpers ----------
  const store = {
    get(k) { try { return window.localStorage.getItem('jalabiya.admin.' + k); } catch (_) { return null; } },
    set(k, v) {
      try {
        if (v == null) window.localStorage.removeItem('jalabiya.admin.' + k);
        else window.localStorage.setItem('jalabiya.admin.' + k, v);
      } catch (_) { /* private window: preferences just aren't remembered */ }
    },
  };

  let lang = store.get('lang') === 'en' ? 'en' : 'ar';
  const missing = new Set();

  function t(key, args) {
    let s = (STRINGS[lang] || {})[key];
    if (s == null) {
      missing.add(key);
      s = (STRINGS.en || {})[key];
      if (s == null) s = key;
    }
    if (args) for (const k of Object.keys(args)) s = s.split('{' + k + '}').join(String(args[k]));
    return s;
  }

  function applyLang() {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.title = t('app.title');
  }

  function h(tag, attrs, ...kids) {
    const el = document.createElement(tag);
    if (attrs) {
      for (const [k, v] of Object.entries(attrs)) {
        if (v == null || v === false) continue;
        if (k === 'class') el.className = v;
        else if (k === 'text') el.textContent = v;
        else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
        else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
        else if (k === 'value') el.value = v;
        else el.setAttribute(k, v === true ? '' : String(v));
      }
    }
    return add(el, kids);
  }

  function add(el, kids) {
    for (const kid of [kids].flat(Infinity)) {
      if (kid == null || kid === false || kid === '') continue;
      el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    }
    return el;
  }

  const ICONS = {
    overview: 'M4 4h7v7H4zM13 4h7v4h-7zM13 10h7v10h-7zM4 13h7v7H4z',
    shop: 'M4 9.5 5.5 4h13L20 9.5M4 9.5V20h16V9.5M4 9.5c0 1.4 1.1 2.5 2.7 2.5s2.6-1.1 2.6-2.5c0 1.4 1.2 2.5 2.7 2.5s2.7-1.1 2.7-2.5c0 1.4 1.1 2.5 2.6 2.5S20 10.9 20 9.5M10 20v-5h4v5',
    orders: 'M6 3h12v18l-2-1.5-2 1.5-2-1.5-2 1.5-2-1.5L6 21zM9 8h6M9 12h6M9 16h3',
    users: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM2.5 20c.6-3.3 3.3-5.5 6.5-5.5s5.9 2.2 6.5 5.5M16 4.5a3.2 3.2 0 0 1 0 6.2M18.5 14.8c1.6.8 2.7 2.4 3 5.2',
    activity: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3 2',
    close: 'M6 6l12 12M18 6 6 18',
    check: 'M5 12.5 10 17 19 7',
    block: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM5.6 5.6l12.8 12.8',
    refresh: 'M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5',
    logout: 'M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3M10 16l-4-4 4-4M6 12h10',
    search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4',
    edit: 'M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4',
    phone: 'M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2',
    chat: 'M4 20l1.3-3.9A8 8 0 1 1 8 19z',
    mail: 'M3 6h18v12H3zM3 7l9 6 9-6',
    warn: 'M12 3 2 20h20zM12 10v4M12 17h.01',
    globe: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM3 12h18M12 3c2.5 2.5 3.8 5.5 3.8 9s-1.3 6.5-3.8 9c-2.5-2.5-3.8-5.5-3.8-9S9.5 5.5 12 3',
    inbox: 'M4 13l2-8h12l2 8M4 13v6h16v-6M4 13h5l1 2h4l1-2h5',
    undo: 'M9 14 4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3',
  };

  function icon(name, cls) {
    const svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('class', 'icon' + (cls ? ' ' + cls : ''));
    svg.setAttribute('aria-hidden', 'true');
    const p = document.createElementNS(NS, 'path');
    p.setAttribute('d', ICONS[name] || ICONS.warn);
    svg.append(p);
    return svg;
  }

  function svgEl(tag, attrs) {
    const el = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs || {})) el.setAttribute(k, String(v));
    return el;
  }

  // ---------- formatting ----------
  const locale = () => (lang === 'ar' ? 'ar-u-nu-latn' : 'en-GB');
  const toDate = (v) => {
    if (!v) return null;
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
    const d = m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date(v);
    return isNaN(d) ? null : d;
  };
  const num = (n) => (n == null || n === '' || isNaN(Number(n))
    ? '—' : new Intl.NumberFormat(locale(), { maximumFractionDigits: 2 }).format(Number(n)));
  const money = (n, cur) => (n == null ? '—' : num(n) + ' ' + (!cur || cur === 'SDG' ? t('money.sdg') : cur));
  const date = (v) => {
    const d = toDate(v);
    return d ? new Intl.DateTimeFormat(locale(), { day: 'numeric', month: 'short', year: 'numeric' }).format(d) : '—';
  };
  const dayLabel = (v) => {
    const d = toDate(v);
    return d ? new Intl.DateTimeFormat(locale(), { day: 'numeric', month: 'short' }).format(d) : '—';
  };
  const dateTime = (v) => {
    const d = toDate(v);
    return d ? new Intl.DateTimeFormat(locale(), {
      day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
    }).format(d) : '—';
  };
  function ago(v) {
    const d = toDate(v);
    if (!d) return '—';
    const s = (Date.now() - d.getTime()) / 1000;
    if (Math.abs(s) < 60) return t('time.now');
    let unit = 'minute';
    let size = 60;
    for (const [u, sz] of [['hour', 3600], ['day', 86400], ['month', 2592000], ['year', 31536000]]) {
      if (Math.abs(s) >= sz) { unit = u; size = sz; }
    }
    return new Intl.RelativeTimeFormat(locale(), { numeric: 'auto' }).format(-Math.round(s / size), unit);
  }
  // isolated left-to-right, so "#AB12CD34" keeps its # in front inside Arabic text
  const ref = (id) => '⁦#' + String(id || '').slice(0, 8).toUpperCase() + '⁩';
  const cityName = (c) => (!c ? '—' : CITIES.includes(c) ? t('city.' + c) : c);
  const place = (city, hood) => [cityName(city), hood].filter((x) => x && x !== '—').join(' · ') || '—';
  const hex = (n) => '#' + (Number(n) || 0).toString(16).padStart(6, '0');
  const yesNo = (b) => t(b ? 'common.yes' : 'common.no');
  const clean = (s) => String(s || '').replace(/[,()*%\\:"'`]/g, ' ').replace(/\s+/g, ' ').trim();

  // Mirrors internationalNumber() in lib/util/contact.dart.
  function intlNumber(raw) {
    const d = String(raw || '').replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x0660))
      .replace(/[۰-۹]/g, (c) => String(c.charCodeAt(0) - 0x06F0)).replace(/\D/g, '');
    if (d.startsWith('00')) return d.slice(2);
    if (d.length === 10 && d.startsWith('0')) return '249' + d.slice(1);
    if (d.length === 9 && (d.startsWith('9') || d.startsWith('1'))) return '249' + d;
    return d;
  }

  function statusTone(s) {
    if (s === 'submitted') return 'tone-gold';
    if (s === 'changes_requested' || s === 'price_offered') return 'tone-henna';
    if (s === 'declined' || s === 'cancelled') return 'tone-grey';
    if (s === 'delivered') return 'tone-ink';
    return 'tone-nile';
  }
  const reviewTone = (r) => ({ pending: 'tone-gold', approved: 'tone-nile', rejected: 'tone-henna', suspended: 'tone-dark' })[r] || 'tone-grey';
  const chip = (text, tone) => h('span', { class: 'chip ' + tone }, h('i'), text);
  const statusChip = (s) => chip(t('status.' + s), statusTone(s));
  const reviewChip = (r) => chip(t('review.' + r), reviewTone(r));

  // ---------- state ----------
  const root = document.getElementById('app');
  const toasts = document.getElementById('toasts');
  const app = {
    sb: null,
    config: null,
    user: null,
    route: null,
    view: null,          // the list view on screen: { name, node, fill, fail }
    drawer: null,        // the open detail panel: { key, fill }
    pending: null,       // shops waiting for review, for the badge
    live: 'connecting',
    channel: null,
    changed: new Set(),
    liveTimer: null,
    modalOpen: false,
    modals: new Set(),   // close() of each open dialog, so signing out can close them
    gate: null,          // re-renders the current sign-in screen (after a language switch)
    routing: false,
  };

  async function q(builder) {
    const { data, error } = await builder;
    if (error) throw error;
    return data;
  }
  async function countOf(builder) {
    const { count, error } = await builder;
    if (error) throw error;
    return count || 0;
  }
  async function rpc(name, args) {
    const { data, error } = await app.sb.rpc(name, args || {});
    if (error) throw error;
    return data;
  }

  // ---------- errors ----------
  function isMissingSql(e) {
    const c = e && e.code;
    const m = String((e && e.message) || '');
    return c === 'PGRST202' || c === 'PGRST205' || c === '42883' || c === '42P01'
      || /could not find the (function|table)/i.test(m);
  }
  function isSessionError(e) {
    const m = String((e && e.message) || '');
    return (e && (e.code === 'PGRST301' || e.code === 'PGRST303')) || /jwt|refresh token|not_signed_in/i.test(m);
  }
  function explain(e) {
    const msg = String((e && (e.message || e.error_description)) || e || '');
    for (const c of SERVER_CODES) if (msg.includes(c)) return t('err.' + c);
    if (isMissingSql(e)) return t('err.noSql');
    if (e && e.code === '23514') return t('err.tooLong');
    if (e && e.code === '42501') return t('err.forbidden');
    if (isSessionError(e)) return t('err.session');
    if (/failed to fetch|networkerror|load failed|network request failed/i.test(msg)) return t('err.network');
    return t('err.generic', { detail: msg || '—' });
  }

  function toast(message, error, link) {
    const el = h('div', { class: 'toast' + (error ? ' error' : '') }, icon(error ? 'warn' : 'check'),
      h('div', null, message, link ? [' ', h('a', { href: link.href }, link.label)] : null));
    toasts.append(el);
    setTimeout(() => el.remove(), error ? 9000 : 5000);
  }

  function errorBox(e, retry) {
    const session = isSessionError(e);
    return h('div', { class: 'error-box' },
      icon('warn', 'big'),
      h('b', { text: t(session ? 'err.sessionTitle' : 'err.title') }),
      h('p', { text: explain(e) }),
      session
        ? h('button', { class: 'btn btn-primary', type: 'button', onclick: signOut }, t('action.signInAgain'))
        : retry ? h('button', { class: 'btn', type: 'button', onclick: retry }, icon('refresh'), t('action.retry')) : null);
  }

  function emptyState(text, iconName) {
    return h('div', { class: 'empty' }, icon(iconName || 'inbox'), h('div', { text }));
  }

  function skeleton(rows) {
    return h('div', { class: 'loading-block', 'aria-busy': 'true' },
      Array.from({ length: rows || 6 }, (_, i) => h('div', { class: 'skeleton sk-line', style: { width: (92 - (i % 3) * 14) + '%' } })));
  }

  // A button that shows a spinner while [fn] runs and reports what happened.
  async function runAction(btn, fn, success) {
    if (btn) { btn.disabled = true; btn.classList.add('busy'); }
    try {
      await fn();
      if (success) toast(success);
      await Promise.all([refreshBadge(false), refreshAll(true)]);
      return true;
    } catch (e) {
      if (!lostAdmin(e)) toast(explain(e), true);
      return false;
    } finally {
      if (btn && btn.isConnected) { btn.disabled = false; btn.classList.remove('busy'); }
    }
  }

  // The server says this account is no longer an admin: leave at once
  // rather than show errors and half-empty lists (RLS hides the rest).
  function lostAdmin(e) {
    if (!String((e && e.message) || '').includes('NOT_AN_ADMIN') || !app.user) return false;
    signOut('notAdmin');
    return true;
  }

  // ---------- dialogs ----------
  // A modal card; [build] gets close(value) and returns the content.
  function openModal(build) {
    return new Promise((resolve) => {
      const before = document.activeElement;
      let done = false;
      const close = (value) => {
        if (done) return;
        done = true;
        app.modals.delete(close);
        scrim.remove();
        document.removeEventListener('keydown', onKey, true);
        app.modalOpen = false;
        if (before && before.focus && before.isConnected) before.focus();
        resolve(value);
        if (app.stale) { app.stale = false; refreshAll(true); }
      };
      const onKey = (ev) => {
        if (ev.key === 'Escape') { ev.stopPropagation(); close(null); }
      };
      const card = h('div', { class: 'modal', role: 'dialog', 'aria-modal': 'true' }, build(close));
      const scrim = h('div', { class: 'modal-scrim', onmousedown: (ev) => { if (ev.target === scrim) close(null); } }, card);
      document.addEventListener('keydown', onKey, true);
      app.modalOpen = true;
      app.modals.add(close);
      document.body.append(scrim);
      const first = card.querySelector('textarea, input, select, button.btn-primary, button.btn-danger');
      if (first) first.focus();
    });
  }

  // Asks for a reason or note. Resolves with the trimmed text ('' when it is
  // optional and left empty), or null when cancelled.
  function askText({ title, body, label, hint, confirm, danger, required, max }) {
    return openModal((close) => {
      const area = h('textarea', { class: 'textarea', maxlength: max || 1000, 'aria-label': label });
      const err = h('div', { class: 'form-error', role: 'alert' });
      const submit = (ev) => {
        ev.preventDefault();
        const v = area.value.trim();
        if (required && !v) {
          err.textContent = t('form.reasonRequired');
          area.setAttribute('aria-invalid', 'true');
          area.focus();
          return;
        }
        close(v);
      };
      return h('form', { onsubmit: submit },
        h('h2', { text: title }),
        body ? h('p', { text: body }) : null,
        label ? h('label', { class: 'field' }, h('span', { text: label }), area, hint ? h('span', { class: 'hint', text: hint }) : null) : null,
        err,
        h('div', { class: 'foot' },
          h('button', { class: 'btn btn-ghost', type: 'button', onclick: () => close(null) }, t('action.cancel')),
          h('button', { class: 'btn ' + (danger ? 'btn-danger' : 'btn-primary'), type: 'submit' }, confirm)));
    });
  }

  // ---------- routing ----------
  function parseRoute() {
    const raw = (location.hash || '').replace(/^#\/?/, '');
    const qi = raw.indexOf('?');
    const path = qi >= 0 ? raw.slice(0, qi) : raw;
    const params = new URLSearchParams(qi >= 0 ? raw.slice(qi + 1) : '');
    const parts = path.split('/').filter(Boolean).map((p) => { try { return decodeURIComponent(p); } catch (_) { return p; } });
    const view = VIEWS.includes(parts[0]) ? parts[0] : 'overview';
    return { view, id: parts[1] || null, params, query: params.toString() };
  }

  function href(view, id, params) {
    const p = new URLSearchParams();
    if (params) {
      const entries = params instanceof URLSearchParams ? params.entries() : Object.entries(params);
      for (const [k, v] of entries) if (v != null && v !== '') p.set(k, v);
    }
    const qs = p.toString();
    return '#/' + view + (id ? '/' + encodeURIComponent(id) : '') + (qs ? '?' + qs : '');
  }

  // Changes the current list's parameters. Typing replaces the history entry;
  // tabs and pages add one, so Back works.
  function setParams(changes, replace) {
    const r = app.route;
    const p = new URLSearchParams(r.params);
    for (const [k, v] of Object.entries(changes)) {
      if (v == null || v === '' || v === false) p.delete(k); else p.set(k, v);
    }
    const next = href(r.view, r.id, p);
    if (replace) { history.replaceState(null, '', next); onRoute(); } else location.hash = next;
  }

  async function onRoute() {
    if (!app.content) return;
    const r = parseRoute();
    const prev = app.route;
    app.route = r;
    paintNav();
    if (!app.view || app.view.name !== r.view) {
      app.view = VIEW_BUILDERS[r.view]();
      app.content.replaceChildren(app.view.node);
      app.titleEl.textContent = t('nav.' + r.view);
      document.title = t('nav.' + r.view) + ' · ' + t('app.title');
      fillView(false, true);
    } else if (!prev || prev.query !== r.query) {
      fillView(false, false);
    }
    const key = r.id ? r.view + '/' + r.id : null;
    if (!key) closeDrawer(true);
    else if (!app.drawer || app.drawer.key !== key) openDrawer(r);
  }

  async function fillView(soft, reload) {
    const view = app.view;
    if (!view) return;
    if (soft) app.content.classList.add('refreshing');
    try {
      await view.fill(app.route, { soft, reload: reload || soft });
    } catch (e) {
      if (app.view !== view || lostAdmin(e)) return;
      if (soft) toast(explain(e), true);
      else view.fail(e, () => fillView(false, true));
    } finally {
      if (app.view === view) app.content.classList.remove('refreshing');
    }
  }

  // Everything on screen again, keeping it in place while new data arrives.
  async function refreshAll() {
    if (app.modalOpen) { app.stale = true; return; }
    const active = document.activeElement;
    if (active && app.content && app.content.contains(active) && /INPUT|TEXTAREA|SELECT/.test(active.tagName)) {
      // someone is typing in a filter: don't redraw under them
      if (app.drawer) await app.drawer.fill(true);
      return;
    }
    await Promise.all([fillView(true, true), app.drawer ? app.drawer.fill(true) : null]);
  }

  // ---------- live updates ----------
  function startLive() {
    if (app.channel) return;
    app.live = 'connecting';
    paintLive();
    try {
      app.channel = app.sb.channel('admin-live')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'tailor_shops' }, () => liveChange('shops'))
        .on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, () => liveChange('orders'))
        .on('postgres_changes', { event: '*', schema: 'public', table: 'account_blocks' }, () => liveChange('blocks'))
        .subscribe((status) => {
          if (status === 'SUBSCRIBED') app.live = 'on';
          else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') app.live = 'off';
          paintLive();
        });
    } catch (_) {
      app.live = 'off';
      paintLive();
    }
  }

  function stopLive() {
    const c = app.channel;
    app.channel = null;
    if (c && app.sb) { try { app.sb.removeChannel(c); } catch (_) { /* already gone */ } }
  }

  function liveChange(kind) {
    app.changed.add(kind);
    clearTimeout(app.liveTimer);
    app.liveTimer = setTimeout(applyLive, 900);
  }

  async function applyLive() {
    const kinds = app.changed;
    app.changed = new Set();
    if (kinds.has('shops')) await refreshBadge(true);
    await refreshAll();
  }

  async function refreshBadge(announce) {
    if (!app.sb || !app.content) return;
    try {
      const n = await countOf(app.sb.from('tailor_shops').select('tailor_id', { count: 'exact', head: true })
        .eq('review_status', 'pending'));
      if (announce && app.pending != null && n > app.pending) {
        toast(t('live.newShop'), false, { href: href('shops', null, { tab: 'pending' }), label: t('live.review') });
      }
      app.pending = n;
      paintBadge();
    } catch (_) { /* the badge just stays as it was */ }
  }

  function paintBadge() {
    const b = root.querySelector('[data-badge="shops"]');
    if (!b) return;
    b.hidden = !app.pending;
    b.textContent = app.pending ? String(app.pending) : '';
    b.setAttribute('aria-label', t('nav.pendingBadge', { n: app.pending || 0 }));
  }

  function paintLive() {
    if (!app.liveEl) return;
    app.liveEl.className = 'live ' + (app.live === 'on' ? 'on' : app.live === 'off' ? 'off' : '');
    app.liveEl.lastChild.textContent = t('live.' + app.live);
  }

  function paintNav() {
    for (const a of root.querySelectorAll('.nav a')) {
      if (a.dataset.view === app.route.view) a.setAttribute('aria-current', 'page');
      else a.removeAttribute('aria-current');
    }
  }

  // ---------- the admin's session ----------
  // Signed out after IDLE_MS without activity (warned WARN_MS before), and
  // MAX_MS after signing in whatever happens. Tabs share the sign-in time and
  // the last activity through localStorage: working in one tab keeps the
  // others open, and signing out in one signs out all. Signing out ends this
  // browser's session only; the same account stays signed in on the phone.
  // While signed in, it also re-checks every ADMIN_CHECK_MS (and when the tab
  // comes back) that the account is still in app_admins.
  const IDLE_MS = 30 * 60e3;
  const WARN_MS = 60e3;
  const MAX_MS = 12 * 3600e3;
  const MAX_WARN_MS = 5 * 60e3;
  const ADMIN_CHECK_MS = 60e3;
  const sess = { since: 0, active: 0, written: 0, maxWarned: false, checked: 0, warning: null };

  function readSession() {
    sess.since = Number(store.get('signedInAt')) || 0;
    sess.active = Math.max(sess.active, Number(store.get('activity')) || 0);
  }

  function beginSession() {
    const now = Date.now();
    Object.assign(sess, { since: now, active: now, written: now, maxWarned: false, checked: now });
    store.set('signedInAt', String(now));
    store.set('activity', String(now));
  }

  // Any input counts. Stored at most every 15 s, which is plenty for a
  // 30-minute timer and keeps other tabs informed.
  function markActive(force) {
    const now = Date.now();
    sess.active = now;
    if (force === true || now - sess.written > 15e3) {
      sess.written = now;
      store.set('activity', String(now));
    }
  }

  // Why the session must end at [now], or null. No sign-in time (a session
  // from before these rules, or storage was cleared) counts as too old.
  function sessionEnd(now) {
    if (!sess.since || now - sess.since >= MAX_MS) return 'max';
    if (now - sess.active >= IDLE_MS) return 'idle';
    return null;
  }

  function tick() {
    if (!app.content || !app.user) return;
    const now = Date.now();
    const end = sessionEnd(now);
    if (end) { signOut(end); return; }
    const left = IDLE_MS - (now - sess.active);
    if (left <= WARN_MS) showIdleWarning(Math.max(1, Math.ceil(left / 1000)));
    else closeIdleWarning();
    if (!sess.maxWarned && now - sess.since >= MAX_MS - MAX_WARN_MS) {
      sess.maxWarned = true;
      toast(t('session.maxSoon'));
    }
    if (now - sess.checked >= ADMIN_CHECK_MS) checkAdmin();
  }

  async function checkAdmin() {
    if (!app.content || !app.user) return;
    sess.checked = Date.now();
    try {
      if ((await rpc('is_admin')) !== true && app.content) signOut('notAdmin');
    } catch (e) {
      // offline or a hiccup: the next check tries again
    }
  }

  // "Still there?" with a countdown; any activity (here or in another tab)
  // or the button keeps the session.
  function showIdleWarning(secs) {
    if (!sess.warning) {
      const body = h('p');
      const stay = h('button', {
        class: 'btn btn-primary', type: 'button',
        onclick: () => { markActive(true); closeIdleWarning(); },
      }, t('session.stay'));
      const node = h('div', { class: 'modal-scrim session-warning' },
        h('div', { class: 'modal', role: 'alertdialog', 'aria-modal': 'true', 'aria-label': t('session.warnTitle') },
          h('h2', { text: t('session.warnTitle') }), body,
          h('div', { class: 'foot' },
            h('button', { class: 'btn btn-ghost', type: 'button', onclick: () => signOut() }, t('action.signOut')),
            stay)));
      document.body.append(node);
      stay.focus();
      sess.warning = { node, body };
    }
    sess.warning.body.textContent = t('session.warnBody', { s: secs });
  }

  function closeIdleWarning() {
    if (!sess.warning) return;
    sess.warning.node.remove();
    sess.warning = null;
  }

  for (const ev of ['pointerdown', 'pointermove', 'keydown', 'wheel', 'touchstart']) {
    document.addEventListener(ev, markActive, { capture: true, passive: true });
  }
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    tick();
    if (Date.now() - sess.checked > 10e3) checkAdmin();
  });
  window.addEventListener('storage', (ev) => {
    if (ev.key === 'jalabiya.admin.activity') {
      sess.active = Math.max(sess.active, Number(ev.newValue) || 0);
    } else if (ev.key === 'jalabiya.admin.signedInAt') {
      if (!ev.newValue && app.user) {
        signOut('otherTab');
      } else if (ev.newValue && !app.user && app.sb) {
        // signed in in another tab: follow it
        app.sb.auth.getSession().then(({ data }) => {
          if (app.user || !data || !data.session) return;
          app.user = data.session.user;
          readSession();
          enter();
        }).catch(() => {});
      }
    }
  });
  setInterval(tick, 1000);

  // ---------- start ----------
  function readConfig() {
    const c = window.JALABIYA_CONFIG;
    if (c && c.url && c.anonKey) return { url: c.url, anonKey: c.anonKey, fromFile: true };
    try {
      const s = JSON.parse(store.get('config') || 'null');
      if (s && s.url && s.anonKey) return s;
    } catch (_) { /* ignore a broken saved value */ }
    return null;
  }

  async function boot() {
    applyLang();
    app.config = readConfig();
    if (!app.config) { renderConnect(); return; }
    if (!window.supabase || typeof window.supabase.createClient !== 'function') {
      renderGate(() => [h('h1', { text: t('boot.noLibraryTitle') }), h('p', { text: t('boot.noLibrary') })]);
      return;
    }
    try {
      app.sb = window.supabase.createClient(app.config.url, app.config.anonKey, {
        auth: { persistSession: true, autoRefreshToken: true, storageKey: 'jalabiya-admin-auth' },
      });
    } catch (_) {
      renderConnect(t('connect.bad'));
      return;
    }
    app.sb.auth.onAuthStateChange((event) => {
      // the server ended the session (it could not be renewed), or another tab signed out
      if (event === 'SIGNED_OUT' && app.user) signOut('ended');
    });
    renderLoading();
    let session = null;
    try {
      const { data } = await app.sb.auth.getSession();
      session = data && data.session;
    } catch (_) { /* treated as signed out */ }
    app.user = session ? session.user : null;
    if (!app.user) { renderSignIn(); return; }
    // a session kept from earlier still follows the idle and 12-hour rules
    readSession();
    const end = sessionEnd(Date.now());
    if (end) await signOut(end);
    else await enter();
  }

  async function enter() {
    renderLoading();
    let ok = false;
    try {
      ok = (await rpc('is_admin')) === true;
    } catch (e) {
      if (isMissingSql(e)) {
        renderGate(() => [
          h('h1', { text: t('gate.noSqlTitle') }),
          h('p', { text: t('gate.noSqlBody') }),
          h('div', { class: 'actions' },
            h('button', { class: 'btn btn-primary', type: 'button', onclick: enter }, icon('refresh'), t('action.retry')),
            h('button', { class: 'btn', type: 'button', onclick: signOut }, t('action.signOut'))),
        ]);
      } else {
        renderGate(() => [errorBox(e, enter)]);
      }
      return;
    }
    if (!ok) { renderNotAdmin(); return; }
    sess.checked = Date.now();
    markActive(true);
    renderShell();
    startLive();
    refreshBadge(false);
    onRoute();
  }

  // Ends the session in this browser (every tab), never on the admin's
  // other devices. [reason] picks the note on the sign-in screen: idle, max,
  // notAdmin, otherTab or ended.
  async function signOut(reason) {
    const why = typeof reason === 'string' ? reason : null;
    app.stale = false;   // nothing to redraw once the dialogs below close
    for (const close of [...app.modals]) close(null);
    closeIdleWarning();
    leaveShell();
    app.user = null;
    Object.assign(sess, { since: 0, active: 0, written: 0, warning: null });
    store.set('signedInAt', null);   // other tabs hear this and sign out too
    store.set('activity', null);
    renderSignIn(why ? t('session.' + why) : '');
    try { await app.sb.auth.signOut({ scope: 'local' }); } catch (_) { /* signed out locally anyway */ }
  }

  function leaveShell() {
    stopLive();
    closeDrawer(true);
    app.content = null;
    app.view = null;
    app.route = null;
    app.pending = null;
  }

  function switchLang() {
    lang = lang === 'ar' ? 'en' : 'ar';
    store.set('lang', lang);
    applyLang();
    if (app.content) {
      // everything is drawn again in the new language, the open panel too
      closeDrawer(true);
      renderShell();
      app.view = null;
      app.route = null;
      onRoute();
    } else if (app.gate) {
      app.gate();
    }
  }

  // ---------- screens before the dashboard ----------
  function renderGate(content, opts) {
    app.gate = () => renderGate(content, opts);
    const host = app.config ? (() => { try { return new URL(app.config.url).host; } catch (_) { return app.config.url; } })() : null;
    const foot = h('div', { class: 'gate-foot' },
      h('button', { class: 'link-btn', type: 'button', onclick: switchLang }, t('lang.switch')),
      host && !(opts && opts.noProject) ? [
        h('span', { text: '·' }),
        h('span', { class: 'ltr', text: host }),
        app.config.fromFile ? null : [h('span', { text: '·' }),
          h('button', { class: 'link-btn', type: 'button', onclick: () => { store.set('config', null); location.reload(); } }, t('connect.change'))],
      ] : null);
    root.replaceChildren(h('div', { class: 'gate' },
      h('div', { class: 'gate-card' },
        h('div', { class: 'brand' }, h('img', { src: 'logo.png', alt: '' }),
          h('div', null, h('div', { class: 'muted small', text: t('app.name') }), h('b', { text: t('app.admin') }))),
        content(), foot)));
  }

  function renderLoading() {
    renderGate(() => [skeleton(4)], { noProject: true });
  }

  function renderConnect(message) {
    renderGate(() => {
      const url = h('input', { class: 'input', type: 'url', dir: 'ltr', required: true, placeholder: 'https://xxxx.supabase.co' });
      const key = h('input', { class: 'input', type: 'text', dir: 'ltr', required: true, autocomplete: 'off', spellcheck: 'false' });
      const err = h('div', { class: 'form-error', role: 'alert', text: message || '' });
      const submit = (ev) => {
        ev.preventDefault();
        const u = url.value.trim().replace(/\/+$/, '');
        const k = key.value.trim();
        if (!/^https:\/\/[^\s/]+/.test(u) || k.length < 20) { err.textContent = t('connect.invalid'); return; }
        store.set('config', JSON.stringify({ url: u, anonKey: k }));
        boot();
      };
      return [
        h('h1', { text: t('connect.title') }),
        h('p', { text: t('connect.body') }),
        h('form', { onsubmit: submit },
          h('label', { class: 'field' }, h('span', { text: t('connect.url') }), url),
          h('label', { class: 'field' }, h('span', { text: t('connect.key') }), key,
            h('span', { class: 'hint', text: t('connect.keyHint') })),
          err,
          h('button', { class: 'btn btn-primary btn-wide', type: 'submit' }, t('connect.save'))),
      ];
    });
  }

  // [note] says why the last session ended, if it did.
  function renderSignIn(note) {
    renderGate(() => {
      const email = h('input', { class: 'input', type: 'email', dir: 'ltr', required: true, autocomplete: 'username' });
      const pass = h('input', { class: 'input', type: 'password', dir: 'ltr', required: true, autocomplete: 'current-password' });
      const err = h('div', { class: 'form-error', role: 'alert' });
      const btn = h('button', { class: 'btn btn-primary btn-wide', type: 'submit' }, t('signin.submit'));
      const submit = async (ev) => {
        ev.preventDefault();
        err.textContent = '';
        btn.disabled = true;
        btn.classList.add('busy');
        try {
          const { data, error } = await app.sb.auth.signInWithPassword({ email: email.value.trim(), password: pass.value });
          if (error) throw error;
          app.user = data.user || (data.session && data.session.user);
          beginSession();
          await enter();
        } catch (e) {
          const m = String((e && e.message) || '');
          err.textContent = /invalid login/i.test(m) ? t('signin.bad')
            : /not confirmed/i.test(m) ? t('signin.unconfirmed') : explain(e);
          if (btn.isConnected) { btn.disabled = false; btn.classList.remove('busy'); }
        }
      };
      return [
        h('h1', { text: t('signin.title') }),
        h('p', { text: t('signin.body') }),
        note ? h('div', { class: 'banner gold session-note', role: 'status', text: note }) : null,
        h('form', { onsubmit: submit },
          h('label', { class: 'field' }, h('span', { text: t('signin.email') }), email),
          h('label', { class: 'field' }, h('span', { text: t('signin.password') }), pass),
          err, btn),
      ];
    });
  }

  function renderNotAdmin() {
    const email = (app.user && app.user.email) || 'you@example.com';
    renderGate(() => [
      h('h1', { text: t('gate.notAdminTitle') }),
      h('p', { text: t('gate.notAdminBody', { email }) }),
      h('pre', { text: "insert into public.app_admins (user_id)\nselect id from auth.users where email = '" + email.replace(/'/g, "''") + "';" }),
      h('div', { class: 'actions' },
        h('button', { class: 'btn btn-primary', type: 'button', onclick: enter }, icon('refresh'), t('gate.checkAgain')),
        h('button', { class: 'btn', type: 'button', onclick: signOut }, t('action.signOut'))),
    ]);
  }

  // ---------- the shell ----------
  function renderShell() {
    app.gate = null;
    const nav = h('nav', { class: 'nav', 'aria-label': t('nav.label') },
      VIEWS.map((v) => h('a', { href: '#/' + v, 'data-view': v },
        icon(NAV_ICONS[v]), h('span', { text: t('nav.' + v) }),
        v === 'shops' ? h('span', { class: 'badge', 'data-badge': 'shops', hidden: true }) : null)));
    const side = h('aside', { class: 'side' },
      h('div', { class: 'brand' }, h('img', { src: 'logo.png', alt: '' }),
        h('div', null, h('b', { text: t('app.name') }), h('small', { text: t('app.admin') }))),
      nav,
      h('div', { class: 'side-foot' },
        h('div', { class: 'who ltr', text: (app.user && app.user.email) || '' }),
        h('div', { class: 'row' },
          h('button', { class: 'btn btn-sm', type: 'button', onclick: switchLang }, icon('globe'), t('lang.short')),
          h('button', { class: 'btn btn-sm', type: 'button', onclick: signOut, title: t('action.signOut') }, icon('logout'), t('action.signOut')))));
    app.titleEl = h('h1');
    app.liveEl = h('span', { class: 'live', title: t('live.hint') }, h('i'), h('span'));
    const top = h('header', { class: 'topbar' }, app.titleEl, h('span', { class: 'spacer' }), app.liveEl,
      h('button', { class: 'btn btn-ghost btn-sm', type: 'button', onclick: () => { refreshBadge(false); refreshAll(); } },
        icon('refresh'), t('action.refresh')));
    app.content = h('main', { class: 'content', id: 'content' });
    root.replaceChildren(h('div', { class: 'shell' }, side, h('div', { class: 'main' }, top, app.content)));
    paintLive();
    paintBadge();
  }

  // ---------- shared pieces ----------
  function panel(title, body, extra) {
    return h('section', { class: 'panel' },
      title ? h('div', { class: 'panel-head' }, h('h2', { text: title }), h('span', { class: 'spacer' }), extra || null) : null,
      h('div', { class: 'panel-pad' }, body));
  }

  function kv(rows) {
    return h('div', { class: 'kv' }, rows.filter(Boolean).map(([k, v]) => [
      h('div', { class: 'k', text: k }),
      h('div', { class: 'v' }, v == null || v === '' ? '—' : v),
    ]));
  }

  function contactLinks(phone, whatsapp) {
    if (!phone) return '—';
    const wa = whatsapp || phone;
    return h('span', null,
      h('a', { href: 'tel:+' + intlNumber(phone), class: 'ltr' }, phone),
      h('span', { class: 'muted', text: ' · ' }),
      h('a', { href: 'https://wa.me/' + intlNumber(wa), target: '_blank', rel: 'noopener noreferrer' }, t('contact.whatsapp')));
  }

  function searchBox(placeholderKey, onChange) {
    let timer = null;
    const input = h('input', {
      class: 'input', type: 'search', placeholder: t(placeholderKey), 'aria-label': t(placeholderKey),
      oninput: () => { clearTimeout(timer); timer = setTimeout(() => onChange(input.value.trim()), 350); },
    });
    return {
      node: h('div', { class: 'search' }, icon('search'), input),
      sync(v) { if (document.activeElement !== input && input.value !== v) input.value = v; },
    };
  }

  function pager(page, total, onPage) {
    const from = total === 0 ? 0 : page * PAGE + 1;
    const to = Math.min(total, (page + 1) * PAGE);
    return h('div', { class: 'pager' },
      h('span', { text: t('pager.range', { from: num(from), to: num(to), total: num(total) }) }),
      h('div', { class: 'btns' },
        h('button', { class: 'btn btn-sm', type: 'button', disabled: page === 0, onclick: () => onPage(page - 1) }, t('pager.prev')),
        h('button', { class: 'btn btn-sm', type: 'button', disabled: to >= total, onclick: () => onPage(page + 1) }, t('pager.next'))));
  }

  // A table whose rows open a detail panel. [cols]: [{ label, cell(row), cls }].
  function table(cols, rows, open, selectedId) {
    const tr = (row) => {
      const go = () => open(row);
      const el = h('tr', {
        tabindex: '0',
        class: selectedId && row.__id === selectedId ? 'selected' : null,
        onclick: go,
        onkeydown: (ev) => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); go(); } },
      }, cols.map((c) => h('td', { class: c.cls || null, 'data-label': c.label }, c.cell(row))));
      return el;
    };
    return h('div', { class: 'table-wrap' },
      h('table', { class: 'data' },
        h('thead', null, h('tr', null, cols.map((c) => h('th', { class: c.cls || null, scope: 'col', text: c.label })))),
        h('tbody', null, rows.map(tr))));
  }

  function barList(items, max) {
    const top = Math.max(1, max == null ? Math.max(0, ...items.map((i) => i.n)) : max);
    return h('div', { class: 'bars' }, items.map((i) => {
      const row = h(i.href ? 'a' : 'div', { class: 'bar-row', href: i.href || null, style: { color: 'inherit', textDecoration: 'none' } },
        h('span', { class: 'ellipsis', text: i.label }),
        h('span', { class: 'track' }, h('span', { class: 'fill', style: {
          width: (i.n / top * 100) + '%', minWidth: i.n ? '' : '0px', background: 'var(--chart)', display: 'block' } })),
        h('span', { class: 'n', text: num(i.n) }));
      return row;
    }));
  }

  function swatch(kind, opt) {
    const name = opt.name || t(kind + '.' + opt.id);
    const extra = Number(opt.price) > 0 ? '+' + num(opt.price) : null;
    return h('span', { class: 'swatch' }, h('i', { style: { background: hex(opt.color) } }), name,
      extra ? h('small', { text: extra }) : null);
  }

  function timeline(items) {
    if (!items.length) return emptyState(t('common.nothingYet'), 'activity');
    return h('div', { class: 'timeline' }, items.map((it) => h('div', { class: 'ev' },
      h('div', { class: 'dot', style: { '--dot': it.color || 'var(--nile)' } }),
      h('div', { class: 'body' },
        h('b', { text: it.title }),
        h('div', { class: 'when', text: [dateTime(it.at), it.by].filter(Boolean).join(' · ') }),
        it.note ? h('div', { class: 'note', text: '“' + it.note + '”' }) : null,
        it.extra || null))));
  }

  function changeList(changes) {
    const keys = Object.keys(changes || {});
    if (!keys.length) return null;
    const val = (k, v) => {
      if (v == null || v === '') return '—';
      if (k === 'base_price') return money(v);
      if (k === 'accepts_orders') return yesNo(v);
      if (k === 'city') return cityName(v);
      if (k === 'lead_time_days') return t('shop.days', { n: v });
      return String(v);
    };
    return h('ul', { class: 'changes' }, keys.map((k) => h('li', null,
      t('field.' + k) + ': ',
      h('span', { class: 'from', text: val(k, changes[k].from) }), ' → ',
      h('span', { class: 'to', text: val(k, changes[k].to) }))));
  }

  // ---------- the chart ----------
  // One series of daily counts as columns, newest at the reading end
  // (mirrored in Arabic), with a hover/keyboard readout and a table view.
  function columnChart(points, title) {
    const wrap = h('div', { class: 'chart' });
    const tip = h('div', { class: 'tooltip', hidden: true, role: 'status' });
    const rtl = lang === 'ar';
    let active = -1;
    let bars = [];

    function draw() {
      const cw = wrap.clientWidth;
      const W = cw > 0 ? Math.max(320, cw - 32) : 600;
      const H = 190;
      const padTop = 22;
      const padBottom = 24;
      const axis = 30;
      const plotL = rtl ? 4 : axis;
      const plotR = rtl ? W - axis : W - 4;
      const base = H - padBottom;
      const n = points.length;
      const max = Math.max(0, ...points.map((p) => p.value));
      const step = niceStep(max);
      const top = Math.max(step, Math.ceil(max / step) * step);
      const y = (v) => base - (v / top) * (base - padTop);
      const slot = (plotR - plotL) / n;
      const bw = Math.min(24, Math.max(2, slot - 2));
      const xAt = (i) => (rtl ? plotR - (i + 1) * slot : plotL + i * slot);

      const svg = svgEl('svg', { viewBox: `0 0 ${W} ${H}`, width: W, height: H, tabindex: '0', role: 'group' });
      svg.setAttribute('aria-label', title + '. ' + t('chart.keys'));
      for (let v = 0; v <= top; v += step) {
        svg.append(svgEl('line', { class: 'grid-line', x1: plotL, x2: plotR, y1: y(v), y2: y(v) }));
        // tick labels sit in the gutter at the reading start, ending at its edge
        const label = svgEl('text', { class: 'axis-text', x: rtl ? W - 2 : axis - 6, y: y(v) + 4, 'text-anchor': 'end' });
        label.textContent = num(v);
        svg.append(label);
      }
      bars = points.map((p, i) => {
        const x = xAt(i) + (slot - bw) / 2;
        const hgt = base - y(p.value);
        const r = Math.min(4, hgt / 2, bw / 2);
        const path = svgEl('path', {
          class: 'bar',
          d: p.value > 0
            ? `M${x},${base}V${base - hgt + r}A${r},${r} 0 0 1 ${x + r},${base - hgt}H${x + bw - r}A${r},${r} 0 0 1 ${x + bw},${base - hgt + r}V${base}Z`
            : '',
        });
        svg.append(path);
        return { path, cx: xAt(i) + slot / 2, top: base - hgt };
      });
      // the hit area is the whole column slot, not just the painted bar
      points.forEach((p, i) => {
        const hit = svgEl('rect', { class: 'hit', x: xAt(i), y: padTop - 8, width: slot, height: base - padTop + 8 });
        hit.addEventListener('pointerenter', () => show(i));
        hit.addEventListener('pointerleave', hide);
        svg.append(hit);
      });
      if (max > 0) {
        const peak = points.findIndex((p) => p.value === max);
        const label = svgEl('text', { class: 'peak-text', x: bars[peak].cx, y: bars[peak].top - 6, 'text-anchor': 'middle' });
        label.textContent = num(max);
        svg.append(label);
      }
      for (const i of [0, Math.floor((n - 1) / 2), n - 1]) {
        const label = svgEl('text', { class: 'axis-text axis-date', x: bars[i].cx, y: H - 6, 'text-anchor': 'middle' });
        label.textContent = dayLabel(points[i].day);
        svg.append(label);
      }
      svg.addEventListener('keydown', (ev) => {
        const fwd = rtl ? 'ArrowLeft' : 'ArrowRight';
        const back = rtl ? 'ArrowRight' : 'ArrowLeft';
        if (ev.key !== fwd && ev.key !== back && ev.key !== 'Home' && ev.key !== 'End') return;
        ev.preventDefault();
        let i = active < 0 ? n - 1 : active;
        if (ev.key === fwd) i = Math.min(n - 1, i + 1);
        if (ev.key === back) i = Math.max(0, i - 1);
        if (ev.key === 'Home') i = 0;
        if (ev.key === 'End') i = n - 1;
        show(i);
      });
      svg.addEventListener('focus', () => show(active < 0 ? n - 1 : active));
      svg.addEventListener('blur', hide);
      return svg;
    }

    function show(i) {
      if (active >= 0 && bars[active]) bars[active].path.classList.remove('active');
      active = i;
      bars[i].path.classList.add('active');
      tip.replaceChildren(h('b', { text: num(points[i].value) }), dayLabel(points[i].day));
      tip.hidden = false;
      tip.style.left = (16 + bars[i].cx) + 'px';
      tip.style.top = (4 + Math.min(bars[i].top, 160) - 8) + 'px';
    }
    function hide() {
      if (active >= 0 && bars[active]) bars[active].path.classList.remove('active');
      tip.hidden = true;
    }

    // every value without hovering: the same numbers as a table
    const dataTable = h('details', null, h('summary', { text: t('chart.table') }),
      h('table', null, h('thead', null, h('tr', null, h('th', { text: t('chart.day') }), h('th', { text: title }))),
        h('tbody', null, points.slice().reverse().map((p) => h('tr', null, h('td', { text: date(p.day) }), h('td', { class: 'mono', text: num(p.value) }))))));
    const render = () => wrap.replaceChildren(draw(), tip, dataTable);
    wrap.redraw = render;
    render();
    // drawn again at its real width once it is on the page
    requestAnimationFrame(() => { if (wrap.isConnected) render(); });
    return wrap;
  }

  function niceStep(max) {
    if (max <= 4) return 1;
    const raw = max / 4;
    const mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const f = raw / mag;
    return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * mag;
  }

  let resizeTimer = null;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { for (const c of document.querySelectorAll('.chart')) if (c.redraw) c.redraw(); }, 200);
  });

  // ---------- overview ----------
  function overviewView() {
    const node = h('div', { class: 'stack' }, skeleton(8));
    let token = 0;
    async function fill() {
      const my = ++token;
      const since = new Date(Date.now() - STALE_DAYS * 864e5).toISOString();
      const [stats, waiting, stale, recent] = await Promise.all([
        rpc('admin_stats'),
        q(app.sb.from('tailor_shops').select('tailor_id, shop_name, city, neighbourhood, updated_at, owner:profiles!tailor_shops_tailor_id_fkey(full_name)')
          .eq('review_status', 'pending').order('updated_at', { ascending: true }).limit(5)),
        countOf(app.sb.from('orders').select('id', { count: 'exact', head: true }).in('status', WAITING).lt('updated_at', since)),
        q(app.sb.from('admin_actions').select('*').order('created_at', { ascending: false }).limit(6)),
      ]);
      if (my !== token) return;
      const orders = stats.orders || {};
      const shops = stats.shops || {};
      const sum = (list) => list.reduce((a, s) => a + (orders[s] || 0), 0);
      const valueLine = (obj) => Object.keys(obj || {}).length
        ? Object.entries(obj).map(([cur, v]) => money(v, cur)).join(' · ') : money(0);
      const days = stats.per_day || [];
      const pendingShops = shops.pending || 0;

      const attention = h('div', { class: 'attention' },
        h('a', { class: pendingShops ? 'gold' : 'calm', href: href('shops', null, { tab: 'pending' }) },
          h('span', { class: 'n', text: num(pendingShops) }), h('span', { class: 't', text: t('ov.pendingShops') })),
        h('a', { class: stale ? 'henna' : 'calm', href: href('orders', null, { stale: '1' }) },
          h('span', { class: 'n', text: num(stale) }), h('span', { class: 't', text: t('ov.staleOrders', { days: STALE_DAYS }) })),
        h('a', { class: 'calm', href: href('users', null, { blocked: '1' }) },
          h('span', { class: 'n', text: num(stats.blocked || 0) }), h('span', { class: 't', text: t('ov.blocked') })));

      const tile = (label, value, sub) => h('div', { class: 'panel tile' },
        h('div', { class: 'label', text: label }), h('div', { class: 'value', text: value }), sub ? h('div', { class: 'sub', text: sub }) : null);
      const tiles = h('div', { class: 'tiles' },
        tile(t('ov.customers'), num(stats.customers), t('ov.newUsers', { n: num(stats.new_users_7d) })),
        tile(t('ov.tailors'), num(stats.tailors), t('ov.listed', { n: num(stats.listed), taking: num(stats.taking_orders) })),
        tile(t('ov.ordersWeek'), num(stats.orders_7d), t('ov.ordersAll', { n: num(sum(STATUSES)) })),
        tile(t('ov.inProgress'), num(sum(ACTIVE)), valueLine(stats.open_value)),
        tile(t('ov.delivered'), num(orders.delivered || 0), valueLine(stats.delivered_value)));

      const charts = h('div', { class: 'grid grid-2' },
        h('section', { class: 'panel' }, h('div', { class: 'panel-head' }, h('h2', { text: t('ov.chartOrders') }),
          h('span', { class: 'spacer' }), h('span', { class: 'muted small', text: t('ov.last30') })),
        columnChart(days.map((d) => ({ day: d.day, value: d.orders })), t('ov.chartOrders'))),
        h('section', { class: 'panel' }, h('div', { class: 'panel-head' }, h('h2', { text: t('ov.chartUsers') }),
          h('span', { class: 'spacer' }), h('span', { class: 'muted small', text: t('ov.last30') })),
        columnChart(days.map((d) => ({ day: d.day, value: d.users })), t('ov.chartUsers'))));

      const breakdown = h('div', { class: 'grid grid-2' },
        h('section', { class: 'panel' }, h('div', { class: 'panel-head' }, h('h2', { text: t('ov.byStatus') })),
          h('div', { style: { height: '12px' } }),
          barList(STATUSES.map((s) => ({ label: t('status.' + s), n: orders[s] || 0, href: href('orders', null, { status: s }) })))),
        h('section', { class: 'panel' }, h('div', { class: 'panel-head' }, h('h2', { text: t('ov.byReview') })),
          h('div', { style: { height: '12px' } }),
          barList(REVIEWS.map((r) => ({ label: t('review.' + r), n: shops[r] || 0, href: href('shops', null, { tab: r }) })))));

      const waitingList = waiting.length
        ? h('div', { class: 'rows' }, waiting.map((s) => h('a', { class: 'rowlink', href: href('shops', s.tailor_id, { tab: 'pending' }) },
          icon('shop'),
          h('div', { class: 'grow' },
            h('div', { class: 'title ellipsis', text: s.shop_name }),
            h('div', { class: 'muted small ellipsis', text: [s.owner && s.owner.full_name, place(s.city, s.neighbourhood)].filter(Boolean).join(' · ') })),
          h('span', { class: 'muted small', text: t('ov.waitingSince', { when: ago(s.updated_at) }) }))))
        : emptyState(t('ov.noneWaiting'), 'check');
      const recentList = recent.length
        ? h('div', { class: 'rows' }, recent.map((a) => h('a', { class: 'rowlink', href: actionHref(a) },
          h('div', { class: 'grow' },
            h('div', { class: 'ellipsis' }, h('b', { text: t('act.' + a.action) }), ' · ', a.target_label || ''),
            h('div', { class: 'muted small ellipsis', text: [a.admin_email, ago(a.created_at)].filter(Boolean).join(' · ') })))))
        : emptyState(t('ov.noActivity'), 'activity');
      const lists = h('div', { class: 'grid grid-2' },
        h('section', { class: 'panel' }, h('div', { class: 'panel-head' }, h('h2', { text: t('ov.waitingTitle') }), h('span', { class: 'spacer' }),
          h('a', { class: 'small', href: href('shops', null, { tab: 'pending' }) }, t('common.seeAll'))), h('div', { style: { height: '8px' } }), waitingList),
        h('section', { class: 'panel' }, h('div', { class: 'panel-head' }, h('h2', { text: t('ov.recentTitle') }), h('span', { class: 'spacer' }),
          h('a', { class: 'small', href: href('activity') }, t('common.seeAll'))), h('div', { style: { height: '8px' } }), recentList));

      node.replaceChildren(attention, tiles, charts, breakdown, lists);
      if (app.pending !== pendingShops) { app.pending = pendingShops; paintBadge(); }
    }
    return { name: 'overview', node, fill, fail: (e, retry) => node.replaceChildren(h('div', { class: 'panel' }, errorBox(e, retry))) };
  }

  function actionHref(a) {
    const kind = String(a.action || '').split('.')[0];
    return kind === 'shop' ? href('shops', a.target_id, { tab: 'all' })
      : kind === 'user' ? href('users', a.target_id)
        : kind === 'order' ? href('orders', a.target_id) : href('activity');
  }

  // ---------- shops ----------
  function shopsView() {
    let data = null;
    let token = 0;
    const search = searchBox('shops.search', (v) => setParams({ q: v }, true));
    const tabsHost = h('div');
    const results = h('section', { class: 'panel' }, skeleton());
    const node = h('div', null, h('div', { class: 'toolbar' }, search.node), tabsHost, results);

    async function fill(r, opts) {
      const my = ++token;
      if (!data || opts.reload) {
        const [shops, blocks] = await Promise.all([
          q(app.sb.from('tailor_shops').select(SHOP_SELECT).order('updated_at', { ascending: false }).limit(1000)),
          q(app.sb.from('account_blocks').select('user_id').is('lifted_at', null)),
        ]);
        if (my !== token) return;
        data = { shops, blocked: new Set(blocks.map((b) => b.user_id)) };
      }
      const tab = SHOP_TABS.includes(r.params.get('tab')) ? r.params.get('tab') : 'pending';
      const text = (r.params.get('q') || '').toLowerCase();
      search.sync(r.params.get('q') || '');
      const counts = {};
      for (const id of SHOP_TABS) counts[id] = id === 'all' ? data.shops.length : data.shops.filter((s) => s.review_status === id).length;
      tabsHost.replaceChildren(h('div', { class: 'tabs', role: 'tablist' }, SHOP_TABS.map((id) => h('button', {
        type: 'button', role: 'tab', 'aria-selected': String(id === tab), onclick: () => setParams({ tab: id }),
      }, t(id === 'all' ? 'common.all' : 'shops.tab.' + id), h('span', { class: 'count', text: num(counts[id]) })))));

      let rows = data.shops.filter((s) => tab === 'all' || s.review_status === tab);
      if (text) {
        rows = rows.filter((s) => [s.shop_name, s.owner && s.owner.full_name, s.owner && s.owner.phone, cityName(s.city), s.city, s.neighbourhood]
          .some((v) => v && String(v).toLowerCase().includes(text)));
      }
      if (tab === 'pending') rows.sort((a, b) => String(a.updated_at).localeCompare(String(b.updated_at)));
      for (const s of rows) s.__id = s.tailor_id;
      if (!rows.length) {
        results.replaceChildren(emptyState(text ? t('common.noMatches') : t('shops.empty.' + tab), tab === 'pending' ? 'check' : 'shop'));
        return;
      }
      results.replaceChildren(table([
        { label: t('shops.col.shop'), cell: (s) => [h('span', { class: 'strong', text: s.shop_name }), h('span', { class: 'sub', text: (s.owner && s.owner.full_name) || '—' })] },
        { label: t('shops.col.place'), cell: (s) => place(s.city, s.neighbourhood) },
        { label: t('shops.col.price'), cls: 'num', cell: (s) => money(s.base_price, s.currency) },
        { label: t('shops.col.lead'), cls: 'num', cell: (s) => t('shop.days', { n: s.lead_time_days }) },
        { label: t('shops.col.taking'), cell: (s) => (s.accepts_orders ? t('shop.taking') : t('shop.paused')) },
        { label: t('shops.col.status'), cell: (s) => [reviewChip(s.review_status), data.blocked.has(s.tailor_id) ? [' ', chip(t('user.blocked'), 'tone-henna')] : null] },
        { label: t('shops.col.updated'), cell: (s) => h('span', { title: dateTime(s.updated_at), text: ago(s.updated_at) }) },
      ], rows, (s) => (location.hash = href('shops', s.tailor_id, r.params)), r.id));
    }
    return { name: 'shops', node, fill, fail: (e, retry) => results.replaceChildren(errorBox(e, retry)) };
  }

  function shopDrawer(id) {
    const d = drawerFrame();
    async function fill() {
      const [shop, users, events, orders] = await Promise.all([
        q(app.sb.from('tailor_shops').select(SHOP_SELECT).eq('tailor_id', id).maybeSingle()),
        rpc('admin_users', { p_user: id }),
        q(app.sb.from('shop_events').select('*').eq('tailor_id', id).order('id', { ascending: false }).limit(60)),
        q(app.sb.from('orders').select('status').eq('tailor_id', id).limit(5000)),
      ]);
      if (!shop) { d.notFound(); return; }
      const owner = (users && users[0]) || {};
      const status = shop.review_status;
      d.setHead(shop.shop_name, [reviewChip(status), owner.blocked ? chip(t('user.blocked'), 'tone-henna') : null,
        h('span', { text: place(shop.city, shop.neighbourhood) })]);

      const review = (to, opts) => async (ev) => {
        const btn = ev.currentTarget;
        const note = await askText(opts);
        if (note == null) return;
        await runAction(btn, () => rpc('admin_review_shop', { p_tailor: id, p_to: to, p_note: note || null }),
          t('shop.done.' + (status === 'suspended' && to === 'approved' ? 'reinstated' : to), { name: shop.shop_name }));
      };
      const approve = review('approved', {
        title: t(status === 'suspended' ? 'shop.reinstateTitle' : 'shop.approveTitle', { name: shop.shop_name }),
        body: t(status === 'suspended' ? 'shop.reinstateBody' : 'shop.approveBody'),
        label: t('shop.noteOptional'), hint: t('shop.noteHint'),
        confirm: t(status === 'suspended' ? 'shop.reinstate' : 'shop.approve'),
      });
      const actions = [];
      if (status === 'pending' || status === 'rejected' || status === 'suspended') {
        actions.push(h('button', { class: 'btn btn-primary', type: 'button', onclick: approve }, icon('check'),
          t(status === 'suspended' ? 'shop.reinstate' : status === 'rejected' ? 'shop.approveAnyway' : 'shop.approve')));
      }
      if (status === 'pending') {
        actions.push(h('button', {
          class: 'btn', type: 'button', onclick: review('rejected', {
            title: t('shop.rejectTitle', { name: shop.shop_name }), body: t('shop.rejectBody'),
            label: t('shop.reasonLabel'), hint: t('shop.reasonHint'), confirm: t('shop.reject'), danger: true, required: true,
          }),
        }, icon('undo'), t('shop.reject')));
      }
      if (status === 'approved') {
        actions.push(h('button', {
          class: 'btn', type: 'button', onclick: review('suspended', {
            title: t('shop.suspendTitle', { name: shop.shop_name }), body: t('shop.suspendBody'),
            label: t('shop.reasonLabel'), hint: t('shop.reasonHint'), confirm: t('shop.suspend'), danger: true, required: true,
          }),
        }, icon('block'), t('shop.suspend')));
      }
      actions.push(h('button', {
        class: 'btn', type: 'button', onclick: async (ev) => {
          const btn = ev.currentTarget;
          const edit = await editShopModal(shop);
          if (!edit) return;
          await runAction(btn, () => rpc('admin_update_shop', { p_tailor: id, p_shop: edit.changes, p_note: edit.note || null }),
            t('shop.done.edited'));
        },
      }, icon('edit'), t('shop.edit')));

      // why it is where it is
      const notices = [];
      const last = events[0];
      if (owner.blocked) {
        notices.push(h('div', { class: 'banner henna' }, h('b', { text: t('shop.ownerBlockedTitle') }),
          t('shop.ownerBlockedBody'), owner.block_reason ? h('div', { class: 'quote', text: '“' + owner.block_reason + '”' }) : null,
          h('a', { href: href('users', id) }, t('shop.openOwner'))));
      }
      if (status === 'pending' && last && (last.kind === 'changed' || last.kind === 'resubmitted')) {
        const lastNote = events.find((e) => e.kind === 'review' && e.to_status === 'rejected');
        notices.push(h('div', { class: 'banner gold' }, h('b', { text: t('shop.back.' + last.kind) }),
          last.kind === 'resubmitted' && lastNote && lastNote.note ? h('div', { text: t('shop.back.earlier', { note: lastNote.note }) }) : null,
          changeList(last.changes)));
      } else if (status === 'pending') {
        notices.push(h('div', { class: 'banner gold' }, h('b', { text: t('shop.newTitle') }), t('shop.newBody')));
      }
      if ((status === 'rejected' || status === 'suspended') && shop.review_note) {
        notices.push(h('div', { class: 'banner henna' }, h('b', { text: t('shop.toldTailor.' + status) }),
          h('div', { class: 'quote', text: '“' + shop.review_note + '”' })));
      }

      const counts = {};
      for (const o of orders) counts[o.status] = (counts[o.status] || 0) + 1;
      const colours = (kind, list) => (Array.isArray(list) && list.length
        ? h('div', { class: 'swatches' }, list.map((o) => swatch(kind, o)))
        : h('span', { class: 'muted', text: t('shop.standardPalette') }));

      d.setBody([
        h('div', { class: 'actions' }, actions,
          h('a', { class: 'btn', href: href('orders', null, { shop: id }) }, icon('orders'), t('shop.seeOrders')),
          h('a', { class: 'btn', href: href('users', id) }, icon('users'), t('shop.owner'))),
        notices,
        panel(t('shop.section.shop'), kv([
          [t('field.bio'), shop.bio],
          [t('field.city'), cityName(shop.city)],
          [t('field.neighbourhood'), shop.neighbourhood],
          [t('field.address_details'), shop.address_details],
          [t('field.base_price'), money(shop.base_price, shop.currency)],
          [t('field.lead_time_days'), t('shop.days', { n: shop.lead_time_days })],
          [t('field.accepts_orders'), yesNo(shop.accepts_orders)],
          [t('shop.opened'), dateTime(shop.created_at)],
          [t('shop.reviewed'), shop.reviewed_at ? dateTime(shop.reviewed_at) : t('shop.neverReviewed')],
        ])),
        panel(t('shop.section.owner'), kv([
          [t('user.name'), (shop.owner && shop.owner.full_name) || owner.full_name],
          [t('user.phone'), contactLinks(shop.owner && shop.owner.phone, shop.owner && shop.owner.whatsapp)],
          [t('user.email'), owner.email ? h('a', { href: 'mailto:' + owner.email, class: 'ltr', text: owner.email }) : '—'],
          [t('user.joined'), date(owner.created_at)],
          [t('user.lastSignIn'), owner.last_sign_in_at ? ago(owner.last_sign_in_at) : t('user.never')],
        ])),
        panel(t('shop.section.colours'), kv([
          [t('shop.cloth'), colours('cloth', shop.cloth_options)],
          [t('shop.thread'), colours('thread', shop.thread_options)],
        ])),
        panel(t('shop.section.orders'), orders.length
          ? h('div', { class: 'swatches' }, STATUSES.filter((s) => counts[s]).map((s) => h('a', { href: href('orders', null, { shop: id, status: s }), style: { textDecoration: 'none' } },
            chip(t('status.' + s) + ' · ' + num(counts[s]), statusTone(s)))))
          : h('span', { class: 'muted', text: t('shop.noOrders') })),
        panel(t('shop.section.history'), timeline(events.map((e) => shopEventItem(e, shop)))),
      ]);
    }
    return { key: null, node: d.node, frame: d, fill: guardDrawer(d, fill) };
  }

  function shopEventItem(e, shop) {
    const by = e.actor_id ? (e.actor_id === shop.tailor_id ? t('who.tailor') : t('who.admin')) : t('who.dashboard');
    let title;
    let color = 'var(--nile)';
    if (e.kind === 'review') {
      const what = e.to_status === 'approved' && e.from_status === 'suspended' ? 'reinstated' : e.to_status;
      title = t('sev.' + what);
      color = e.to_status === 'approved' ? 'var(--nile)' : 'var(--henna)';
    } else {
      title = t('sev.' + e.kind);
      color = e.kind === 'opened' ? 'var(--chalk)' : e.kind === 'edited' ? 'var(--ink)' : 'var(--gold)';
    }
    return { title, at: e.created_at, by, note: e.note, color, extra: changeList(e.changes) };
  }

  function editShopModal(shop) {
    return openModal((close) => {
      const known = CITIES.includes(shop.city);
      const name = h('input', { class: 'input', value: shop.shop_name, maxlength: 100, required: true });
      const bio = h('textarea', { class: 'textarea', maxlength: 500 });
      bio.value = shop.bio || '';
      const citySel = h('select', { class: 'select' },
        CITIES.map((c) => h('option', { value: c, selected: c === shop.city }, t('city.' + c))),
        h('option', { value: '__other', selected: !known }, t('edit.otherCity')));
      const cityOther = h('input', { class: 'input', value: known ? '' : shop.city, maxlength: 100, hidden: known, 'aria-label': t('edit.otherCity') });
      citySel.addEventListener('change', () => { cityOther.hidden = citySel.value !== '__other'; });
      const hood = h('input', { class: 'input', value: shop.neighbourhood, maxlength: 100 });
      const addr = h('textarea', { class: 'textarea', maxlength: 500 });
      addr.value = shop.address_details || '';
      const price = h('input', { class: 'input', type: 'number', min: 0, step: 'any', dir: 'ltr', value: String(Number(shop.base_price)) });
      const lead = h('input', { class: 'input', type: 'number', min: 1, max: 120, step: 1, dir: 'ltr', value: String(shop.lead_time_days) });
      const taking = h('input', { type: 'checkbox' });
      taking.checked = !!shop.accepts_orders;
      const note = h('input', { class: 'input', maxlength: 1000 });
      const err = h('div', { class: 'form-error', role: 'alert' });

      const submit = (ev) => {
        ev.preventDefault();
        const city = citySel.value === '__other' ? cityOther.value.trim() : citySel.value;
        const next = {
          shop_name: name.value.trim(), bio: bio.value.trim() || null, city,
          neighbourhood: hood.value.trim(), address_details: addr.value.trim(),
          base_price: Number(price.value), lead_time_days: Number(lead.value), accepts_orders: taking.checked,
        };
        if (!next.shop_name || !next.city || !next.neighbourhood || !next.address_details) { err.textContent = t('edit.required'); return; }
        if (!(price.value !== '' && next.base_price >= 0 && next.base_price <= 1e8)) { err.textContent = t('edit.badPrice'); return; }
        if (!(Number.isInteger(next.lead_time_days) && next.lead_time_days >= 1 && next.lead_time_days <= 120)) { err.textContent = t('edit.badLead'); return; }
        const changes = {};
        for (const [k, v] of Object.entries(next)) {
          const old = k === 'base_price' ? Number(shop[k]) : k === 'bio' ? (shop.bio || null) : shop[k];
          if (v !== old) changes[k] = v;
        }
        if (!Object.keys(changes).length) { err.textContent = t('edit.nothing'); return; }
        close({ changes, note: note.value.trim() });
      };
      const field = (label, input, hint) => h('label', { class: 'field' }, h('span', { text: label }), input, hint ? h('span', { class: 'hint', text: hint }) : null);
      return h('form', { onsubmit: submit },
        h('h2', { text: t('edit.title', { name: shop.shop_name }) }),
        h('p', { text: t('edit.body') }),
        field(t('field.shop_name'), name),
        field(t('field.bio'), bio),
        h('div', { class: 'row2' }, field(t('field.city'), h('div', { style: { display: 'grid', gap: '8px' } }, citySel, cityOther)), field(t('field.neighbourhood'), hood)),
        field(t('field.address_details'), addr),
        h('div', { class: 'row2' }, field(t('field.base_price'), price), field(t('field.lead_time_days'), lead)),
        h('label', { class: 'check' }, taking, h('span', { text: t('field.accepts_orders') })),
        field(t('edit.note'), note, t('edit.noteHint')),
        err,
        h('div', { class: 'foot' },
          h('button', { class: 'btn btn-ghost', type: 'button', onclick: () => close(null) }, t('action.cancel')),
          h('button', { class: 'btn btn-primary', type: 'submit' }, t('action.save'))));
    });
  }

  // ---------- orders ----------
  function ordersView() {
    let token = 0;
    const search = searchBox('orders.search', (v) => setParams({ q: v, p: null }, true));
    const status = h('select', { class: 'select', 'aria-label': t('orders.statusFilter'), onchange: () => setParams({ status: status.value, p: null, stale: null }) },
      h('option', { value: '' }, t('orders.allStatuses')),
      ['open', 'waiting', 'active'].map((g) => h('option', { value: g }, t('orders.group.' + g))),
      STATUSES.map((s) => h('option', { value: s }, t('status.' + s))));
    const chips = h('div', { class: 'toolbar', style: { marginBottom: 0 } });
    const results = h('section', { class: 'panel' }, skeleton());
    const node = h('div', null, h('div', { class: 'toolbar' }, search.node, status, chips), results);
    const names = {};

    async function nameOf(kind, id) {
      const k = kind + id;
      if (names[k] !== undefined) return names[k];
      try {
        const row = kind === 'shop'
          ? await q(app.sb.from('tailor_shops').select('shop_name').eq('tailor_id', id).maybeSingle())
          : await q(app.sb.from('profiles').select('full_name').eq('id', id).maybeSingle());
        names[k] = row ? (row.shop_name || row.full_name || ref(id)) : ref(id);
      } catch (_) { names[k] = ref(id); }
      return names[k];
    }

    async function fill(r) {
      const my = ++token;
      const p = r.params;
      const page = Math.max(0, parseInt(p.get('p') || '0', 10) || 0);
      const st = p.get('status') || '';
      const shop = isUuid(p.get('shop')) ? p.get('shop') : null;
      const customer = isUuid(p.get('customer')) ? p.get('customer') : null;
      const stale = p.get('stale') === '1';
      const text = clean(p.get('q'));
      search.sync(p.get('q') || '');
      status.value = stale ? 'waiting' : st;

      let qb = app.sb.from('orders').select(ORDER_LIST_SELECT, { count: 'exact' })
        .order('created_at', { ascending: false }).range(page * PAGE, page * PAGE + PAGE - 1);
      const group = { open: OPEN, waiting: WAITING, active: ACTIVE }[st];
      if (stale) qb = qb.in('status', WAITING).lt('updated_at', new Date(Date.now() - STALE_DAYS * 864e5).toISOString());
      else if (group) qb = qb.in('status', group);
      else if (STATUSES.includes(st)) qb = qb.eq('status', st);
      if (shop) qb = qb.eq('tailor_id', shop);
      if (customer) qb = qb.eq('customer_id', customer);
      const short = /^#?([0-9a-f]{8})$/i.exec(text);
      if (short) {
        const pre = short[1].toLowerCase();
        qb = qb.gte('id', pre + '-0000-0000-0000-000000000000').lte('id', pre + '-ffff-ffff-ffff-ffffffffffff');
      } else if (text) {
        qb = qb.or('wearer_label.ilike.*' + text + '*,delivery->>name.ilike.*' + text + '*');
      }
      const [{ data, count, error }, shopName, customerName] = await Promise.all([
        qb, shop ? nameOf('shop', shop) : null, customer ? nameOf('user', customer) : null]);
      if (error) throw error;
      if (my !== token) return;

      const filterChip = (label, clear) => h('span', { class: 'filter-chip' }, label,
        h('button', { type: 'button', 'aria-label': t('common.clearFilter'), onclick: clear }, icon('close')));
      chips.replaceChildren(
        shop ? filterChip(t('orders.shopIs', { name: shopName }), () => setParams({ shop: null, p: null })) : null,
        customer ? filterChip(t('orders.customerIs', { name: customerName }), () => setParams({ customer: null, p: null })) : null,
        stale ? filterChip(t('orders.staleChip', { days: STALE_DAYS }), () => setParams({ stale: null, p: null })) : null);

      const rows = data || [];
      for (const o of rows) o.__id = o.id;
      if (!rows.length) {
        results.replaceChildren(emptyState(text || st || shop || customer || stale ? t('common.noMatches') : t('orders.empty'), 'orders'));
        return;
      }
      results.replaceChildren(
        table([
          { label: t('orders.col.ref'), cell: (o) => h('span', { class: 'mono', text: ref(o.id) }) },
          { label: t('orders.col.placed'), cell: (o) => h('span', { title: dateTime(o.created_at), text: date(o.created_at) }) },
          { label: t('orders.col.customer'), cell: (o) => [h('span', { class: 'strong', text: (o.delivery && o.delivery.name) || '—' }), h('span', { class: 'sub ltr', text: (o.delivery && o.delivery.phone) || '' })] },
          { label: t('orders.col.for'), cell: (o) => o.wearer_label + (o.quantity > 1 ? ' × ' + o.quantity : '') },
          { label: t('orders.col.shop'), cell: (o) => (o.shop && o.shop.shop_name) || '—' },
          { label: t('orders.col.amount'), cls: 'num', cell: (o) => (o.price != null ? money(o.price, o.currency) : o.estimate != null ? '≈ ' + money(o.estimate, o.currency) : '—') },
          { label: t('orders.col.due'), cell: (o) => date(o.due_date) },
          { label: t('orders.col.status'), cell: (o) => statusChip(o.status) },
        ], rows, (o) => (location.hash = href('orders', o.id, r.params)), r.id),
        pager(page, count || 0, (n) => setParams({ p: n || null })));
    }
    return { name: 'orders', node, fill, fail: (e, retry) => results.replaceChildren(errorBox(e, retry)) };
  }

  function orderDrawer(id) {
    const d = drawerFrame();
    async function fill() {
      const [o, events] = await Promise.all([
        q(app.sb.from('orders').select(ORDER_SELECT).eq('id', id).maybeSingle()),
        q(app.sb.from('order_events').select('*').eq('order_id', id).order('id', { ascending: false })),
      ]);
      if (!o) { d.notFound(); return; }
      d.setHead(t('order.title', { ref: ref(o.id) }), [statusChip(o.status), h('span', { text: dateTime(o.created_at) })]);
      const design = o.design || {};
      const option = (kind) => {
        const opt = design[kind + '_option'] || (design[kind] ? { id: design[kind], color: STD_COLOURS[kind][design[kind]], price: 0 } : null);
        return opt ? swatch(kind, opt) : '—';
      };
      const m = o.measurements || {};
      const del = o.delivery || {};
      const shop = o.shop || {};
      const owner = shop.owner || {};
      const customer = o.customer || {};
      const actions = [];
      if (OPEN.includes(o.status)) {
        actions.push(h('button', {
          class: 'btn', type: 'button', onclick: async (ev) => {
            const btn = ev.currentTarget;
            const note = await askText({
              title: t('order.cancelTitle', { ref: ref(o.id) }), body: t('order.cancelBody'),
              label: t('order.cancelReason'), hint: t('order.cancelHint'), confirm: t('order.cancel'), danger: true, required: true,
            });
            if (note == null) return;
            await runAction(btn, () => rpc('admin_cancel_order', { p_order: id, p_note: note }), t('order.cancelled'));
          },
        }, icon('block'), t('order.cancel')));
      }
      const who = (e) => (e.kind === 'admin' ? t('who.support') : e.actor_id === o.customer_id ? t('who.customer')
        : e.actor_id === o.tailor_id ? t('who.tailor') : '');
      const eventTitle = (e) => (['edited', 'accepted', 'rejected', 'admin'].includes(e.kind) ? t('event.' + e.kind) : t('event.' + e.to_status));

      d.setBody([
        h('div', { class: 'actions' }, actions,
          h('a', { class: 'btn', href: href('users', o.customer_id) }, icon('users'), t('order.customer')),
          h('a', { class: 'btn', href: href('shops', o.tailor_id, { tab: 'all' }) }, icon('shop'), t('order.shop'))),
        o.status === 'cancelled' && events[0] && events[0].kind === 'admin'
          ? h('div', { class: 'banner henna' }, h('b', { text: t('order.cancelledBySupport') }), h('div', { class: 'quote', text: '“' + (events[0].note || '') + '”' }))
          : null,
        panel(t('order.section.summary'), kv([
          [t('order.for'), o.wearer_label],
          [t('order.quantity'), num(o.quantity)],
          [t('order.estimate'), o.estimate != null ? money(o.estimate, o.currency) : '—'],
          [t('order.price'), o.price != null ? money(o.price, o.currency) : t('order.noPrice')],
          [t('order.due'), date(o.due_date)],
          [t('order.updated'), dateTime(o.updated_at)],
        ])),
        panel(t('order.section.people'), kv([
          [t('order.customer'), h('a', { href: href('users', o.customer_id), text: customer.full_name || del.name || '—' })],
          [t('user.phone'), contactLinks(customer.phone || del.phone, customer.whatsapp || del.whatsapp)],
          [t('order.shop'), h('a', { href: href('shops', o.tailor_id, { tab: 'all' }), text: shop.shop_name || '—' })],
          [t('order.tailor'), owner.full_name],
          [t('user.phone'), contactLinks(owner.phone, owner.whatsapp)],
        ])),
        panel(t('order.section.delivery'), kv([
          [t('user.name'), del.name],
          [t('user.phone'), del.phone ? h('span', { class: 'ltr', text: del.phone }) : '—'],
          [t('field.city'), cityName(del.city)],
          [t('field.neighbourhood'), del.neighbourhood],
          [t('field.address_details'), del.address_details],
        ])),
        panel(t('order.section.design'), kv([
          [t('design.cut'), design.cut ? t('cut.' + design.cut) : '—'],
          [t('design.collar'), design.collar ? t('collar.' + design.collar) : '—'],
          [t('design.emb'), design.emb ? t('emb.' + design.emb) : '—'],
          [t('design.cloth'), option('cloth')],
          [t('design.thread'), option('thread')],
          [t('design.hem'), design.hem != null ? num(design.hem) + ' ' + t('unit.cm') : '—'],
          [t('design.cuff'), design.cuff != null ? num(design.cuff) + ' ' + t('unit.cm') : '—'],
        ])),
        panel(t('order.section.sizes'), h('div', { class: 'measures' }, MEASURES.map((k) => h('div', null,
          h('small', { text: t('m.' + k) }), h('b', { text: m[k] != null ? num(m[k]) : '—' }), ' ', h('span', { class: 'muted small', text: t('unit.cm') }))))),
        o.customer_notes || o.tailor_note ? panel(t('order.section.notes'), kv([
          o.customer_notes ? [t('order.customerNotes'), o.customer_notes] : null,
          o.tailor_note ? [t('order.tailorNote'), o.tailor_note] : null,
        ])) : null,
        panel(t('order.section.history'), timeline(events.map((e) => ({
          title: eventTitle(e), at: e.created_at, by: who(e), note: e.note,
          color: e.kind === 'admin' ? 'var(--henna)' : `var(--${{ 'tone-gold': 'gold-ink', 'tone-henna': 'henna', 'tone-grey': 'muted', 'tone-ink': 'ink', 'tone-nile': 'nile' }[statusTone(e.to_status)]})`,
        })))),
      ]);
    }
    return { key: null, node: d.node, frame: d, fill: guardDrawer(d, fill) };
  }

  // ---------- users ----------
  function usersView() {
    let token = 0;
    const search = searchBox('users.search', (v) => setParams({ q: v, p: null }, true));
    const blocked = h('input', { type: 'checkbox', onchange: () => setParams({ blocked: blocked.checked ? '1' : null, p: null }) });
    const tabsHost = h('div');
    const results = h('section', { class: 'panel' }, skeleton());
    const node = h('div', null,
      h('div', { class: 'toolbar' }, search.node, h('label', { class: 'check' }, blocked, h('span', { text: t('users.blockedOnly') }))),
      tabsHost, results);

    async function fill(r) {
      const my = ++token;
      const p = r.params;
      const role = USER_TABS.includes(p.get('role')) ? p.get('role') : 'all';
      const page = Math.max(0, parseInt(p.get('p') || '0', 10) || 0);
      const onlyBlocked = p.get('blocked') === '1';
      search.sync(p.get('q') || '');
      blocked.checked = onlyBlocked;
      tabsHost.replaceChildren(h('div', { class: 'tabs', role: 'tablist' }, USER_TABS.map((id) => h('button', {
        type: 'button', role: 'tab', 'aria-selected': String(id === role), onclick: () => setParams({ role: id === 'all' ? null : id, p: null }),
      }, t('users.tab.' + id)))));

      const rows = await rpc('admin_users', {
        p_search: (p.get('q') || '').trim() || null,
        p_role: role === 'all' ? null : role,
        p_blocked: onlyBlocked ? true : null,
        p_limit: PAGE,
        p_offset: page * PAGE,
      });
      if (my !== token) return;
      const total = rows.length ? Number(rows[0].total_count) : 0;
      for (const u of rows) u.__id = u.id;
      if (!rows.length) {
        results.replaceChildren(emptyState(p.get('q') || onlyBlocked || role !== 'all' ? t('common.noMatches') : t('users.empty'), 'users'));
        return;
      }
      results.replaceChildren(
        table([
          { label: t('users.col.name'), cell: (u) => [h('span', { class: 'strong', text: u.full_name || '—' }), h('span', { class: 'sub ltr', text: u.email || '' })] },
          { label: t('users.col.role'), cell: (u) => [chip(t('role.' + u.role), u.role === 'tailor' ? 'tone-gold' : 'tone-grey'), u.is_admin ? [' ', chip(t('role.admin'), 'tone-dark')] : null] },
          { label: t('users.col.phone'), cell: (u) => h('span', { class: 'ltr', text: u.phone || '—' }) },
          { label: t('users.col.place'), cell: (u) => place(u.city, u.neighbourhood) },
          { label: t('users.col.joined'), cell: (u) => date(u.created_at) },
          { label: t('users.col.lastSignIn'), cell: (u) => (u.last_sign_in_at ? ago(u.last_sign_in_at) : t('user.never')) },
          { label: t('users.col.orders'), cls: 'num', cell: (u) => num(u.orders_count) },
          { label: t('users.col.status'), cell: (u) => (u.blocked ? chip(t('user.blocked'), 'tone-henna') : chip(t('user.active'), 'tone-nile')) },
        ], rows, (u) => (location.hash = href('users', u.id, r.params)), r.id),
        pager(page, total, (n) => setParams({ p: n || null })));
    }
    return { name: 'users', node, fill, fail: (e, retry) => results.replaceChildren(errorBox(e, retry)) };
  }

  function userDrawer(id) {
    const d = drawerFrame();
    async function fill() {
      const [users, orders, history] = await Promise.all([
        rpc('admin_users', { p_user: id }),
        q(app.sb.from('orders').select('id, status, wearer_label, created_at, price, estimate, currency, customer_id, tailor_id, shop:tailor_shops!orders_tailor_id_fkey(shop_name)')
          .or('customer_id.eq.' + id + ',tailor_id.eq.' + id).order('created_at', { ascending: false }).limit(10)),
        q(app.sb.from('admin_actions').select('*').eq('target_id', id).order('created_at', { ascending: false }).limit(20)),
      ]);
      const u = users && users[0];
      if (!u) { d.notFound(); return; }
      d.setHead(u.full_name || u.email || t('user.unnamed'), [
        chip(t('role.' + u.role), u.role === 'tailor' ? 'tone-gold' : 'tone-grey'),
        u.is_admin ? chip(t('role.admin'), 'tone-dark') : null,
        u.blocked ? chip(t('user.blocked'), 'tone-henna') : null,
        h('span', { class: 'ltr', text: u.email || '' }),
      ]);
      const actions = [];
      if (!u.is_admin && !u.blocked) {
        actions.push(h('button', {
          class: 'btn', type: 'button', onclick: async (ev) => {
            const btn = ev.currentTarget;
            const reason = await askText({
              title: t('user.blockTitle', { name: u.full_name || u.email }), body: t(u.role === 'tailor' ? 'user.blockBodyTailor' : 'user.blockBody'),
              label: t('user.blockReason'), hint: t('user.blockHint'), confirm: t('user.block'), danger: true, required: true,
            });
            if (reason == null) return;
            await runAction(btn, () => rpc('admin_block_user', { p_user: id, p_reason: reason }), t('user.blockedDone'));
          },
        }, icon('block'), t('user.block')));
      }
      if (u.blocked) {
        actions.push(h('button', {
          class: 'btn btn-primary', type: 'button', onclick: async (ev) => {
            const btn = ev.currentTarget;
            const note = await askText({
              title: t('user.unblockTitle', { name: u.full_name || u.email }), body: t('user.unblockBody'),
              label: t('shop.noteOptional'), confirm: t('user.unblock'),
            });
            if (note == null) return;
            await runAction(btn, () => rpc('admin_unblock_user', { p_user: id, p_note: note || null }), t('user.unblockedDone'));
          },
        }, icon('check'), t('user.unblock')));
      }
      if (u.shop_name) actions.push(h('a', { class: 'btn', href: href('shops', id, { tab: 'all' }) }, icon('shop'), t('user.openShop')));
      actions.push(h('a', { class: 'btn', href: href('orders', null, u.role === 'tailor' ? { shop: id } : { customer: id }) }, icon('orders'), t('user.allOrders')));

      d.setBody([
        h('div', { class: 'actions' }, actions),
        u.blocked ? h('div', { class: 'banner henna' }, h('b', { text: t('user.blockedSince', { when: dateTime(u.blocked_at) }) }),
          h('div', { class: 'quote', text: '“' + (u.block_reason || '') + '”' }),
          h('div', { class: 'small', text: t(u.role === 'tailor' ? 'user.blockedEffectTailor' : 'user.blockedEffect') })) : null,
        u.is_admin ? h('div', { class: 'banner nile', text: t('user.isAdmin') }) : null,
        panel(t('user.section.contact'), kv([
          [t('user.email'), u.email ? h('a', { href: 'mailto:' + u.email, class: 'ltr', text: u.email }) : '—'],
          [t('user.phone'), contactLinks(u.phone, u.whatsapp)],
          [t('field.city'), cityName(u.city)],
          [t('field.neighbourhood'), u.neighbourhood],
          [t('field.address_details'), u.address_details],
        ])),
        panel(t('user.section.account'), kv([
          [t('users.col.role'), t('role.' + u.role)],
          [t('user.joined'), dateTime(u.created_at)],
          [t('user.lastSignIn'), u.last_sign_in_at ? dateTime(u.last_sign_in_at) : t('user.never')],
          [t('users.col.orders'), num(u.orders_count)],
          u.role === 'tailor' ? [t('user.shop'), u.shop_name
            ? h('a', { href: href('shops', id, { tab: 'all' }) }, u.shop_name + ' ', reviewChip(u.review_status))
            : t('user.noShop')] : null,
        ])),
        panel(t('user.section.orders'), orders.length
          ? h('div', { class: 'rows', style: { margin: '0 -20px' } }, orders.map((o) => h('a', { class: 'rowlink', href: href('orders', o.id) },
            h('span', { class: 'mono small', text: ref(o.id) }),
            h('div', { class: 'grow' },
              h('div', { class: 'ellipsis', text: o.wearer_label + ' · ' + ((o.shop && o.shop.shop_name) || '') }),
              h('div', { class: 'muted small', text: date(o.created_at) + ' · ' + (o.price != null ? money(o.price, o.currency) : o.estimate != null ? '≈ ' + money(o.estimate, o.currency) : '—') })),
            statusChip(o.status))))
          : h('span', { class: 'muted', text: t('user.noOrders') })),
        panel(t('user.section.history'), timeline(history.map((a) => ({
          title: t('act.' + a.action), at: a.created_at, by: a.admin_email, note: a.note,
          color: /blocked|suspended|rejected|cancelled/.test(a.action) && !/unblocked/.test(a.action) ? 'var(--henna)' : 'var(--nile)',
        })))),
      ]);
    }
    return { key: null, node: d.node, frame: d, fill: guardDrawer(d, fill) };
  }

  // ---------- activity ----------
  function activityView() {
    let token = 0;
    const kind = h('select', { class: 'select', 'aria-label': t('activity.filter'), onchange: () => setParams({ kind: kind.value || null, p: null }) },
      ['', 'shop', 'user', 'order'].map((k) => h('option', { value: k }, t('activity.kind.' + (k || 'all')))));
    const results = h('section', { class: 'panel' }, skeleton());
    const node = h('div', null, h('div', { class: 'toolbar' }, kind), results);
    async function fill(r) {
      const my = ++token;
      const k = ['shop', 'user', 'order'].includes(r.params.get('kind')) ? r.params.get('kind') : '';
      const page = Math.max(0, parseInt(r.params.get('p') || '0', 10) || 0);
      kind.value = k;
      let qb = app.sb.from('admin_actions').select('*', { count: 'exact' }).order('created_at', { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1);
      if (k) qb = qb.like('action', k + '.%');
      const { data, count, error } = await qb;
      if (error) throw error;
      if (my !== token) return;
      if (!data.length) { results.replaceChildren(emptyState(t('ov.noActivity'), 'activity')); return; }
      results.replaceChildren(
        h('div', { class: 'rows' }, data.map((a) => h('div', null,
          h('div', null, h('b', { text: t('act.' + a.action) }), ' · ', h('a', { href: actionHref(a), text: a.target_label || ref(a.target_id) })),
          h('div', { class: 'muted small', text: [a.admin_email, dateTime(a.created_at)].filter(Boolean).join(' · ') }),
          a.note ? h('div', { class: 'note', style: { marginTop: '4px' }, text: '“' + a.note + '”' }) : null,
          a.action === 'shop.edited' ? changeList(a.details) : null))),
        pager(page, count || 0, (n) => setParams({ p: n || null })));
    }
    return { name: 'activity', node, fill, fail: (e, retry) => results.replaceChildren(errorBox(e, retry)) };
  }

  const VIEW_BUILDERS = { overview: overviewView, shops: shopsView, orders: ordersView, users: usersView, activity: activityView };
  const DRAWER_BUILDERS = { shops: shopDrawer, orders: orderDrawer, users: userDrawer };

  // ---------- the detail panel ----------
  function drawerFrame() {
    const title = h('h2', { tabindex: '-1' });
    const meta = h('div', { class: 'meta' });
    const body = h('div', { class: 'drawer-body' }, skeleton(10));
    const closeBtn = h('button', { class: 'btn btn-ghost btn-sm', type: 'button', 'aria-label': t('action.close'), onclick: () => closeDrawer() }, icon('close'));
    const node = h('aside', { class: 'drawer', role: 'dialog', 'aria-modal': 'false', 'aria-label': t('common.details') },
      h('div', { class: 'drawer-head' }, h('div', { class: 'titles' }, title, meta), closeBtn), body);
    return {
      node, body,
      setHead(text, metaKids) { title.textContent = text; node.setAttribute('aria-label', text); meta.replaceChildren(); add(meta, metaKids); },
      setBody(kids) { body.replaceChildren(); add(body, kids); },
      notFound() { title.textContent = t('common.notFound'); meta.replaceChildren(); body.replaceChildren(emptyState(t('common.notFoundBody'), 'search')); },
      fail(e, retry) { body.replaceChildren(errorBox(e, retry)); },
    };
  }

  // Loads a panel; a failed first load shows the error in the panel, a failed
  // refresh keeps what is shown and says so.
  function guardDrawer(d, fill) {
    let token = 0;
    const run = async (soft) => {
      const my = ++token;
      try {
        await fill();
      } catch (e) {
        if (my !== token || lostAdmin(e)) return;
        if (soft) toast(explain(e), true);
        else d.fail(e, () => run(false));
      }
    };
    return run;
  }

  const isUuid = (v) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(v || ''));

  function openDrawer(r) {
    closeDrawer(true);
    const build = DRAWER_BUILDERS[r.view];
    if (!build) return;
    const drawer = build(r.id);
    drawer.key = r.view + '/' + r.id;
    if (!isUuid(r.id)) drawer.fill = async () => drawer.frame.notFound();
    const scrim = h('div', { class: 'scrim', onclick: () => closeDrawer() });
    drawer.scrim = scrim;
    app.drawer = drawer;
    document.body.append(scrim, drawer.node);
    // screen readers start at the panel's title; Escape or the × closes it
    drawer.node.querySelector('.drawer-head h2').focus();
    drawer.fill(false);
  }

  // Closes the panel; [quiet] when the route already says so.
  function closeDrawer(quiet) {
    const d = app.drawer;
    if (!d) return;
    app.drawer = null;
    d.node.remove();
    if (d.scrim) d.scrim.remove();
    if (!quiet && app.route && app.route.id) location.hash = href(app.route.view, null, app.route.params);
  }

  document.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape' && app.drawer && !app.modalOpen) closeDrawer();
  });
  window.addEventListener('hashchange', () => { if (app.content) onRoute(); });

  // for tool/tests/admin_test.mjs
  window.JalabiyaAdmin = { missing, lang: () => lang, app, tick };

  boot();
})();
