-- =====================================================================
--  Jalabiya app — the customer approves a changed price or date
--  Run in Supabase → SQL Editor AFTER schema.sql, security_fixes.sql and
--  shop_options.sql. Safe to re-run. Run it again whenever you re-run
--  schema.sql, because schema.sql puts back the old advance_order.
--
--  * Every order keeps the estimate the customer saw when sending it:
--    (shop base price + cloth extra + thread extra) × quantity.
--  * When the tailor confirms with exactly that price, and a delivery date
--    within the shop's usual sewing time, the order is confirmed as before.
--  * Otherwise it becomes 'price_offered' and waits for the customer:
--    accepting confirms it, rejecting cancels it. The tailor can still
--    decline while waiting.
-- =====================================================================

-- ---------- the new status ----------
-- Added on its own; nothing below uses the value until it is called.
alter type public.order_status add value if not exists 'price_offered' after 'changes_requested';

-- ---------- the estimate the customer saw ----------
alter table public.orders add column if not exists estimate numeric(12,2);

create or replace function public.order_estimate(p_tailor uuid, d jsonb, q int) returns numeric
language sql stable security definer set search_path = public as $$
  select round((s.base_price
         + coalesce((d -> 'cloth_option' ->> 'price')::numeric, 0)
         + case when d ->> 'emb' = 'none' then 0
                else coalesce((d -> 'thread_option' ->> 'price')::numeric, 0) end) * q, 2)
  from public.tailor_shops s
  where s.tailor_id = p_tailor
$$;

-- Set when the order is sent and whenever the customer edits it, so it is
-- always the price the customer last saw.
create or replace function public.set_order_estimate() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.estimate := public.order_estimate(new.tailor_id, new.design, new.quantity);
  return new;
end $$;
drop trigger if exists orders_estimate on public.orders;
create trigger orders_estimate before insert or update of design, quantity on public.orders
  for each row execute function public.set_order_estimate();

-- orders sent before this change: their estimate from the shop's price now
update public.orders
   set estimate = public.order_estimate(tailor_id, design, quantity)
 where estimate is null;

revoke execute on function
  public.order_estimate(uuid, jsonb, int),
  public.set_order_estimate()
  from public, anon, authenticated;

-- ---------- every status change, with the offer step ----------
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
  target public.order_status := p_to;
  kind text := 'status';
  v_lead int;
begin
  if uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.tailor_id = uid then actor := 'tailor';
  elsif o.customer_id = uid then actor := 'customer';
  else raise exception 'ORDER_NOT_FOUND'; end if;

  if actor = 'tailor' then
    ok := (o.status = 'submitted' and p_to in ('confirmed', 'changes_requested', 'declined'))
       or (o.status = 'price_offered' and p_to = 'declined')
       or (o.status = 'confirmed' and p_to = 'cutting')
       or (o.status = 'cutting'   and p_to = 'sewing')
       or (o.status = 'sewing'    and p_to = 'ready')
       or (o.status = 'ready'     and p_to = 'delivered');
  else
    ok := (o.status in ('submitted', 'changes_requested', 'price_offered') and p_to = 'cancelled')
       or (o.status = 'price_offered' and p_to = 'confirmed');
  end if;
  if not ok then raise exception 'TRANSITION_NOT_ALLOWED'; end if;

  if actor = 'tailor' and p_to = 'confirmed' then
    if p_price is null or p_price <= 0 or p_due is null or p_due < current_date then
      raise exception 'PRICE_AND_DATE_REQUIRED';
    end if;
    select s.lead_time_days into v_lead from public.tailor_shops s where s.tailor_id = o.tailor_id;
    -- a different price, or a later date than the shop promises, needs the customer
    if o.estimate is null or round(p_price, 2) <> o.estimate
       or p_due > current_date + coalesce(v_lead, 0) then
      target := 'price_offered';
    end if;
  end if;
  if actor = 'tailor' and p_to in ('changes_requested', 'declined') and note is null then
    raise exception 'NOTE_REQUIRED';
  end if;
  if actor = 'customer' and o.status = 'price_offered' then
    kind := case when p_to = 'confirmed' then 'accepted' else 'rejected' end;
  end if;

  update public.orders set
    status      = target,
    price       = case when actor = 'tailor' and p_to = 'confirmed' then p_price else price end,
    due_date    = case when actor = 'tailor' and p_to = 'confirmed' then p_due else due_date end,
    tailor_note = case when actor = 'tailor' and note is not null then note else tailor_note end
  where id = p_order;

  insert into public.order_events (order_id, actor_id, from_status, to_status, kind, note)
  values (p_order, uid, o.status, target, kind, note);
end $$;
