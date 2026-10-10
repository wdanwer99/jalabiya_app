-- =====================================================================
--  Jalabiya app — each shop's own cloth and thread colours
--  Run in Supabase → SQL Editor AFTER schema.sql and security_fixes.sql.
--  Safe to re-run. Run it again whenever you re-run schema.sql, because
--  schema.sql puts back the old submit_order / update_order.
--
--  * A tailor lists the cloth colours and embroidery-thread colours they
--    work with, each with a name, a colour and an extra price on top of
--    the shop's base price.
--  * A shop that has not listed any keeps the standard palette, at no
--    extra, so shops opened before this change keep working.
--  * An order may only use colours its shop offers. The order keeps its
--    own copy of the name, colour and price, so the tailor editing their
--    list later never changes an order already placed.
-- =====================================================================

-- ---------- columns ----------
alter table public.tailor_shops
  add column if not exists cloth_options  jsonb not null default '[]'::jsonb;
alter table public.tailor_shops
  add column if not exists thread_options jsonb not null default '[]'::jsonb;

-- ---------- the standard palette (same as JalabiyaDesign in the app) ----------
create or replace function public.default_options(p_kind text) returns jsonb
language sql immutable set search_path = public as $$
  select case p_kind
    when 'cloth' then '[
      {"id": "damuriya", "color": 16118246, "price": 0},
      {"id": "cream",    "color": 15589314, "price": 0},
      {"id": "nile",     "color": 12176857, "price": 0},
      {"id": "sand",     "color": 14468770, "price": 0},
      {"id": "ash",      "color": 12830667, "price": 0},
      {"id": "charcoal", "color": 4870232,  "price": 0}]'::jsonb
    when 'thread' then '[
      {"id": "gold",   "color": 13148746, "price": 0},
      {"id": "white",  "color": 16184298, "price": 0},
      {"id": "indigo", "color": 2834275,  "price": 0},
      {"id": "henna",  "color": 10242607, "price": 0}]'::jsonb
  end
$$;

-- ---------- what a tailor may store ----------
-- A list of at most 30 options, each {id, name, color, price}, ids unique.
create or replace function public.valid_options(o jsonb) returns boolean
language plpgsql immutable set search_path = public as $$
declare
  e jsonb;
  ids text[] := '{}';
begin
  if jsonb_typeof(o) is distinct from 'array' or jsonb_array_length(o) > 30 then
    return false;
  end if;
  for e in select value from jsonb_array_elements(o) loop
    if jsonb_typeof(e) is distinct from 'object' then return false; end if;
    if jsonb_typeof(e -> 'id') is distinct from 'string'
       or (e ->> 'id') !~ '^[a-z0-9_-]{1,40}$'
       or (e ->> 'id') = any (ids) then
      return false;
    end if;
    ids := ids || (e ->> 'id');
    if jsonb_typeof(e -> 'name') is distinct from 'string'
       or length(trim(e ->> 'name')) not between 1 and 40 then
      return false;
    end if;
    if not public.num_between(e, 'color', 0, 16777215)
       or (e ->> 'color')::numeric <> trunc((e ->> 'color')::numeric) then
      return false;
    end if;
    if not public.num_between(e, 'price', 0, 100000000) then return false; end if;
  end loop;
  return true;
end $$;

alter table public.tailor_shops drop constraint if exists shops_options_valid;
alter table public.tailor_shops add constraint shops_options_valid check (
  public.valid_options(cloth_options) and public.valid_options(thread_options));

-- ---------- what a customer may pick ----------
-- The option with this id from the shop's list (or the standard palette when
-- the shop has none of this kind), as {id, name, color, price}; null if the
-- shop does not offer it.
create or replace function public.shop_option(p_tailor uuid, p_kind text, p_id text)
returns jsonb
language sql stable security definer set search_path = public as $$
  with list as (
    select case p_kind when 'cloth' then s.cloth_options else s.thread_options end as opts
    from public.tailor_shops s
    where s.tailor_id = p_tailor and p_kind in ('cloth', 'thread')
  )
  select jsonb_build_object(
           'id',    e ->> 'id',
           'name',  e -> 'name',
           'color', (e ->> 'color')::int,
           'price', (e ->> 'price')::numeric)
  from list,
       jsonb_array_elements(case when jsonb_array_length(list.opts) = 0
                                 then public.default_options(p_kind)
                                 else list.opts end) e
  where e ->> 'id' = p_id
  limit 1
$$;

-- The colour lists are checked against the shop now, not a fixed palette.
create or replace function public.valid_design(d jsonb) returns boolean
language plpgsql immutable set search_path = public as $$
begin
  if jsonb_typeof(d) is distinct from 'object' then return false; end if;
  return coalesce(d ->> 'cut', '')    in ('slim', 'regular', 'full')
     and coalesce(d ->> 'collar', '') in ('round', 'band', 'shirt')
     and coalesce(d ->> 'emb', '')    in ('none', 'neck', 'full')
     and jsonb_typeof(d -> 'cloth')  = 'string'
     and jsonb_typeof(d -> 'thread') = 'string'
     and public.num_between(d, 'hem',  0,  30)
     and public.num_between(d, 'cuff', 22, 60);
end $$;

-- The design an order stores: the known keys, plus the shop's own copy of
-- the chosen cloth and thread. Raises if the shop does not offer them.
create or replace function public.order_design(p_tailor uuid, d jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cloth  jsonb;
  thread jsonb;
begin
  if not public.valid_design(d) then raise exception 'INVALID_DESIGN'; end if;
  cloth  := public.shop_option(p_tailor, 'cloth',  d ->> 'cloth');
  thread := public.shop_option(p_tailor, 'thread', d ->> 'thread');
  if cloth is null or thread is null then raise exception 'OPTION_UNAVAILABLE'; end if;
  return public.clean_design(d)
      || jsonb_build_object('cloth_option', cloth, 'thread_option', thread);
end $$;

revoke execute on function
  public.default_options(text),
  public.shop_option(uuid, text, text),
  public.order_design(uuid, jsonb)
  from public, anon, authenticated;
-- evaluated by the table check when a tailor saves their shop
grant execute on function public.valid_options(jsonb) to authenticated;
revoke execute on function public.valid_options(jsonb) from public, anon;

-- ---------- order actions, now checking the shop's colours ----------
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
  v_design jsonb;
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
  v_design := public.order_design(p_tailor, p_design);
  if coalesce(p_quantity, 0) not between 1 and 20 then raise exception 'INVALID_QUANTITY'; end if;
  if length(trim(coalesce(p_wearer, ''))) = 0 then raise exception 'INVALID_WEARER'; end if;

  insert into public.orders (customer_id, tailor_id, measurement_set_id, wearer_label,
                             measurements, design, delivery, quantity, customer_notes)
  values (uid, p_tailor, p_measurement_set, left(trim(p_wearer), 60),
          public.clean_measurements(p_measurements), v_design,
          public.delivery_snapshot(uid), p_quantity, nullif(trim(coalesce(p_notes, '')), ''))
  returning id into new_id;

  insert into public.order_events (order_id, actor_id, from_status, to_status, kind)
  values (new_id, uid, null, 'submitted', 'status');
  return new_id;
end $$;

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
  v_design jsonb;
begin
  if uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found or o.customer_id <> uid then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status not in ('submitted', 'changes_requested') then raise exception 'ORDER_LOCKED'; end if;
  if not public.profile_is_complete(uid) then raise exception 'PROFILE_INCOMPLETE'; end if;
  if not public.valid_measurements(p_measurements) then raise exception 'INVALID_MEASUREMENTS'; end if;
  v_design := public.order_design(o.tailor_id, p_design);
  if coalesce(p_quantity, 0) not between 1 and 20 then raise exception 'INVALID_QUANTITY'; end if;
  if length(trim(coalesce(p_wearer, ''))) = 0 then raise exception 'INVALID_WEARER'; end if;

  update public.orders set
    wearer_label   = left(trim(p_wearer), 60),
    measurements   = public.clean_measurements(p_measurements),
    design         = v_design,
    delivery       = public.delivery_snapshot(uid),
    quantity       = p_quantity,
    customer_notes = nullif(trim(coalesce(p_notes, '')), ''),
    status         = 'submitted'
  where id = p_order;

  insert into public.order_events (order_id, actor_id, from_status, to_status, kind)
  values (p_order, uid, o.status, 'submitted', 'edited');
end $$;
