-- =====================================================================
--  88-DAY CALENDAR — Supabase schema
--  HOW TO USE:
--    1) Create a free project at https://supabase.com
--    2) Open the project -> SQL Editor -> New query
--    3) Paste this whole file and click RUN
--    4) Project Settings -> API: copy the Project URL + the "anon public"
--       key into ../supabase-config.js
--    5) Create your own account through the calendar page, then make
--       yourself admin (see the last line of this file).
-- =====================================================================

-- ---------- app config (single row) ----------
create table if not exists public.app_config (
  id          int primary key default 1,
  start_date  date    not null default '2026-06-08',  -- DAY 1 unlocks here
  total       int     not null default 88,
  peek_ahead  int     not null default 3,             -- cards she may open ahead of "today"
  check (id = 1)
);
insert into public.app_config (id) values (1) on conflict (id) do nothing;

-- ---------- profiles ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  username    text unique,
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz
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

-- ---------- helper: am I an admin? (definer avoids RLS recursion) ----------
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- ---------- create a profile automatically on sign-up ----------
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
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- the gate: open a day (server-time enforced) ----------
-- Returns jsonb {allowed:bool, reason:text, current:int}
--   reason: 'ok' | 'auth' | 'range' | 'finale' | 'cheat'
create or replace function public.open_day(p_day int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_cfg public.app_config%rowtype;
  v_current int;
  v_max int;
begin
  if v_uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'auth');
  end if;

  select * into v_cfg from public.app_config where id = 1;

  -- days unlocked purely by SERVER date (clock-cheating impossible)
  v_current := (current_date - v_cfg.start_date) + 1;
  if v_current < 0 then v_current := 0; end if;
  if v_current > v_cfg.total then v_current := v_cfg.total; end if;

  if p_day < 1 or p_day > v_cfg.total then
    return jsonb_build_object('allowed', false, 'reason', 'range', 'current', v_current);
  end if;

  -- the finale is sacred: only on/after its real day
  if p_day = v_cfg.total and v_current < v_cfg.total then
    return jsonb_build_object('allowed', false, 'reason', 'finale', 'current', v_current);
  end if;

  -- she may sneak up to peek_ahead cards beyond today's unlocked day
  v_max := greatest(v_current, 0) + v_cfg.peek_ahead;
  if p_day > v_max then
    return jsonb_build_object('allowed', false, 'reason', 'cheat', 'current', v_current);
  end if;

  insert into public.opens (user_id, day) values (v_uid, p_day)
    on conflict (user_id, day) do nothing;
  update public.profiles set last_seen = now() where id = v_uid;

  return jsonb_build_object('allowed', true, 'reason', 'ok', 'current', v_current);
end;
$$;

-- ---------- Row Level Security ----------
alter table public.app_config enable row level security;
alter table public.profiles   enable row level security;
alter table public.opens      enable row level security;
alter table public.replies    enable row level security;

-- everyone can read config (needed for the countdown / locked dates)
drop policy if exists cfg_read on public.app_config;
create policy cfg_read on public.app_config for select using (true);
drop policy if exists cfg_admin_write on public.app_config;
create policy cfg_admin_write on public.app_config for update using (public.is_admin()) with check (public.is_admin());

-- profiles: read own (or all if admin); update own
drop policy if exists prof_read on public.profiles;
create policy prof_read on public.profiles for select using (id = auth.uid() or public.is_admin());
drop policy if exists prof_update on public.profiles;
create policy prof_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- opens: read own (or all if admin). Inserts happen only via open_day() (definer).
drop policy if exists opens_read on public.opens;
create policy opens_read on public.opens for select using (user_id = auth.uid() or public.is_admin());

-- replies: read own (or all if admin); insert own
drop policy if exists rep_read on public.replies;
create policy rep_read on public.replies for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists rep_insert on public.replies;
create policy rep_insert on public.replies for insert with check (user_id = auth.uid());

grant execute on function public.open_day(int) to authenticated;
grant execute on function public.is_admin() to authenticated;

-- =====================================================================
--  AFTER you've signed up once through the calendar, run this ONCE with
--  your email to give yourself the admin dashboard:
--
--    update public.profiles set is_admin = true
--    where id = (select id from auth.users where email = 'YOUR_EMAIL_HERE');
-- =====================================================================
