-- =====================================================================
--  Jalabiya app — Supabase schema
--  Run once in Supabase → SQL Editor. Safe to re-run.
--
--  Design rules:
--   * Customers and tailors read data through Row Level Security.
--   * Nobody writes to `orders` directly. Every change goes through the
--     functions at the bottom, which check who is acting, validate the
--     sizes, and log each step in `order_events`.
--   * An order freezes a copy of the measurements, design and delivery
--     address. Editing a saved person later never changes an order the
--     tailor has already confirmed.
-- =====================================================================

-- ---------- types ----------
do $$ begin
  create type public.user_role as enum ('customer', 'tailor');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.order_status as enum (
    'submitted',          -- customer sent it, tailor has not answered
    'changes_requested',  -- tailor asked the customer to fix something
    'confirmed',          -- tailor accepted, set price and due date
    'cutting',
    'sewing',
    'ready',
    'delivered',
    'declined',           -- tailor turned it down
    'cancelled'           -- customer withdrew it
  );
exception when duplicate_object then null; end $$;

-- ---------- tables ----------
create table if not exists public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  role            public.user_role not null default 'customer',
  full_name       text not null default '',
  phone           text not null default '',
  whatsapp        text,
  city            text,
  neighbourhood   text,
  address_details text,          -- landmarks, house, street: how a driver finds you
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table if not exists public.tailor_shops (
  tailor_id       uuid primary key,
  shop_name       text not null,
  bio             text,
  city            text not null,
  neighbourhood   text not null,
  address_details text not null,
  base_price      numeric(12,2) not null check (base_price >= 0),
  currency        text not null default 'SDG',
  lead_time_days  int not null check (lead_time_days between 1 and 120),
  accepts_orders  boolean not null default true,
  approved        boolean not null default false,  -- set by you in the dashboard
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint tailor_shops_tailor_id_fkey
    foreign key (tailor_id) references public.profiles (id) on delete cascade
);

create table if not exists public.measurement_sets (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  label       text not null check (length(trim(label)) between 1 and 60),
  relation    text not null default 'self',  -- self, son, father, brother, other
  height      numeric(5,1) not null check (height   between 145 and 205),
  chest       numeric(5,1) not null check (chest    between 76  and 150),
  waist       numeric(5,1) not null check (waist    between 64  and 150),
  hip         numeric(5,1) not null check (hip      between 76  and 150),
  shoulder    numeric(5,1) not null check (shoulder between 36  and 58),
  arm         numeric(5,1) not null check (arm      between 48  and 74),
  neck        numeric(5,1) not null check (neck     between 32  and 50),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists measurement_sets_owner_idx on public.measurement_sets (owner_id);

create table if not exists public.orders (
  id                  uuid primary key default gen_random_uuid(),
  customer_id         uuid not null,
  tailor_id           uuid not null,
  measurement_set_id  uuid references public.measurement_sets (id) on delete set null,
  wearer_label        text not null,
  measurements        jsonb not null,   -- frozen copy: height, chest, waist, hip, shoulder, arm, neck (cm)
  design              jsonb not null,   -- cut, hem, cuff, collar, emb, cloth, thread
  delivery            jsonb not null,   -- frozen copy of name, phone, city, neighbourhood, address
  quantity            int not null default 1 check (quantity between 1 and 20),
  customer_notes      text,
  status              public.order_status not null default 'submitted',
  price               numeric(12,2) check (price is null or price > 0),
  currency            text not null default 'SDG',
  due_date            date,
  tailor_note         text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint orders_customer_id_fkey
    foreign key (customer_id) references public.profiles (id) on delete cascade,
  constraint orders_tailor_id_fkey
    foreign key (tailor_id) references public.tailor_shops (tailor_id) on delete restrict
);
create index if not exists orders_customer_idx on public.orders (customer_id, created_at desc);
create index if not exists orders_tailor_idx   on public.orders (tailor_id, created_at desc);

create table if not exists public.order_events (
  id          bigint generated always as identity primary key,
  order_id    uuid not null references public.orders (id) on delete cascade,
  actor_id    uuid references public.profiles (id) on delete set null,
  from_status public.order_status,
  to_status   public.order_status not null,
  kind        text not null default 'status',   -- status | edited
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists order_events_order_idx on public.order_events (order_id, created_at);

-- ---------- updated_at ----------
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();
drop trigger if exists shops_touch on public.tailor_shops;
create trigger shops_touch before update on public.tailor_shops
  for each row execute function public.touch_updated_at();
drop trigger if exists sets_touch on public.measurement_sets;
create trigger sets_touch before update on public.measurement_sets
  for each row execute function public.touch_updated_at();
drop trigger if exists orders_touch on public.orders;
create trigger orders_touch before update on public.orders
  for each row execute function public.touch_updated_at();

-- ---------- helpers ----------
-- True when the request comes from the app (a signed-in or anonymous user),
-- false when you are working in the dashboard / SQL editor.
create or replace function public.is_app_request() returns boolean
language sql stable as $$
  select coalesce(auth.role(), '') in ('authenticated', 'anon')
$$;

create or replace function public.my_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.profile_is_complete(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid
      and length(trim(p.full_name)) >= 3
      and length(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')) between 9 and 15
      and length(trim(coalesce(p.city, ''))) > 0
      and length(trim(coalesce(p.neighbourhood, ''))) > 0
      and length(trim(coalesce(p.address_details, ''))) >= 5
      and (p.role = 'customer'
           or exists (select 1 from public.tailor_shops s where s.tailor_id = p.id))
  )
$$;

create or replace function public.is_my_customer(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.orders o
                 where o.customer_id = pid and o.tailor_id = auth.uid())
$$;

create or replace function public.is_my_tailor(tid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.orders o
                 where o.tailor_id = tid and o.customer_id = auth.uid())
$$;

create or replace function public.can_see_order(oid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.orders o
                 where o.id = oid and auth.uid() in (o.customer_id, o.tailor_id))
$$;

-- ---------- guards ----------
-- A role is chosen once at sign-up and never changes from the app.
create or replace function public.protect_profile() returns trigger
language plpgsql as $$
begin
  if public.is_app_request() then
    new.id   := old.id;
    new.role := old.role;
  end if;
  return new;
end $$;
drop trigger if exists profiles_protect on public.profiles;
create trigger profiles_protect before update on public.profiles
  for each row execute function public.protect_profile();

-- Only you (dashboard) can approve a shop. A tailor editing their shop keeps
-- whatever approval it already had; a brand-new shop always starts unapproved.
create or replace function public.protect_shop() returns trigger
language plpgsql as $$
begin
  if public.is_app_request() then
    if tg_op = 'INSERT' then
      new.approved := false;
    else
      new.approved  := old.approved;
      new.tailor_id := old.tailor_id;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists shops_protect on public.tailor_shops;
create trigger shops_protect before insert or update on public.tailor_shops
  for each row execute function public.protect_shop();

-- Create the profile row the moment someone signs up.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    case when new.raw_user_meta_data ->> 'role' = 'tailor'
         then 'tailor'::public.user_role else 'customer'::public.user_role end,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'phone', '')
  )
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- validation ----------
create or replace function public.num_between(j jsonb, k text, lo numeric, hi numeric)
returns boolean language plpgsql immutable as $$
begin
  if jsonb_typeof(j -> k) is distinct from 'number' then return false; end if;
  return (j ->> k)::numeric between lo and hi;
end $$;

create or replace function public.valid_measurements(m jsonb) returns boolean
language plpgsql immutable as $$
begin
  if jsonb_typeof(m) is distinct from 'object' then return false; end if;
  return public.num_between(m, 'height',   145, 205)
     and public.num_between(m, 'chest',    76,  150)
     and public.num_between(m, 'waist',    64,  150)
     and public.num_between(m, 'hip',      76,  150)
     and public.num_between(m, 'shoulder', 36,  58)
     and public.num_between(m, 'arm',      48,  74)
     and public.num_between(m, 'neck',     32,  50);
end $$;

create or replace function public.valid_design(d jsonb) returns boolean
language plpgsql immutable as $$
begin
  if jsonb_typeof(d) is distinct from 'object' then return false; end if;
  return coalesce(d ->> 'cut', '')    in ('slim', 'regular', 'full')
     and coalesce(d ->> 'collar', '') in ('round', 'band', 'shirt')
     and coalesce(d ->> 'emb', '')    in ('none', 'neck', 'full')
     and coalesce(d ->> 'cloth', '')  in ('damuriya', 'cream', 'nile', 'sand', 'ash', 'charcoal')
     and coalesce(d ->> 'thread', '') in ('gold', 'white', 'indigo', 'henna')
     and public.num_between(d, 'hem',  0,  30)
     and public.num_between(d, 'cuff', 22, 60);
end $$;

-- Only the keys we know, so nothing else rides along inside an order.
create or replace function public.clean_measurements(m jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'height', (m->>'height')::numeric, 'chest', (m->>'chest')::numeric,
    'waist',  (m->>'waist')::numeric,  'hip',   (m->>'hip')::numeric,
    'shoulder', (m->>'shoulder')::numeric, 'arm', (m->>'arm')::numeric,
    'neck',   (m->>'neck')::numeric)
$$;

create or replace function public.clean_design(d jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'cut', d->>'cut', 'collar', d->>'collar', 'emb', d->>'emb',
    'cloth', d->>'cloth', 'thread', d->>'thread',
    'hem', (d->>'hem')::numeric, 'cuff', (d->>'cuff')::numeric)
$$;

create or replace function public.delivery_snapshot(uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'name', p.full_name, 'phone', p.phone, 'whatsapp', p.whatsapp,
    'city', p.city, 'neighbourhood', p.neighbourhood,
    'address_details', p.address_details)
  from public.profiles p where p.id = uid
$$;

-- ---------- order actions (the only way to write an order) ----------
create or replace function public.submit_order(
  p_tailor uuid,
  p_measurement_set uuid,
  p_wearer text,
  p_measurements jsonb,
  p_design jsonb,
  p_quantity int default 1,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  new_id uuid;
begin
  if uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  if public.my_role() is distinct from 'customer' then raise exception 'NOT_A_CUSTOMER'; end if;
  if not public.profile_is_complete(uid) then raise exception 'PROFILE_INCOMPLETE'; end if;
  if not exists (select 1 from public.tailor_shops s
                 where s.tailor_id = p_tailor and s.approved and s.accepts_orders) then
    raise exception 'TAILOR_UNAVAILABLE';
  end if;
  if p_measurement_set is not null and not exists (
       select 1 from public.measurement_sets m
       where m.id = p_measurement_set and m.owner_id = uid) then
    raise exception 'INVALID_MEASUREMENT_SET';
  end if;
  if not public.valid_measurements(p_measurements) then raise exception 'INVALID_MEASUREMENTS'; end if;
  if not public.valid_design(p_design) then raise exception 'INVALID_DESIGN'; end if;
  if coalesce(p_quantity, 0) not between 1 and 20 then raise exception 'INVALID_QUANTITY'; end if;
  if length(trim(coalesce(p_wearer, ''))) = 0 then raise exception 'INVALID_WEARER'; end if;

  insert into public.orders (customer_id, tailor_id, measurement_set_id, wearer_label,
                             measurements, design, delivery, quantity, customer_notes)
  values (uid, p_tailor, p_measurement_set, left(trim(p_wearer), 60),
          public.clean_measurements(p_measurements), public.clean_design(p_design),
          public.delivery_snapshot(uid), p_quantity, nullif(trim(coalesce(p_notes, '')), ''))
  returning id into new_id;

  insert into public.order_events (order_id, actor_id, from_status, to_status, kind)
  values (new_id, uid, null, 'submitted', 'status');
  return new_id;
end $$;

-- Customer edits an order the tailor has not confirmed yet. It goes back to
-- the tailor as 'submitted' so they review the new sizes.
create or replace function public.update_order(
  p_order uuid,
  p_wearer text,
  p_measurements jsonb,
  p_design jsonb,
  p_quantity int default 1,
  p_notes text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  o public.orders%rowtype;
begin
  if uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found or o.customer_id <> uid then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status not in ('submitted', 'changes_requested') then raise exception 'ORDER_LOCKED'; end if;
  if not public.profile_is_complete(uid) then raise exception 'PROFILE_INCOMPLETE'; end if;
  if not public.valid_measurements(p_measurements) then raise exception 'INVALID_MEASUREMENTS'; end if;
  if not public.valid_design(p_design) then raise exception 'INVALID_DESIGN'; end if;
  if coalesce(p_quantity, 0) not between 1 and 20 then raise exception 'INVALID_QUANTITY'; end if;
  if length(trim(coalesce(p_wearer, ''))) = 0 then raise exception 'INVALID_WEARER'; end if;

  update public.orders set
    wearer_label   = left(trim(p_wearer), 60),
    measurements   = public.clean_measurements(p_measurements),
    design         = public.clean_design(p_design),
    delivery       = public.delivery_snapshot(uid),
    quantity       = p_quantity,
    customer_notes = nullif(trim(coalesce(p_notes, '')), ''),
    status         = 'submitted'
  where id = p_order;

  insert into public.order_events (order_id, actor_id, from_status, to_status, kind)
  values (p_order, uid, o.status, 'submitted', 'edited');
end $$;

-- Every status change, for both sides, with the rules in one place.
create or replace function public.advance_order(
  p_order uuid,
  p_to public.order_status,
  p_note text default null,
  p_price numeric default null,
  p_due date default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  o public.orders%rowtype;
  actor text;
  note text := nullif(trim(coalesce(p_note, '')), '');
  ok boolean := false;
begin
  if uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.tailor_id = uid then actor := 'tailor';
  elsif o.customer_id = uid then actor := 'customer';
  else raise exception 'ORDER_NOT_FOUND'; end if;

  if actor = 'tailor' then
    ok := (o.status = 'submitted' and p_to in ('confirmed', 'changes_requested', 'declined'))
       or (o.status = 'confirmed' and p_to = 'cutting')
       or (o.status = 'cutting'   and p_to = 'sewing')
       or (o.status = 'sewing'    and p_to = 'ready')
       or (o.status = 'ready'     and p_to = 'delivered');
  else
    ok := o.status in ('submitted', 'changes_requested') and p_to = 'cancelled';
  end if;
  if not ok then raise exception 'TRANSITION_NOT_ALLOWED'; end if;

  if p_to = 'confirmed' and (p_price is null or p_price <= 0 or p_due is null or p_due < current_date) then
    raise exception 'PRICE_AND_DATE_REQUIRED';
  end if;
  if p_to in ('changes_requested', 'declined') and note is null then
    raise exception 'NOTE_REQUIRED';
  end if;

  update public.orders set
    status      = p_to,
    price       = case when p_to = 'confirmed' then p_price else price end,
    due_date    = case when p_to = 'confirmed' then p_due else due_date end,
    tailor_note = case when actor = 'tailor' and note is not null then note else tailor_note end
  where id = p_order;

  insert into public.order_events (order_id, actor_id, from_status, to_status, kind, note)
  values (p_order, uid, o.status, p_to, 'status', note);
end $$;

-- ---------- row level security ----------
alter table public.profiles         enable row level security;
alter table public.tailor_shops     enable row level security;
alter table public.measurement_sets enable row level security;
alter table public.orders           enable row level security;
alter table public.order_events     enable row level security;

drop policy if exists profiles_read   on public.profiles;
drop policy if exists profiles_insert on public.profiles;
drop policy if exists profiles_update on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or role = 'tailor' or public.is_my_customer(id));
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists shops_read   on public.tailor_shops;
drop policy if exists shops_insert on public.tailor_shops;
drop policy if exists shops_update on public.tailor_shops;
create policy shops_read on public.tailor_shops for select to authenticated
  using (approved or tailor_id = auth.uid() or public.is_my_tailor(tailor_id));
create policy shops_insert on public.tailor_shops for insert to authenticated
  with check (tailor_id = auth.uid() and public.my_role() = 'tailor');
create policy shops_update on public.tailor_shops for update to authenticated
  using (tailor_id = auth.uid()) with check (tailor_id = auth.uid());

drop policy if exists sets_owner on public.measurement_sets;
create policy sets_owner on public.measurement_sets for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select to authenticated
  using (auth.uid() in (customer_id, tailor_id));

drop policy if exists events_read on public.order_events;
create policy events_read on public.order_events for select to authenticated
  using (public.can_see_order(order_id));

-- ---------- privileges ----------
revoke all on public.profiles, public.tailor_shops, public.measurement_sets,
              public.orders, public.order_events from anon;
grant select, insert, update on public.profiles     to authenticated;
grant select, insert, update on public.tailor_shops to authenticated;
grant select, insert, update, delete on public.measurement_sets to authenticated;
revoke insert, update, delete on public.orders, public.order_events from authenticated;
grant select on public.orders, public.order_events to authenticated;

revoke execute on function public.submit_order(uuid, uuid, text, jsonb, jsonb, int, text) from public, anon;
revoke execute on function public.update_order(uuid, text, jsonb, jsonb, int, text) from public, anon;
revoke execute on function public.advance_order(uuid, public.order_status, text, numeric, date) from public, anon;
grant execute on function public.submit_order(uuid, uuid, text, jsonb, jsonb, int, text) to authenticated;
grant execute on function public.update_order(uuid, text, jsonb, jsonb, int, text) to authenticated;
grant execute on function public.advance_order(uuid, public.order_status, text, numeric, date) to authenticated;

-- ---------- live updates ----------
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.orders;
    exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.order_events;
    exception when duplicate_object then null; end;
  end if;
end $$;

-- ---------- approving a tailor (run by hand, in the dashboard) ----------
-- update public.tailor_shops set approved = true where shop_name = 'Shop name here';
