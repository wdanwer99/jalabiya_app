-- =====================================================================
--  Jalabiya app — the admin dashboard (admin/index.html)
--  Run in Supabase → SQL Editor AFTER schema.sql, security_fixes.sql,
--  shop_options.sql and price_offers.sql. Safe to re-run. Run it again
--  whenever you re-run schema.sql, because schema.sql puts back the old
--  protect_shop().
--
--  * Admins are the accounts listed in app_admins. Add one by hand:
--      insert into public.app_admins (user_id)
--      select id from auth.users where email = 'you@example.com';
--  * Every shop has a review status. A new shop is 'pending'; an admin
--    approves or rejects it (with a reason the tailor sees), and can
--    suspend an approved shop and reinstate it later.
--  * `approved` stays the "customers can see it" flag that the rest of the
--    schema relies on. A trigger keeps it equal to: review is 'approved'
--    and the owner is not blocked. Setting `approved` by hand in the table
--    editor still works and updates the review status to match.
--  * An approved shop goes back to 'pending' (hidden) when its tailor
--    changes the shop name, city, neighbourhood or address. A rejected
--    shop goes back to 'pending' when its tailor saves it again.
--  * A blocked account cannot send, edit or move orders, or change its
--    shop, and a blocked tailor's shop is hidden from customers. The app
--    follows its own block row over Realtime, so it switches to the blocked
--    screen (and back) the moment an admin acts. An unblock keeps the row
--    and sets lifted_at: Realtime can filter and RLS-check updates, but not
--    deletes, which would go to every listener.
--  * Admins read everything through RLS. They change things only through
--    the admin_* functions below, which log each step in admin_actions.
-- =====================================================================

-- ---------- who is an admin ----------
create table if not exists public.app_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_admins a where a.user_id = auth.uid())
$$;

-- True only inside the admin_* functions below, after they checked the
-- caller (begin_admin sets it for the current transaction). The triggers
-- use it to let an admin change what the app itself may not.
create or replace function public.admin_acting() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(current_setting('jalabiya.admin_acting', true), '') = 'on' and public.is_admin()
$$;

create or replace function public.begin_admin() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'NOT_SIGNED_IN'; end if;
  if not public.is_admin() then raise exception 'NOT_AN_ADMIN'; end if;
  perform set_config('jalabiya.admin_acting', 'on', true);
end $$;

-- ---------- blocked accounts ----------
create table if not exists public.account_blocks (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  reason     text not null check (length(trim(reason)) between 1 and 1000),
  blocked_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

-- set when an admin lifts the block; the row stays (see the note at the top)
alter table public.account_blocks add column if not exists lifted_at timestamptz;
alter table public.account_blocks add column if not exists lifted_by uuid references auth.users (id) on delete set null;

create or replace function public.is_blocked(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.account_blocks b where b.user_id = uid and b.lifted_at is null)
$$;

-- ---------- each shop's review ----------
alter table public.tailor_shops add column if not exists review_status text not null default 'pending';
alter table public.tailor_shops add column if not exists review_note text;
alter table public.tailor_shops add column if not exists reviewed_at timestamptz;
alter table public.tailor_shops drop constraint if exists shops_review_known;
alter table public.tailor_shops add constraint shops_review_known check (
      review_status in ('pending', 'approved', 'rejected', 'suspended')
  and length(coalesce(review_note, '')) <= 1000);

-- shops approved before this file: they stay approved
update public.tailor_shops set review_status = 'approved', reviewed_at = coalesce(reviewed_at, updated_at)
 where approved and review_status = 'pending';

-- A shop's history: opened, sent back for review, every admin decision and edit.
create table if not exists public.shop_events (
  id          bigint generated always as identity primary key,
  tailor_id   uuid not null references public.tailor_shops (tailor_id) on delete cascade,
  actor_id    uuid references auth.users (id) on delete set null,
  kind        text not null,   -- opened | changed | resubmitted | review | edited
  from_status text,
  to_status   text,
  note        text,
  changes     jsonb,           -- {"field": {"from": …, "to": …}}
  created_at  timestamptz not null default now()
);
create index if not exists shop_events_shop_idx on public.shop_events (tailor_id, id);

-- The fields that differ between two versions of a shop.
create or replace function public.shop_changes(a public.tailor_shops, b public.tailor_shops) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_object_agg(k, jsonb_build_object('from', to_jsonb(a) -> k, 'to', to_jsonb(b) -> k)), '{}'::jsonb)
  from unnest(array['shop_name', 'bio', 'city', 'neighbourhood', 'address_details',
                    'base_price', 'lead_time_days', 'accepts_orders']) k
  where to_jsonb(a) -> k is distinct from to_jsonb(b) -> k
$$;

-- Replaces the version in schema.sql. The tailor (from the app) can never
-- set the review; their edits may send the shop back for review. You, in
-- the table editor, can still flip `approved`.
create or replace function public.protect_shop() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_app_request() and not public.admin_acting() then
    if public.is_blocked(auth.uid()) then raise exception 'ACCOUNT_BLOCKED'; end if;
    if tg_op = 'INSERT' then
      new.review_status := 'pending';
      new.review_note   := null;
      new.reviewed_at   := null;
    else
      new.tailor_id     := old.tailor_id;
      new.review_status := old.review_status;
      new.review_note   := old.review_note;
      new.reviewed_at   := old.reviewed_at;
      -- what customers use to find the shop changed: check it again
      if old.review_status = 'rejected'
         or (old.review_status = 'approved'
             and (new.shop_name, new.city, new.neighbourhood, new.address_details)
                 is distinct from (old.shop_name, old.city, old.neighbourhood, old.address_details)) then
        new.review_status := 'pending';
      end if;
    end if;
  elsif not public.is_app_request() then
    if (tg_op = 'INSERT' and new.approved and new.review_status = 'pending')
       or (tg_op = 'UPDATE' and new.approved is distinct from old.approved
           and new.review_status is not distinct from old.review_status) then
      new.review_status := case when new.approved then 'approved' else 'suspended' end;
      new.reviewed_at   := now();
    end if;
  end if;
  new.approved := new.review_status = 'approved' and not public.is_blocked(new.tailor_id);
  return new;
end $$;
drop trigger if exists shops_protect on public.tailor_shops;
create trigger shops_protect before insert or update on public.tailor_shops
  for each row execute function public.protect_shop();

create or replace function public.log_shop_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_kind text := 'review';
  v_changes jsonb;
begin
  if tg_op = 'INSERT' then
    insert into public.shop_events (tailor_id, actor_id, kind, to_status)
    values (new.tailor_id, auth.uid(), 'opened', new.review_status);
    return null;
  end if;
  if new.review_status is not distinct from old.review_status then return null; end if;
  if public.is_app_request() and not public.admin_acting() then
    v_kind := case when old.review_status = 'rejected' then 'resubmitted' else 'changed' end;
    v_changes := public.shop_changes(old, new);
  end if;
  insert into public.shop_events (tailor_id, actor_id, kind, from_status, to_status, note, changes)
  values (new.tailor_id, auth.uid(), v_kind, old.review_status, new.review_status,
          case when v_kind = 'review' then new.review_note end, v_changes);
  return null;
end $$;
drop trigger if exists shops_log on public.tailor_shops;
create trigger shops_log after insert or update on public.tailor_shops
  for each row execute function public.log_shop_event();

-- ---------- a blocked account cannot touch orders ----------
create or replace function public.stop_blocked() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_app_request() and not public.admin_acting() and public.is_blocked(auth.uid()) then
    raise exception 'ACCOUNT_BLOCKED';
  end if;
  return new;
end $$;
drop trigger if exists orders_blocked on public.orders;
create trigger orders_blocked before insert or update on public.orders
  for each row execute function public.stop_blocked();

-- ---------- what admins did ----------
create table if not exists public.admin_actions (
  id           bigint generated always as identity primary key,
  admin_id     uuid references auth.users (id) on delete set null,
  admin_email  text,
  action       text not null,  -- shop.approved | shop.rejected | shop.suspended | shop.reinstated | shop.edited
                               -- | user.blocked | user.unblocked | order.cancelled
  target_id    uuid not null,
  target_label text,           -- shop name, person or order at the time
  note         text,
  details      jsonb,
  created_at   timestamptz not null default now()
);
create index if not exists admin_actions_created_idx on public.admin_actions (created_at desc);
create index if not exists admin_actions_target_idx on public.admin_actions (target_id, created_at desc);

create or replace function public.log_admin(p_action text, p_target uuid, p_label text, p_note text,
                                            p_details jsonb default null) returns void
language sql security definer set search_path = public as $$
  insert into public.admin_actions (admin_id, admin_email, action, target_id, target_label, note, details)
  values (auth.uid(), (select u.email from auth.users u where u.id = auth.uid()),
          p_action, p_target, p_label, p_note, p_details)
$$;

-- ---------- admin actions (the only way an admin changes anything) ----------
-- pending → approved | rejected; approved → suspended; rejected | suspended → approved.
-- Rejecting and suspending need a reason: the tailor sees it in the app.
create or replace function public.admin_review_shop(p_tailor uuid, p_to text, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_shop public.tailor_shops%rowtype;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  perform public.begin_admin();
  select * into v_shop from public.tailor_shops where tailor_id = p_tailor for update;
  if not found then raise exception 'SHOP_NOT_FOUND'; end if;
  if not (   (p_to = 'approved'  and v_shop.review_status in ('pending', 'rejected', 'suspended'))
          or (p_to = 'rejected'  and v_shop.review_status = 'pending')
          or (p_to = 'suspended' and v_shop.review_status = 'approved')) then
    raise exception 'REVIEW_NOT_ALLOWED';
  end if;
  if p_to in ('rejected', 'suspended') and v_note is null then raise exception 'NOTE_REQUIRED'; end if;

  update public.tailor_shops
     set review_status = p_to, review_note = v_note, reviewed_at = now()
   where tailor_id = p_tailor;

  perform public.log_admin(
    'shop.' || case when p_to = 'approved' and v_shop.review_status = 'suspended' then 'reinstated' else p_to end,
    p_tailor, v_shop.shop_name, v_note);
end $$;

-- Fix a shop's details for its tailor. Only the keys present in p_shop change.
create or replace function public.admin_update_shop(p_tailor uuid, p_shop jsonb, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_old public.tailor_shops%rowtype;
  v_new public.tailor_shops%rowtype;
  v_changes jsonb;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  perform public.begin_admin();
  -- separate checks, in order: a number is only cast once it is known to be one
  if jsonb_typeof(p_shop) is distinct from 'object' then raise exception 'INVALID_SHOP'; end if;
  if p_shop ? 'base_price' and not public.num_between(p_shop, 'base_price', 0, 100000000) then
    raise exception 'INVALID_SHOP';
  end if;
  if p_shop ? 'lead_time_days' then
    if not public.num_between(p_shop, 'lead_time_days', 1, 120) then raise exception 'INVALID_SHOP'; end if;
    if (p_shop ->> 'lead_time_days')::numeric <> trunc((p_shop ->> 'lead_time_days')::numeric) then
      raise exception 'INVALID_SHOP';
    end if;
  end if;
  if p_shop ? 'accepts_orders' and jsonb_typeof(p_shop -> 'accepts_orders') is distinct from 'boolean' then
    raise exception 'INVALID_SHOP';
  end if;
  if exists (select 1 from unnest(array['shop_name', 'city', 'neighbourhood', 'address_details']) k
             where p_shop ? k and length(trim(coalesce(p_shop ->> k, ''))) = 0) then
    raise exception 'INVALID_SHOP';
  end if;
  select * into v_old from public.tailor_shops where tailor_id = p_tailor for update;
  if not found then raise exception 'SHOP_NOT_FOUND'; end if;

  update public.tailor_shops s set
    shop_name       = coalesce(trim(p_shop ->> 'shop_name'), s.shop_name),
    bio             = case when p_shop ? 'bio' then nullif(trim(coalesce(p_shop ->> 'bio', '')), '') else s.bio end,
    city            = coalesce(trim(p_shop ->> 'city'), s.city),
    neighbourhood   = coalesce(trim(p_shop ->> 'neighbourhood'), s.neighbourhood),
    address_details = coalesce(trim(p_shop ->> 'address_details'), s.address_details),
    base_price      = coalesce((p_shop ->> 'base_price')::numeric, s.base_price),
    lead_time_days  = coalesce((p_shop ->> 'lead_time_days')::numeric::int, s.lead_time_days),
    accepts_orders  = coalesce((p_shop ->> 'accepts_orders')::boolean, s.accepts_orders)
  where s.tailor_id = p_tailor
  returning * into v_new;

  v_changes := public.shop_changes(v_old, v_new);
  if v_changes = '{}'::jsonb then return; end if;
  insert into public.shop_events (tailor_id, actor_id, kind, note, changes)
  values (p_tailor, auth.uid(), 'edited', v_note, v_changes);
  perform public.log_admin('shop.edited', p_tailor, v_new.shop_name, v_note, v_changes);
end $$;

create or replace function public.admin_block_user(p_user uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_name text;
begin
  perform public.begin_admin();
  select full_name into v_name from public.profiles where id = p_user;
  if not found then raise exception 'USER_NOT_FOUND'; end if;
  if exists (select 1 from public.app_admins a where a.user_id = p_user) then raise exception 'CANNOT_BLOCK_ADMIN'; end if;
  if v_reason is null then raise exception 'NOTE_REQUIRED'; end if;

  insert into public.account_blocks (user_id, reason, blocked_by)
  values (p_user, v_reason, auth.uid())
  on conflict (user_id) do update
    set reason = excluded.reason, blocked_by = excluded.blocked_by, created_at = now(),
        lifted_at = null, lifted_by = null;
  -- the trigger works `approved` out again: a blocked tailor's shop is hidden
  update public.tailor_shops set updated_at = now() where tailor_id = p_user;
  perform public.log_admin('user.blocked', p_user, v_name, v_reason);
end $$;

create or replace function public.admin_unblock_user(p_user uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  perform public.begin_admin();
  select full_name into v_name from public.profiles where id = p_user;
  if not found then raise exception 'USER_NOT_FOUND'; end if;
  update public.account_blocks set lifted_at = now(), lifted_by = auth.uid()
   where user_id = p_user and lifted_at is null;
  if not found then raise exception 'NOT_BLOCKED'; end if;
  update public.tailor_shops set updated_at = now() where tailor_id = p_user;
  perform public.log_admin('user.unblocked', p_user, v_name, nullif(trim(coalesce(p_note, '')), ''));
end $$;

-- Cancel an order that is still open (stuck, disputed, a mistake). Both
-- sides see it in the order's history as a step by Jalabiya support.
create or replace function public.admin_cancel_order(p_order uuid, p_note text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  perform public.begin_admin();
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status in ('delivered', 'declined', 'cancelled') then raise exception 'TRANSITION_NOT_ALLOWED'; end if;
  if v_note is null then raise exception 'NOTE_REQUIRED'; end if;

  update public.orders set status = 'cancelled' where id = p_order;
  insert into public.order_events (order_id, actor_id, from_status, to_status, kind, note)
  values (p_order, (select p.id from public.profiles p where p.id = auth.uid()), o.status, 'cancelled', 'admin', v_note);
  perform public.log_admin('order.cancelled', p_order,
                           upper(left(p_order::text, 8)) || ' · ' || o.wearer_label, v_note,
                           jsonb_build_object('from', o.status));
end $$;

-- ---------- what the dashboard reads ----------
-- Everything on the overview page, in one call.
create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_AN_ADMIN'; end if;
  return jsonb_build_object(
    'customers', (select count(*) from public.profiles p
                  where p.role = 'customer' and not exists (select 1 from public.app_admins a where a.user_id = p.id)),
    'tailors', (select count(*) from public.profiles where role = 'tailor'),
    'blocked', (select count(*) from public.account_blocks where lifted_at is null),
    'new_users_7d', (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'shops', (select coalesce(jsonb_object_agg(review_status, n), '{}'::jsonb)
              from (select review_status, count(*) n from public.tailor_shops group by 1) x),
    'listed', (select count(*) from public.tailor_shops where approved),
    'taking_orders', (select count(*) from public.tailor_shops where approved and accepts_orders),
    'orders', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
               from (select status, count(*) n from public.orders group by 1) x),
    'orders_7d', (select count(*) from public.orders where created_at > now() - interval '7 days'),
    'delivered_value', (select coalesce(jsonb_object_agg(currency, total), '{}'::jsonb)
                        from (select currency, sum(price) total from public.orders
                              where status = 'delivered' and price is not null group by 1) x),
    'open_value', (select coalesce(jsonb_object_agg(currency, total), '{}'::jsonb)
                   from (select currency, sum(coalesce(price, estimate)) total from public.orders
                         where status in ('confirmed', 'cutting', 'sewing', 'ready') group by 1) x),
    'per_day', (select coalesce(jsonb_agg(jsonb_build_object('day', g.day, 'orders', coalesce(o.n, 0),
                                                             'users', coalesce(p.n, 0)) order by g.day), '[]'::jsonb)
                from (select generate_series(current_date - 29, current_date, interval '1 day')::date as day) g
                left join (select created_at::date d, count(*) n from public.orders
                           where created_at >= current_date - 29 group by 1) o on o.d = g.day
                left join (select created_at::date d, count(*) n from public.profiles
                           where created_at >= current_date - 29 group by 1) p on p.d = g.day)
  );
end $$;

-- People, with what only the server knows: their email and last sign-in.
-- p_role is 'customer', 'tailor' or 'admin'; p_user picks one person.
create or replace function public.admin_users(
  p_search text default null,
  p_role text default null,
  p_blocked boolean default null,
  p_user uuid default null,
  p_limit int default 50,
  p_offset int default 0
) returns table (
  id uuid, email text, role text, is_admin boolean, full_name text, phone text, whatsapp text,
  city text, neighbourhood text, address_details text, created_at timestamptz, last_sign_in_at timestamptz,
  blocked boolean, block_reason text, blocked_at timestamptz, shop_name text, review_status text,
  orders_count bigint, total_count bigint
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_q text := nullif(trim(coalesce(p_search, '')), '');
  v_digits text := nullif(regexp_replace(coalesce(p_search, ''), '[^0-9]', '', 'g'), '');
begin
  if not public.is_admin() then raise exception 'NOT_AN_ADMIN'; end if;
  return query
  select p.id, u.email::text, p.role::text, a.user_id is not null, p.full_name, p.phone, p.whatsapp,
         p.city, p.neighbourhood, p.address_details, p.created_at, u.last_sign_in_at,
         b.user_id is not null, b.reason, b.created_at, s.shop_name, s.review_status,
         (select count(*) from public.orders o where o.customer_id = p.id or o.tailor_id = p.id),
         count(*) over ()
  from public.profiles p
  left join auth.users u on u.id = p.id
  left join public.app_admins a on a.user_id = p.id
  left join public.account_blocks b on b.user_id = p.id and b.lifted_at is null
  left join public.tailor_shops s on s.tailor_id = p.id
  where (p_user is null or p.id = p_user)
    and (p_role is null
         or (p_role = 'admin' and a.user_id is not null)
         or (p_role <> 'admin' and p.role::text = p_role))
    and (p_blocked is null or (b.user_id is not null) = p_blocked)
    and (v_q is null
         or p.full_name ilike '%' || v_q || '%'
         or u.email ilike '%' || v_q || '%'
         or s.shop_name ilike '%' || v_q || '%'
         or (v_digits is not null and length(v_digits) >= 3
             and regexp_replace(p.phone, '[^0-9]', '', 'g') like '%' || v_digits || '%'))
  order by p.created_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200)
  offset greatest(coalesce(p_offset, 0), 0);
end $$;

-- ---------- row level security: admins read everything ----------
alter table public.app_admins     enable row level security;
alter table public.account_blocks enable row level security;
alter table public.shop_events    enable row level security;
alter table public.admin_actions  enable row level security;

drop policy if exists profiles_admin_read on public.profiles;
create policy profiles_admin_read on public.profiles for select to authenticated
  using ((select public.is_admin()));
drop policy if exists shops_admin_read on public.tailor_shops;
create policy shops_admin_read on public.tailor_shops for select to authenticated
  using ((select public.is_admin()));
drop policy if exists orders_admin_read on public.orders;
create policy orders_admin_read on public.orders for select to authenticated
  using ((select public.is_admin()));
drop policy if exists events_admin_read on public.order_events;
create policy events_admin_read on public.order_events for select to authenticated
  using ((select public.is_admin()));

drop policy if exists admins_read on public.app_admins;
create policy admins_read on public.app_admins for select to authenticated
  using (user_id = auth.uid() or (select public.is_admin()));
-- the app reads its own block to show why it is blocked
drop policy if exists blocks_read on public.account_blocks;
create policy blocks_read on public.account_blocks for select to authenticated
  using (user_id = auth.uid() or (select public.is_admin()));
drop policy if exists shop_events_read on public.shop_events;
create policy shop_events_read on public.shop_events for select to authenticated
  using ((select public.is_admin()));
drop policy if exists admin_actions_read on public.admin_actions;
create policy admin_actions_read on public.admin_actions for select to authenticated
  using ((select public.is_admin()));

-- ---------- privileges ----------
revoke all on public.app_admins, public.account_blocks, public.shop_events, public.admin_actions from anon;
revoke insert, update, delete on public.app_admins, public.account_blocks, public.shop_events,
                                 public.admin_actions from authenticated;
grant select on public.app_admins, public.account_blocks, public.shop_events, public.admin_actions to authenticated;

revoke execute on function
  public.is_admin(),
  public.admin_acting(),
  public.begin_admin(),
  public.is_blocked(uuid),
  public.shop_changes(public.tailor_shops, public.tailor_shops),
  public.protect_shop(),
  public.log_shop_event(),
  public.stop_blocked(),
  public.log_admin(text, uuid, text, text, jsonb),
  public.admin_review_shop(uuid, text, text),
  public.admin_update_shop(uuid, jsonb, text),
  public.admin_block_user(uuid, text),
  public.admin_unblock_user(uuid, text),
  public.admin_cancel_order(uuid, text),
  public.admin_stats(),
  public.admin_users(text, text, boolean, uuid, int, int)
  from public, anon;
revoke execute on function
  public.admin_acting(),
  public.begin_admin(),
  public.is_blocked(uuid),
  public.shop_changes(public.tailor_shops, public.tailor_shops),
  public.protect_shop(),
  public.log_shop_event(),
  public.stop_blocked(),
  public.log_admin(text, uuid, text, text, jsonb)
  from authenticated;
-- RLS policies call is_admin() as the signed-in user; the dashboard calls it
-- to check the account. The admin_* functions check is_admin() themselves.
grant execute on function
  public.is_admin(),
  public.admin_review_shop(uuid, text, text),
  public.admin_update_shop(uuid, jsonb, text),
  public.admin_block_user(uuid, text),
  public.admin_unblock_user(uuid, text),
  public.admin_cancel_order(uuid, text),
  public.admin_stats(),
  public.admin_users(text, text, boolean, uuid, int, int)
  to authenticated;

-- ---------- live updates ----------
-- the dashboard's review queue and blocks, a tailor's own shop status in the
-- app, and every account's own block (RLS: each user receives only their row)
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.tailor_shops;
    exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.account_blocks;
    exception when duplicate_object then null; end;
  end if;
end $$;
