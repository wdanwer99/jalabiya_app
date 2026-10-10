// Runs supabase/schema.sql on a real Postgres engine (PGlite) with a stub of
// Supabase's auth schema, then exercises every rule as real users would.
import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';

const sql = (name) => fs.readFileSync(new URL(`../../supabase/${name}`, import.meta.url), 'utf8');
const schema = sql('schema.sql');
const securityFixes = sql('security_fixes.sql');
const shopOptions = sql('shop_options.sql');
const priceOffers = sql('price_offers.sql');
const adminSql = sql('admin.sql');
const db = new PGlite();

// --- what Supabase already provides before your SQL runs ---
await db.exec(`
  create role anon nologin;
  create role authenticated nologin;
  create schema auth;
  create table auth.users (
    id uuid primary key default gen_random_uuid(),
    email text unique,
    raw_user_meta_data jsonb default '{}'::jsonb,
    created_at timestamptz default now(),
    last_sign_in_at timestamptz
  );
  create function auth.uid() returns uuid language sql stable as $$
    select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
  create function auth.role() returns text language sql stable as $$
    select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))::text $$;
  grant usage on schema public, auth to anon, authenticated;
  grant execute on all functions in schema auth to anon, authenticated;
  create publication supabase_realtime;
`);

await db.exec(schema);
await db.exec(schema);           // must be safe to re-run
for (const file of [securityFixes, shopOptions, shopOptions, priceOffers, priceOffers, adminSql, adminSql]) {
  await db.exec(file);
}
const results = [];
const check = (ok, msg) => results.push((ok ? 'PASS  ' : 'FAIL  ') + msg);

// run SQL as a signed-in app user, exactly like PostgREST does
async function as(uid, sql, params = []) {
  return db.transaction(async (tx) => {
    await tx.query(`select set_config('request.jwt.claim.sub', $1, true),
                           set_config('request.jwt.claim.role', 'authenticated', true)`, [uid]);
    await tx.query('set local role authenticated');
    return tx.query(sql, params);
  });
}
async function err(uid, sql, params = []) {
  try { await as(uid, sql, params); return 'NO ERROR'; }
  catch (e) { return e.message; }
}
async function admin(sql, params = []) { return db.query(sql, params); }

async function signUp(email, meta) {
  const r = await admin(`insert into auth.users (email, raw_user_meta_data) values ($1, $2) returning id`,
    [email, JSON.stringify(meta)]);
  return r.rows[0].id;
}

// ---------- sign-up ----------
const C1 = await signUp('amna-son@x.sd', { role: 'customer', full_name: 'Osman Ali', phone: '0912345678' });
const C2 = await signUp('other@x.sd',    { role: 'customer', full_name: 'Hassan Idris', phone: '0998765432' });
const T1 = await signUp('tailor@x.sd',   { role: 'tailor',   full_name: 'Abdelrahim', phone: '0911111111' });
const T2 = await signUp('new@x.sd',      { role: 'tailor',   full_name: 'Babiker', phone: '0922222222' });
const roles = (await admin(`select id, role from profiles`)).rows;
check(roles.length === 4 && roles.find(r => r.id === T1).role === 'tailor' && roles.find(r => r.id === C1).role === 'customer',
  'sign-up trigger creates a profile with the chosen role');

// ---------- profile gate ----------
const meas = { height: 178, chest: 104, waist: 94, hip: 102, shoulder: 47, arm: 61, neck: 40 };
const design = { cut: 'regular', collar: 'band', emb: 'neck', cloth: 'damuriya', thread: 'gold', hem: 4, cuff: 34 };
const SUBMIT = `select submit_order($1, $2, $3, $4, $5, $6, $7) as id`;

check((await err(C1, SUBMIT, [T1, null, 'Me', meas, design, 1, null])).includes('PROFILE_INCOMPLETE'),
  'an incomplete customer profile cannot order');

await as(C1, `update profiles set city='khartoum', neighbourhood='Riyadh', address_details='Street 15, near the mosque', role='tailor' where id=$1`, [C1]);
check((await admin(`select role from profiles where id=$1`, [C1])).rows[0].role === 'customer',
  'a customer cannot promote themselves to tailor');
check((await admin(`select profile_is_complete($1) c`, [C1])).rows[0].c === true, 'completed customer profile passes the gate');

// ---------- tailor shops ----------
await as(T1, `update profiles set city='omdurman', neighbourhood='Souq', address_details='Souq Omdurman, row 3' where id=$1`, [T1]);
check((await admin(`select profile_is_complete($1) c`, [T1])).rows[0].c === false, 'a tailor without a shop is not complete');
await as(T1, `insert into tailor_shops (tailor_id, shop_name, city, neighbourhood, address_details, base_price, lead_time_days, approved)
              values ($1, 'Abdelrahim Tailoring', 'omdurman', 'Souq', 'Row 3', 25000, 7, true)`, [T1]);
check((await admin(`select approved from tailor_shops where tailor_id=$1`, [T1])).rows[0].approved === false,
  'a tailor cannot approve their own shop on insert');
check((await admin(`select profile_is_complete($1) c`, [T1])).rows[0].c === true, 'a tailor with a shop is complete');
await admin(`update tailor_shops set approved = true where tailor_id = $1`, [T1]);
await as(T1, `update tailor_shops set approved=false, bio='Since 1998' where tailor_id=$1`, [T1]);
const s1 = (await admin(`select approved, bio from tailor_shops where tailor_id=$1`, [T1])).rows[0];
check(s1.approved === true && s1.bio === 'Since 1998', 'a tailor edits their shop but cannot change its approval');

await as(T2, `update profiles set city='bahri', neighbourhood='Shambat', address_details='Near the bridge' where id=$1`, [T2]);
await as(T2, `insert into tailor_shops (tailor_id, shop_name, city, neighbourhood, address_details, base_price, lead_time_days)
              values ($1, 'Babiker', 'bahri', 'Shambat', 'Bridge', 20000, 10)`, [T2]);
check((await err(C1, `insert into tailor_shops (tailor_id, shop_name, city, neighbourhood, address_details, base_price, lead_time_days)
                      values ($1,'Fake','x','x','xxxxx',1,1)`, [C1])).includes('row-level security'),
  'a customer cannot open a shop');
const visible = (await as(C1, `select tailor_id from tailor_shops`)).rows.map(r => r.tailor_id);
check(visible.includes(T1) && !visible.includes(T2), 'customers see approved shops only');

// ---------- measurement sets ----------
const setId = (await as(C1, `insert into measurement_sets (owner_id, label, relation, height, chest, waist, hip, shoulder, arm, neck)
  values ($1, 'Me', 'self', 178, 104, 94, 102, 47, 61, 40) returning id`, [C1])).rows[0].id;
check((await as(C2, `select id from measurement_sets`)).rows.length === 0, "another customer cannot read someone's sizes");
check((await err(C1, `insert into measurement_sets (owner_id, label, height, chest, waist, hip, shoulder, arm, neck)
  values ($1, 'Bad', 178, 300, 94, 102, 47, 61, 40)`, [C1])).includes('check constraint'),
  'impossible sizes are rejected by the table itself');
const otherSet = (await as(C2, `insert into measurement_sets (owner_id, label, height, chest, waist, hip, shoulder, arm, neck)
  values ($1, 'Hassan', 170, 96, 88, 98, 44, 58, 38) returning id`, [C2])).rows[0].id;

// ---------- submitting ----------
check((await err(C1, SUBMIT, [T2, null, 'Me', meas, design, 1, null])).includes('TAILOR_UNAVAILABLE'),
  'cannot order from an unapproved tailor');
check((await err(C1, SUBMIT, [T1, null, 'Me', { ...meas, chest: 300 }, design, 1, null])).includes('INVALID_MEASUREMENTS'),
  'out-of-range sizes rejected');
check((await err(C1, SUBMIT, [T1, null, 'Me', { ...meas, chest: '104' }, design, 1, null])).includes('INVALID_MEASUREMENTS'),
  'a size sent as text is rejected cleanly, not a crash');
check((await err(C1, SUBMIT, [T1, null, 'Me', meas, { ...design, cloth: 'silk' }, 1, null])).includes('OPTION_UNAVAILABLE'),
  'unknown cloth rejected');
check((await err(C1, SUBMIT, [T1, null, 'Me', meas, { ...design, collar: 'hood' }, 1, null])).includes('INVALID_DESIGN'),
  'unknown collar rejected');
check((await err(C1, SUBMIT, [T1, otherSet, 'Me', meas, design, 1, null])).includes('INVALID_MEASUREMENT_SET'),
  "cannot attach someone else's saved sizes");
check((await err(C1, SUBMIT, [T1, null, 'Me', meas, design, 0, null])).includes('INVALID_QUANTITY'), 'quantity 0 rejected');
check((await err(T1, SUBMIT, [T1, null, 'Me', meas, design, 1, null])).includes('NOT_A_CUSTOMER'), 'a tailor cannot place orders');

const orderId = (await as(C1, SUBMIT, [T1, setId, '  Me  ', { ...meas, evil: 'x' }, design, 2, ' Wide sleeves please '])).rows[0].id;
const o1 = (await admin(`select * from orders where id=$1`, [orderId])).rows[0];
check(o1.status === 'submitted' && o1.quantity === 2 && o1.wearer_label === 'Me' && o1.customer_notes === 'Wide sleeves please',
  'a valid order is stored as submitted, text trimmed');
check(!('evil' in o1.measurements) && o1.delivery.neighbourhood === 'Riyadh' && o1.delivery.phone === '0912345678',
  'unknown keys stripped; delivery address frozen from the profile');

check((await err(C1, `insert into orders (customer_id, tailor_id, wearer_label, measurements, design, delivery)
  values ($1,$2,'x','{}','{}','{}')`, [C1, T1])).includes('permission denied'),
  'orders cannot be inserted directly');
check((await err(C1, `update orders set status='delivered', price=1 where id=$1`, [orderId])).includes('permission denied'),
  'orders cannot be edited directly');

// ---------- who sees what ----------
check((await as(T1, `select id from orders`)).rows.length === 1, 'the tailor sees the order');
check((await as(C2, `select id from orders`)).rows.length === 0, 'another customer does not');
check((await as(T2, `select id from orders`)).rows.length === 0, 'another tailor does not');
const custSeen = (await as(T1, `select full_name, phone, city, neighbourhood, address_details from profiles where id=$1`, [C1])).rows[0];
check(custSeen && custSeen.full_name === 'Osman Ali' && custSeen.address_details.includes('mosque'),
  "the tailor reads the customer's full profile");
check((await as(T2, `select id from profiles where id=$1`, [C1])).rows.length === 0, "an unrelated tailor cannot read the customer's profile");
check((await as(C2, `select id from profiles where id=$1`, [C1])).rows.length === 0, 'customers cannot read each other');
check((await as(C1, `select phone from profiles where id=$1`, [T1])).rows.length === 1, "the customer can read the tailor's contact");

// ---------- the order's life ----------
const ADV = `select advance_order($1, $2::order_status, $3, $4, $5)`;
check((await err(C1, ADV, [orderId, 'confirmed', null, 100, '2099-01-01'])).includes('TRANSITION_NOT_ALLOWED'),
  'a customer cannot confirm their own order');
check((await err(T1, ADV, [orderId, 'confirmed', null, null, null])).includes('PRICE_AND_DATE_REQUIRED'),
  'confirming needs a price and date');
check((await err(T1, ADV, [orderId, 'confirmed', null, 100, '2000-01-01'])).includes('PRICE_AND_DATE_REQUIRED'),
  'the due date cannot be in the past');
check((await err(T1, ADV, [orderId, 'changes_requested', '  ', null, null])).includes('NOTE_REQUIRED'),
  'asking for changes needs a note');
await as(T1, ADV, [orderId, 'changes_requested', 'Arm length looks short, please re-measure', null, null]);
check((await admin(`select status, tailor_note from orders where id=$1`, [orderId])).rows[0].tailor_note.startsWith('Arm'),
  'the tailor asks for changes with a note');

const UPD = `select update_order($1, $2, $3, $4, $5, $6)`;
await as(C1, UPD, [orderId, 'Me', { ...meas, arm: 63 }, { ...design, cut: 'full' }, 1, null]);
const o2 = (await admin(`select status, measurements, design, quantity from orders where id=$1`, [orderId])).rows[0];
check(o2.status === 'submitted' && Number(o2.measurements.arm) === 63 && o2.design.cut === 'full' && o2.quantity === 1,
  'the customer fixes it and it returns to the tailor');
check((await err(C2, UPD, [orderId, 'Me', meas, design, 1, null])).includes('ORDER_NOT_FOUND'),
  "a stranger cannot edit someone's order");

// 30000 is not the 25000 estimate, so the customer has to accept it
await as(T1, ADV, [orderId, 'confirmed', 'Ready in a week', 30000, '2099-06-01']);
await as(C1, ADV, [orderId, 'confirmed', null, null, null]);
const o3 = (await admin(`select status, price, due_date from orders where id=$1`, [orderId])).rows[0];
check(o3.status === 'confirmed' && Number(o3.price) === 30000, 'the tailor confirms with price and date');
check((await err(C1, UPD, [orderId, 'Me', meas, design, 1, null])).includes('ORDER_LOCKED'), 'a confirmed order is locked from edits');
check((await err(C1, ADV, [orderId, 'cancelled', null, null, null])).includes('TRANSITION_NOT_ALLOWED'), 'a confirmed order cannot be cancelled');
check((await err(T1, ADV, [orderId, 'ready', null, null, null])).includes('TRANSITION_NOT_ALLOWED'), 'steps cannot be skipped');
for (const s of ['cutting', 'sewing', 'ready', 'delivered']) await as(T1, ADV, [orderId, s, null, null, null]);
check((await admin(`select status from orders where id=$1`, [orderId])).rows[0].status === 'delivered', 'cutting → sewing → ready → delivered');

// ---------- history ----------
const ev = (await as(C1, `select to_status, kind from order_events where order_id=$1 order by id`, [orderId])).rows;
check(ev.map(e => e.to_status).join(',') === 'submitted,changes_requested,submitted,price_offered,confirmed,cutting,sewing,ready,delivered'
      && ev[2].kind === 'edited', 'every step is logged in order, including the edit');
check((await as(C2, `select id from order_events`)).rows.length === 0, "strangers cannot read an order's history");

// ---------- frozen snapshot ----------
await as(C1, `update measurement_sets set chest = 120 where id=$1`, [setId]);
await as(C1, `delete from measurement_sets where id=$1`, [setId]);
const o4 = (await admin(`select measurements, measurement_set_id from orders where id=$1`, [orderId])).rows[0];
check(Number(o4.measurements.chest) === 104 && o4.measurement_set_id === null,
  'changing or deleting saved sizes never alters a placed order');

// ---------- the shop's own cloth and thread colours ----------
check(o1.design.cloth_option.id === 'damuriya' && Number(o1.design.cloth_option.price) === 0,
  'a shop with no colours of its own offers the standard palette at no extra');

const SET_OPTS = `update tailor_shops set cloth_options = $2, thread_options = $3 where tailor_id = $1`;
const cloths = [{ id: 'white-cotton', name: 'Egyptian cotton', color: 0xFAFAF5, price: 5000 },
                { id: 'navy', name: 'Navy', color: 0x1F2A44, price: 0 }];
const threads = [{ id: 'silver', name: 'Silver', color: 0xC0C0C0, price: 1500 }];
check((await err(T1, SET_OPTS, [T1, JSON.stringify([...cloths, cloths[0]]), '[]'])).includes('shops_options_valid'),
  'a shop cannot list the same colour twice');
check((await err(T1, SET_OPTS, [T1, JSON.stringify([{ ...cloths[0], color: 'red' }]), '[]'])).includes('shops_options_valid'),
  'a colour must be a number');
check((await err(T1, SET_OPTS, [T1, JSON.stringify([{ ...cloths[0], price: -1 }]), '[]'])).includes('shops_options_valid'),
  'an extra price cannot be negative');
check((await err(T1, SET_OPTS, [T1, JSON.stringify([{ ...cloths[0], name: ' ' }]), '[]'])).includes('shops_options_valid'),
  'a colour needs a name');
await as(T1, SET_OPTS, [T1, JSON.stringify(cloths), JSON.stringify(threads)]);
await as(T2, SET_OPTS, [T1, JSON.stringify([]), JSON.stringify([])]);
check((await admin(`select jsonb_array_length(cloth_options) n from tailor_shops where tailor_id=$1`, [T1])).rows[0].n === 2,
  "a tailor saves their colours; another tailor cannot change them");

check((await err(C1, SUBMIT, [T1, null, 'Me', meas, design, 1, null])).includes('OPTION_UNAVAILABLE'),
  'a standard colour is refused once the shop lists its own');
check((await err(C1, SUBMIT, [T1, null, 'Me', meas, { ...design, cloth: 'navy' }, 1, null])).includes('OPTION_UNAVAILABLE'),
  'a thread the shop does not offer is refused');
const mine = { ...design, cloth: 'white-cotton', thread: 'silver',
               cloth_option: { id: 'white-cotton', name: 'Fake', color: 0, price: 0 } };
const o6 = (await as(C1, SUBMIT, [T1, null, 'Me', meas, mine, 1, null])).rows[0].id;
const d6 = (await admin(`select design from orders where id=$1`, [o6])).rows[0].design;
check(d6.cloth_option.name === 'Egyptian cotton' && Number(d6.cloth_option.price) === 5000
      && d6.cloth_option.color === 0xFAFAF5 && d6.thread_option.id === 'silver',
  "the order stores the shop's own name, colour and price, not what the app sent");

await as(T1, SET_OPTS, [T1, JSON.stringify([{ ...cloths[0], price: 9000 }]), JSON.stringify(threads)]);
const d6b = (await admin(`select design from orders where id=$1`, [o6])).rows[0].design;
check(Number(d6b.cloth_option.price) === 5000, 'changing the price later never alters a placed order');
check((await err(C1, UPD, [o6, 'Me', meas, { ...mine, cloth: 'navy' }, 1, null])).includes('OPTION_UNAVAILABLE'),
  'an edit cannot pick a colour the shop removed');
await as(C1, UPD, [o6, 'Me', meas, mine, 1, null]);
check(Number((await admin(`select design from orders where id=$1`, [o6])).rows[0].design.cloth_option.price) === 9000,
  "an edit takes the shop's current price");
await as(C1, ADV, [o6, 'cancelled', null, null, null]);

// ---------- the customer approves a changed price or date ----------
// T1 now: base 25000, white cotton +9000, silver thread +1500, lead time 7 days
const day = async (n) => (await admin(`select (current_date + $1::int)::text d`, [n])).rows[0].d;
const inWeek = await day(7), inMonth = await day(30);
const fresh = async () => (await as(C1, SUBMIT, [T1, null, 'Me', meas, mine, 2, null])).rows[0].id;
const row = async (id) => (await admin(`select status, price, due_date, estimate from orders where id=$1`, [id])).rows[0];
const lastEvent = async (id) => (await admin(`select to_status, kind, note from order_events where order_id=$1 order by id desc limit 1`, [id])).rows[0];

const p1 = await fresh();
check(Number((await row(p1)).estimate) === 71000, 'the order keeps the estimate the customer saw: (base + extras) × quantity');
await as(T1, ADV, [p1, 'confirmed', null, 71000, inWeek]);
check((await row(p1)).status === 'confirmed', 'the estimated price within the usual time confirms straight away');

const p2 = await fresh();
await as(T1, ADV, [p2, 'confirmed', 'Silver thread costs more now', 80000, inWeek]);
const r2 = await row(p2);
check(r2.status === 'price_offered' && Number(r2.price) === 80000, 'a different price waits for the customer');
check((await err(T1, ADV, [p2, 'cutting', null, null, null])).includes('TRANSITION_NOT_ALLOWED'),
  'the tailor cannot start work before the customer accepts');
check((await err(C1, UPD, [p2, 'Me', meas, mine, 2, null])).includes('ORDER_LOCKED'), 'an offered order cannot be edited');
check((await err(C2, ADV, [p2, 'confirmed', null, null, null])).includes('ORDER_NOT_FOUND'),
  "a stranger cannot accept someone's offer");
await as(C1, ADV, [p2, 'confirmed', null, 1, '2000-01-01']);
const r2b = await row(p2);
check(r2b.status === 'confirmed' && Number(r2b.price) === 80000 && (await lastEvent(p2)).kind === 'accepted',
  "accepting confirms at the tailor's price; the customer cannot change it");

const p3 = await fresh();
await as(T1, ADV, [p3, 'confirmed', null, 71000, inMonth]);
check((await row(p3)).status === 'price_offered', 'a later date than the shop usually needs also waits for the customer');
await as(C1, ADV, [p3, 'cancelled', 'Too late for the wedding', null, null]);
const e3 = await lastEvent(p3);
check((await row(p3)).status === 'cancelled' && e3.kind === 'rejected' && e3.note === 'Too late for the wedding',
  'rejecting cancels the order, with the reason in its history');

const p4 = await fresh();
await as(T1, ADV, [p4, 'confirmed', null, 90000, inWeek]);
await as(T1, ADV, [p4, 'declined', 'Out of silver thread', null, null]);
check((await row(p4)).status === 'declined', 'the tailor can still decline while the customer decides');

// ---------- customer cancel path ----------
const o5 = (await as(C1, SUBMIT, [T1, null, 'Ahmed (son)', meas, mine, 1, null])).rows[0].id;
await as(C1, ADV, [o5, 'cancelled', null, null, null]);
check((await admin(`select status from orders where id=$1`, [o5])).rows[0].status === 'cancelled', 'a customer cancels before confirmation');

// ---------- the admin dashboard (admin.sql) ----------
const A1 = await signUp('admin@x.sd', { full_name: 'Site admin' });
await admin(`insert into app_admins (user_id) values ($1)`, [A1]);
const REVIEW = `select admin_review_shop($1, $2, $3)`;
const EDIT = `select admin_update_shop($1, $2, $3)`;
const BLOCK = `select admin_block_user($1, $2)`;
const UNBLOCK = `select admin_unblock_user($1, null)`;
const CANCEL = `select admin_cancel_order($1, $2)`;
const shop = async (t) => (await admin(`select * from tailor_shops where tailor_id=$1`, [t])).rows[0];
const listed = async () => (await as(C1, `select tailor_id from tailor_shops where approved`)).rows.map(r => r.tailor_id);

check((await shop(T1)).review_status === 'approved' && (await shop(T2)).review_status === 'pending',
  'a shop approved by hand in the table editor counts as approved; a new one waits for review');
check((await as(A1, `select is_admin() a`)).rows[0].a === true && (await as(T1, `select is_admin() a`)).rows[0].a === false,
  'is_admin() tells admins from everyone else');
check((await err(T2, REVIEW, [T2, 'approved', null])).includes('NOT_AN_ADMIN')
      && (await err(C1, `select admin_stats()`)).includes('NOT_AN_ADMIN')
      && (await err(C1, `select * from admin_users()`)).includes('NOT_AN_ADMIN'),
  'only admins can review shops, read the stats or list people');
check((await err(C1, `insert into app_admins (user_id) values ($1)`, [C1])).includes('permission denied')
      && (await err(C1, `insert into account_blocks (user_id, reason) values ($1, 'x')`, [C2])).includes('permission denied'),
  'nobody makes themselves an admin or blocks someone from the app');
await as(T2, `update tailor_shops set review_status = 'approved', review_note = 'self' where tailor_id = $1`, [T2]);
check((await shop(T2)).review_status === 'pending' && (await shop(T2)).approved === false,
  'a tailor cannot set their own review status');

const allOrders = Number((await admin(`select count(*) n from orders`)).rows[0].n);
check((await as(A1, `select tailor_id from tailor_shops`)).rows.length === 2
      && (await as(A1, `select id from orders`)).rows.length === allOrders
      && (await as(A1, `select id from profiles`)).rows.length === 5
      && (await as(A1, `select id from measurement_sets`)).rows.length === 0,
  "an admin reads every shop, order and profile, but not people's saved sizes");

check((await err(A1, REVIEW, [T2, 'rejected', '  '])).includes('NOTE_REQUIRED'), 'rejecting a shop needs a reason');
check((await err(A1, REVIEW, [T2, 'suspended', 'x'])).includes('REVIEW_NOT_ALLOWED'), 'a shop under review cannot be suspended');
await as(A1, REVIEW, [T2, 'rejected', 'Add your street and shop number']);
const r1 = (await as(T2, `select review_status, review_note, approved from tailor_shops where tailor_id=$1`, [T2])).rows[0];
check(r1.review_status === 'rejected' && r1.review_note.startsWith('Add your street') && r1.approved === false,
  'the tailor sees the rejection and its reason');
await as(T2, `update tailor_shops set address_details = 'Shambat, by the bridge, shop 4' where tailor_id=$1`, [T2]);
check((await shop(T2)).review_status === 'pending', 'saving a rejected shop sends it back for review');
await as(A1, REVIEW, [T2, 'approved', null]);
check((await listed()).includes(T2), 'approving lists the shop for customers');

await as(T2, `update tailor_shops set bio = 'Since 2001', lead_time_days = 12, base_price = 21000 where tailor_id=$1`, [T2]);
check((await shop(T2)).review_status === 'approved', 'changing the bio, price or sewing time keeps a shop listed');
await as(T2, `update tailor_shops set shop_name = 'Babiker & Sons' where tailor_id=$1`, [T2]);
check((await shop(T2)).review_status === 'pending' && !(await listed()).includes(T2)
      && (await err(C1, SUBMIT, [T2, null, 'Me', meas, design, 1, null])).includes('TAILOR_UNAVAILABLE'),
  'renaming an approved shop hides it until it is reviewed again');
const sev = (await admin(`select kind, from_status, to_status, note, changes from shop_events where tailor_id=$1 order by id`, [T2])).rows;
check(sev.map(e => e.kind).join(',') === 'opened,review,resubmitted,review,changed'
      && sev[1].note.startsWith('Add your street')
      && sev[4].changes.shop_name.from === 'Babiker' && sev[4].changes.shop_name.to === 'Babiker & Sons',
  "the shop's history records each step, with the reason and what changed");
await as(A1, REVIEW, [T2, 'approved', 'Name checked']);

await admin(`update tailor_shops set approved = false where tailor_id=$1`, [T2]);
const hand = await shop(T2);
await admin(`update tailor_shops set approved = true where tailor_id=$1`, [T2]);
check(hand.review_status === 'suspended' && (await shop(T2)).review_status === 'approved',
  'flipping approved by hand in the table editor still works');

// an open order to carry through suspension, blocking and cancelling
const live = (await as(C1, SUBMIT, [T1, null, 'Me', meas, mine, 1, null])).rows[0].id;
check((await err(A1, REVIEW, [T1, 'suspended', ''])).includes('NOTE_REQUIRED'), 'suspending a shop needs a reason');
await as(A1, REVIEW, [T1, 'suspended', 'Complaints about late orders, call us']);
check(!(await listed()).includes(T1) && (await err(C1, SUBMIT, [T1, null, 'Me', meas, mine, 1, null])).includes('TAILOR_UNAVAILABLE'),
  'a suspended shop is hidden and takes no new orders');
await as(T1, ADV, [live, 'confirmed', null, Number((await row(live)).estimate), inWeek]);
check((await row(live)).status === 'confirmed', 'orders already placed with a suspended shop carry on');
await as(A1, REVIEW, [T1, 'approved', null]);
check((await listed()).includes(T1)
      && (await admin(`select action from admin_actions order by id desc limit 1`)).rows[0].action === 'shop.reinstated',
  'reinstating lists the shop again, logged as a reinstatement');

check((await err(A1, EDIT, [T1, JSON.stringify({ lead_time_days: 0 }), null])).includes('INVALID_SHOP')
      && (await err(A1, EDIT, [T1, JSON.stringify({ base_price: 'abc' }), null])).includes('INVALID_SHOP')
      && (await err(A1, EDIT, [T1, JSON.stringify({ shop_name: '  ' }), null])).includes('INVALID_SHOP'),
  'an admin edit is checked like the shop form');
await as(A1, EDIT, [T1, JSON.stringify({ shop_name: ' Abdelrahim Tailoring House ', base_price: 26000 }), 'Typo in the name']);
const e1 = await shop(T1);
const lastShopEvent = (await admin(`select kind, note, changes from shop_events where tailor_id=$1 order by id desc limit 1`, [T1])).rows[0];
check(e1.shop_name === 'Abdelrahim Tailoring House' && Number(e1.base_price) === 26000 && e1.review_status === 'approved'
      && lastShopEvent.kind === 'edited' && lastShopEvent.note === 'Typo in the name'
      && Number(lastShopEvent.changes.base_price.from) === 25000,
  "an admin fixes a shop's details; it stays listed and the change is logged");
check(Number((await row(live)).estimate) === 35500, 'changing the base price never alters a placed order');

check((await err(A1, BLOCK, [A1, 'x'])).includes('CANNOT_BLOCK_ADMIN'), 'an admin cannot be blocked');
check((await err(A1, BLOCK, [C2, ' '])).includes('NOTE_REQUIRED'), 'blocking needs a reason');
await as(C2, `update profiles set city='khartoum', neighbourhood='Amarat', address_details='Street 61, blue gate' where id=$1`, [C2]);
await as(A1, BLOCK, [C2, 'Fake orders']);
check((await err(C2, SUBMIT, [T1, null, 'Hassan', meas, mine, 1, null])).includes('ACCOUNT_BLOCKED'),
  'a blocked customer cannot send orders');
check((await as(C2, `select reason from account_blocks`)).rows[0]?.reason === 'Fake orders'
      && (await as(C1, `select user_id from account_blocks`)).rows.length === 0,
  'a blocked person can read why; nobody else can');
await as(A1, UNBLOCK, [C2]);
check((await err(A1, UNBLOCK, [C2])).includes('NOT_BLOCKED')
      && !!(await as(C2, SUBMIT, [T1, null, 'Hassan', meas, mine, 1, null])).rows[0].id,
  'unblocked, they can order again');
const lifted = (await as(C2, `select reason, lifted_at from account_blocks`)).rows;
check(lifted.length === 1 && lifted[0].lifted_at !== null && lifted[0].reason === 'Fake orders',
  'an unblock keeps the row and stamps lifted_at, so the app hears it as an update (deletes reach every listener)');
await as(A1, BLOCK, [C2, 'Fake orders again']);
const again = (await as(C2, `select reason, lifted_at from account_blocks`)).rows[0];
check(again.lifted_at === null && again.reason === 'Fake orders again'
      && (await err(C2, SUBMIT, [T1, null, 'Hassan', meas, mine, 1, null])).includes('ACCOUNT_BLOCKED'),
  'blocking again reopens the same row with the new reason');
await as(A1, UNBLOCK, [C2]);
const published = (await admin(`select tablename from pg_publication_tables where pubname = 'supabase_realtime'`)).rows
  .map(r => r.tablename);
check(['orders', 'order_events', 'tailor_shops', 'account_blocks'].every(t => published.includes(t))
      && !published.includes('profiles') && !published.includes('admin_actions'),
  'blocks and shops are sent over Realtime (RLS limits each user to their own row); profiles and the admin log are not');

await as(A1, BLOCK, [T1, 'Took deposits and stopped answering']);
const b1 = await shop(T1);
check(b1.approved === false && b1.review_status === 'approved' && !(await listed()).includes(T1)
      && (await err(T1, ADV, [live, 'cutting', null, null, null])).includes('ACCOUNT_BLOCKED')
      && (await err(T1, `update tailor_shops set accepts_orders = false where tailor_id=$1`, [T1])).includes('ACCOUNT_BLOCKED'),
  "a blocked tailor's shop is hidden, and they cannot move orders or change the shop");
await as(A1, UNBLOCK, [T1]);
check((await shop(T1)).approved === true, 'unblocking lists their approved shop again');

check((await err(A1, CANCEL, [live, ''])).includes('NOTE_REQUIRED')
      && (await err(C1, CANCEL, [live, 'x'])).includes('NOT_AN_ADMIN'),
  'cancelling for support needs an admin and a reason');
await as(A1, CANCEL, [live, 'The tailor is closed this month']);
const ce = (await as(C1, `select to_status, kind, note, actor_id from order_events where order_id=$1 order by id desc limit 1`, [live])).rows[0];
check((await row(live)).status === 'cancelled' && ce.kind === 'admin' && ce.note.startsWith('The tailor') && ce.actor_id === A1,
  "an admin cancels an open order; both sides see support's step and reason");
check((await err(A1, CANCEL, [live, 'again'])).includes('TRANSITION_NOT_ALLOWED'), 'a closed order cannot be cancelled again');
check((await err(A1, `update orders set status = 'delivered' where id=$1`, [live])).includes('permission denied'),
  'admins also change orders only through the functions');

const st = (await as(A1, `select admin_stats() s`)).rows[0].s;
check(st.customers === 2 && st.tailors === 2 && st.listed === 2 && st.shops.approved === 2 && st.blocked === 0
      && st.per_day.length === 30 && st.per_day[29].orders >= 1 && st.orders.cancelled >= 1,
  'the overview counts people, shops and orders, and orders per day');
const found = (await as(A1, `select * from admin_users($1)`, ['babiker'])).rows;
const byPhone = (await as(A1, `select * from admin_users($1)`, ['0912 34'])).rows;
const tailors = (await as(A1, `select * from admin_users(null, 'tailor')`)).rows;
const admins = (await as(A1, `select * from admin_users(null, 'admin')`)).rows;
check(found.length === 1 && found[0].email === 'new@x.sd' && found[0].shop_name === 'Babiker & Sons'
      && byPhone.length === 1 && byPhone[0].id === C1 && tailors.length === 2 && Number(tailors[0].total_count) === 2
      && admins.length === 1 && admins[0].is_admin === true,
  'an admin finds people by name, shop, email or phone, with their email');

const log = (await as(A1, `select action from admin_actions order by id`)).rows.map(r => r.action);
check(['shop.rejected', 'shop.approved', 'shop.suspended', 'shop.reinstated', 'shop.edited', 'user.blocked',
       'user.unblocked', 'order.cancelled'].every(a => log.includes(a))
      && (await as(T1, `select id from admin_actions`)).rows.length === 0
      && (await as(T1, `select id from shop_events`)).rows.length === 0,
  'every admin step is logged, and only admins can read the logs');

console.log(results.join('\n'));
const fails = results.filter(r => r.startsWith('FAIL')).length;
console.log(`\n${results.length - fails}/${results.length} passed`);
process.exit(fails ? 1 : 0);
