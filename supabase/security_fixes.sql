-- =====================================================================
--  Jalabiya app — security fixes (see SECURITY_REPORT.md)
--  Run in Supabase → SQL Editor AFTER schema.sql. Safe to re-run.
--  Every fix below was checked against schema.sql on real Postgres.
-- =====================================================================

-- ---------------------------------------------------------------------
-- [H-1] Internal SECURITY DEFINER helpers were reachable over the REST API
--       (POST /rest/v1/rpc/<name>) by anyone holding the public anon key.
--       delivery_snapshot(uid) returned any user's name, phone and home
--       address without signing in.
-- ---------------------------------------------------------------------
revoke execute on function
  public.delivery_snapshot(uuid),
  public.profile_is_complete(uuid),
  public.handle_new_user(),
  public.my_role(),
  public.is_my_customer(uuid),
  public.is_my_tailor(uuid),
  public.can_see_order(uuid)
  from public, anon;

-- Only ever called from inside other SECURITY DEFINER functions (which run
-- as their owner) or as a trigger, so no app user needs to call them.
revoke execute on function
  public.delivery_snapshot(uuid),
  public.profile_is_complete(uuid),
  public.handle_new_user()
  from authenticated;

-- RLS policies call these as the signed-in user, so they stay granted. They
-- only answer questions about the caller's own orders.
grant execute on function
  public.my_role(),
  public.is_my_customer(uuid),
  public.is_my_tailor(uuid),
  public.can_see_order(uuid)
  to authenticated;

-- Functions you add later start private instead of public.
alter default privileges in schema public revoke execute on functions from public, anon;

-- ---------------------------------------------------------------------
-- [H-2] Every signed-in user could read the full profile (phone, WhatsApp,
--       home address) of every account with role 'tailor', including ones
--       that signed up minutes ago and were never approved.
-- [M-1] A tailor kept reading a customer's live profile forever after one
--       order, even one they declined, including address changes made later.
--       (The tailor screen already falls back to the address frozen in the
--       order, so narrowing this does not break the app.)
-- ---------------------------------------------------------------------
create or replace function public.is_listed_tailor(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.tailor_shops s where s.tailor_id = pid and s.approved)
$$;
revoke execute on function public.is_listed_tailor(uuid) from public, anon;
grant execute on function public.is_listed_tailor(uuid) to authenticated;

-- Live access lasts while the order is open, and 30 days after delivery.
create or replace function public.is_my_customer(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.orders o
    where o.customer_id = pid and o.tailor_id = auth.uid()
      and o.status not in ('declined', 'cancelled')
      and (o.status <> 'delivered' or o.updated_at > now() - interval '30 days'))
$$;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid()
         or public.is_listed_tailor(id)   -- approved tailors only
         or public.is_my_tailor(id)       -- the tailor of one of my orders
         or public.is_my_customer(id));   -- a customer with an open order with me

-- ---------------------------------------------------------------------
-- [M-2] No length limits on free text: a single request could store
--       megabytes in a name, bio or order note (storage, bandwidth and UI
--       abuse). Limits sit well above what the app's forms allow.
--       NOT VALID: existing rows are left alone, every new write is checked.
-- ---------------------------------------------------------------------
alter table public.profiles drop constraint if exists profiles_text_len;
alter table public.profiles add constraint profiles_text_len check (
      length(full_name) <= 100
  and length(phone) <= 30
  and length(coalesce(whatsapp, '')) <= 30
  and length(coalesce(city, '')) <= 100
  and length(coalesce(neighbourhood, '')) <= 100
  and length(coalesce(address_details, '')) <= 500) not valid;

alter table public.tailor_shops drop constraint if exists shops_text_len;
alter table public.tailor_shops add constraint shops_text_len check (
      length(shop_name) between 1 and 100
  and length(coalesce(bio, '')) <= 500
  and length(city) <= 100
  and length(neighbourhood) <= 100
  and length(address_details) <= 500
  and currency ~ '^[A-Z]{3}$'
  and base_price <= 100000000) not valid;

alter table public.orders drop constraint if exists orders_text_len;
alter table public.orders add constraint orders_text_len check (
      length(coalesce(customer_notes, '')) <= 1000
  and length(coalesce(tailor_note, '')) <= 1000
  and (price is null or price <= 1000000000)) not valid;

alter table public.order_events drop constraint if exists events_text_len;
alter table public.order_events add constraint events_text_len check (
  length(coalesce(note, '')) <= 1000) not valid;

-- [L-1] relation was free text
alter table public.measurement_sets drop constraint if exists sets_relation_known;
alter table public.measurement_sets add constraint sets_relation_known check (
  relation in ('self', 'son', 'father', 'brother', 'other')) not valid;

-- ---------------------------------------------------------------------
-- [M-3] No rate limits: one account could send hundreds of orders a second
--       to a tailor, or create unlimited saved people.
-- ---------------------------------------------------------------------
create or replace function public.limit_orders() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_app_request() then
    if (select count(*) from public.orders
        where customer_id = new.customer_id and created_at > now() - interval '1 hour') >= 10 then
      raise exception 'TOO_MANY_ORDERS';
    end if;
    if (select count(*) from public.orders
        where customer_id = new.customer_id and tailor_id = new.tailor_id
          and status in ('submitted', 'changes_requested')) >= 5 then
      raise exception 'TOO_MANY_ORDERS';
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.limit_orders() from public, anon, authenticated;
drop trigger if exists orders_limit on public.orders;
create trigger orders_limit before insert on public.orders
  for each row execute function public.limit_orders();

create or replace function public.limit_sets() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_app_request()
     and (select count(*) from public.measurement_sets where owner_id = new.owner_id) >= 30 then
    raise exception 'TOO_MANY_PEOPLE';
  end if;
  return new;
end $$;
revoke execute on function public.limit_sets() from public, anon, authenticated;
drop trigger if exists sets_limit on public.measurement_sets;
create trigger sets_limit before insert on public.measurement_sets
  for each row execute function public.limit_sets();

-- ---------------------------------------------------------------------
-- [L-2] Pin search_path on the remaining functions (Supabase's linter flags
--       "function_search_path_mutable"; stops a lookalike object shadowing them).
-- ---------------------------------------------------------------------
alter function public.touch_updated_at() set search_path = public;
alter function public.is_app_request() set search_path = public;
alter function public.protect_profile() set search_path = public;
alter function public.protect_shop() set search_path = public;
alter function public.num_between(jsonb, text, numeric, numeric) set search_path = public;
alter function public.valid_measurements(jsonb) set search_path = public;
alter function public.valid_design(jsonb) set search_path = public;
alter function public.clean_measurements(jsonb) set search_path = public;
alter function public.clean_design(jsonb) set search_path = public;
