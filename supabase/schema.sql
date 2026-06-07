-- =====================================================================
--  88-DAY CALENDAR — Supabase schema (v2: cards in DB + daily drip)
--  HOW TO USE:
--    1) Create a free project at https://supabase.com
--    2) SQL Editor -> New query -> paste this whole file -> RUN
--       (safe to re-run; it drops/recreates functions & policies)
--    3) Project Settings -> API: copy Project URL + "anon public" key
--       into ../supabase-config.js
--    4) Sign up once via calendar.html, then make yourself admin
--       (see the last line of this file).
--    5) Add your cards from admin.html.
--
--  HOW UNLOCKING WORKS (all enforced by SERVER time, uncheatable):
--    • 88 tiles always shown -> looks like a finished calendar.
--    • 1 new card "drips" open per day: day N opens on start_date+(N-1).
--    • A day only truly opens if a card with that position exists, so she
--      never lands on an empty card. (Keep filling AHEAD of the drip.)
--    • She may open at most `daily_limit` NEW cards per day (re-opening an
--      already-opened card is free) -> no speed-running.
--    • The last card (position = total) only opens on the very last day.
-- =====================================================================

-- ---------- app config (single row) ----------
create table if not exists public.app_config (
  id          int  primary key default 1,
  start_date  date not null default '2026-06-08',  -- day 1 opens here
  total       int  not null default 88,
  daily_limit int  not null default 4,              -- max NEW opens per day
  check (id = 1)
);
insert into public.app_config (id) values (1) on conflict (id) do nothing;
-- migrate older installs that had peek_ahead
alter table public.app_config add column if not exists daily_limit int not null default 4;

-- ---------- profiles ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  username   text unique,
  is_admin   boolean not null default false,
  created_at timestamptz not null default now(),
  last_seen  timestamptz
);

-- ---------- the cards (CONTENT lives here; admin-only) ----------
create table if not exists public.cards (
  id         bigint generated always as identity primary key,
  position   int unique not null,        -- 1..total ; the calendar slot
  category   text not null default 'note',
  reason     text,                        -- the cocky one-liner
  body       text,                        -- supports HTML / \n
  spotify    text,
  youtube    text,
  image      text,
  ask        boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------- which cards she opened ----------
create table if not exists public.opens (
  user_id   uuid not null references auth.users on delete cascade,
  day       int  not null,
  opened_at timestamptz not null default now(),
  primary key (user_id, day)
);

-- ---------- her replies to "question" cards ----------
create table if not exists public.replies (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users on delete cascade,
  day        int  not null,
  body       text not null,
  created_at timestamptz not null default now()
);

-- ---------- helpers ----------
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- contiguous filled count from position 1 (stops at the first gap)
create or replace function public.cards_filled()
returns int language sql security definer set search_path = public as $$
  with mx as (select coalesce(max(position),0) m from public.cards)
  select case
    when (select m from mx) = 0 then 0
    else coalesce(
      (select min(s.p) - 1
         from generate_series(1, (select m from mx)) s(p)
        where not exists (select 1 from public.cards c where c.position = s.p)),
      (select m from mx))
  end;
$$;

-- create a profile automatically on sign-up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id, nullif(new.raw_user_meta_data->>'username',''))
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- ---------- state for the grid (no content leaked) ----------
create or replace function public.calendar_state()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_cfg public.app_config%rowtype;
  v_date int; v_filled int; v_avail int; v_used int; v_opened jsonb;
begin
  if v_uid is null then return jsonb_build_object('error','auth'); end if;
  select * into v_cfg from public.app_config where id = 1;
  v_date := (current_date - v_cfg.start_date) + 1;
  if v_date < 0 then v_date := 0; end if;
  if v_date > v_cfg.total then v_date := v_cfg.total; end if;
  v_filled := public.cards_filled();
  v_avail := least(v_date, v_filled);
  if v_avail < 0 then v_avail := 0; end if;

  select coalesce(jsonb_agg(jsonb_build_object('d', o.day, 'c', c.category) order by o.day), '[]'::jsonb)
    into v_opened
    from public.opens o left join public.cards c on c.position = o.day
   where o.user_id = v_uid;

  select count(*) into v_used from public.opens
   where user_id = v_uid and opened_at::date = current_date;

  update public.profiles set last_seen = now() where id = v_uid;

  return jsonb_build_object(
    'available', v_avail, 'opened', v_opened, 'used_today', v_used,
    'total', v_cfg.total, 'daily_limit', v_cfg.daily_limit
  );
end;
$$;

-- ---------- the gate: open a day and return its content ----------
-- {allowed:bool, reason:'ok'|'auth'|'range'|'finale'|'locked'|'limit', card?:{...}}
create or replace function public.open_day(p_day int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_cfg public.app_config%rowtype;
  v_date int; v_filled int; v_avail int; v_used int; v_already boolean;
  v_card public.cards%rowtype;
begin
  if v_uid is null then return jsonb_build_object('allowed',false,'reason','auth'); end if;
  select * into v_cfg from public.app_config where id = 1;
  v_date := (current_date - v_cfg.start_date) + 1;
  if v_date < 0 then v_date := 0; end if;
  if v_date > v_cfg.total then v_date := v_cfg.total; end if;
  v_filled := public.cards_filled();
  v_avail := least(v_date, v_filled);

  if p_day < 1 or p_day > v_cfg.total then return jsonb_build_object('allowed',false,'reason','range'); end if;
  if p_day = v_cfg.total and v_date < v_cfg.total then return jsonb_build_object('allowed',false,'reason','finale'); end if;
  if p_day > v_avail then return jsonb_build_object('allowed',false,'reason','locked'); end if;

  select exists(select 1 from public.opens where user_id = v_uid and day = p_day) into v_already;
  if not v_already then
    select count(*) into v_used from public.opens
     where user_id = v_uid and opened_at::date = current_date;
    if v_used >= v_cfg.daily_limit then return jsonb_build_object('allowed',false,'reason','limit'); end if;
    insert into public.opens(user_id, day) values (v_uid, p_day) on conflict do nothing;
  end if;
  update public.profiles set last_seen = now() where id = v_uid;

  select * into v_card from public.cards where position = p_day;
  return jsonb_build_object('allowed',true,'reason','ok','card', jsonb_build_object(
    'category', coalesce(v_card.category,'note'), 'reason', v_card.reason, 'body', v_card.body,
    'spotify', v_card.spotify, 'youtube', v_card.youtube, 'image', v_card.image,
    'ask', coalesce(v_card.ask,false)));
end;
$$;

-- ---------- Row Level Security ----------
alter table public.app_config enable row level security;
alter table public.profiles   enable row level security;
alter table public.cards      enable row level security;
alter table public.opens      enable row level security;
alter table public.replies    enable row level security;

drop policy if exists cfg_read on public.app_config;
create policy cfg_read on public.app_config for select using (true);
drop policy if exists cfg_admin_write on public.app_config;
create policy cfg_admin_write on public.app_config for update using (public.is_admin()) with check (public.is_admin());

drop policy if exists prof_read on public.profiles;
create policy prof_read on public.profiles for select using (id = auth.uid() or public.is_admin());
drop policy if exists prof_update on public.profiles;
create policy prof_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- cards: ONLY admin can see/edit (content stays secret; served via open_day)
drop policy if exists cards_admin on public.cards;
create policy cards_admin on public.cards for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists opens_read on public.opens;
create policy opens_read on public.opens for select using (user_id = auth.uid() or public.is_admin());

drop policy if exists rep_read on public.replies;
create policy rep_read on public.replies for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists rep_insert on public.replies;
create policy rep_insert on public.replies for insert with check (user_id = auth.uid());

grant execute on function public.open_day(int)     to authenticated;
grant execute on function public.calendar_state()  to authenticated;
grant execute on function public.is_admin()        to authenticated;
grant execute on function public.cards_filled()    to authenticated;

-- =====================================================================
--  AFTER signing up once through calendar.html, run this ONCE with your
--  email to unlock the admin dashboard:
--
--    update public.profiles set is_admin = true
--    where id = (select id from auth.users where email = 'YOUR_EMAIL_HERE');
-- =====================================================================
