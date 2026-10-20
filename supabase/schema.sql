-- =====================================================================
-- maagal · מבנה הנתונים והאלגוריתמים
-- מריצים פעם אחת ב-Supabase: SQL Editor ← New query ← להדביק ← Run
-- =====================================================================

-- ---------- הגדרות האלגוריתם (משנים כאן, בלי לגעת בקוד) ----------
create table if not exists public.settings (
  key   text primary key,
  value numeric not null,
  note  text
);
insert into public.settings (key, value, note) values
  ('k_early',            0.30, 'כמה הרמה זזה בכל אחד מ-3 המשחקים הראשונים'),
  ('k_late',             0.10, 'כמה הרמה זזה אחרי 3 משחקים'),
  ('games_for_level',    3,    'אחרי כמה משחקים מדורגים מוצגת רמה'),
  ('raters_for_level',   3,    'מכמה מדרגים שונים לפחות'),
  ('new_rater_weight',   0.30, 'משקל דירוג של שחקן בלי משחקים'),
  ('trusted_games',      10,   'מכמה משחקים מדרג שוקל 100%'),
  ('outlier_gap',        1.50, 'מרחק מהחציון שנחשב דירוג חריג'),
  ('outlier_weight',     0.30, 'משקל דירוג חריג'),
  ('pair_window_days',   30,   'חלון זמן לחישוב דירוגים חוזרים בין אותו זוג'),
  ('reveal_hours',       24,   'אחרי כמה שעות דירוגים נכנסים גם אם לא כולם דירגו'),
  ('w_level',            0.50, 'משקל רמה בהתאמה'),
  ('w_distance',         0.25, 'משקל מרחק בהתאמה'),
  ('w_crew',             0.15, 'משקל חבר''ה בהתאמה'),
  ('w_reliability',      0.10, 'משקל אמינות המארגן בהתאמה'),
  ('max_minutes',        30,   'מעבר לכמה דקות נסיעה המרחק שווה 0'),
  ('checkin_hours',      3,    'כמה זמן צ''ק-אין נשאר בתוקף'),
  ('circle_ttl_minutes', 60,   'מעגל פתוח נסגר לבד אחרי'),
  ('default_level',      3,    'רמה משוערת למי שעוד אין לו רמה')
on conflict (key) do nothing;

create or replace function public.setting(k text) returns numeric
language sql stable security definer set search_path = public as
$$ select value from public.settings where key = k $$;

-- ---------- טבלאות ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  nickname   text not null check (char_length(nickname) between 2 and 20),
  sports     text[] not null default '{}',
  visibility text not null default 'all' check (visibility in ('all','crew','none')),
  created_at timestamptz not null default now()
);

create table if not exists public.spots (
  id       text primary key,
  name     text not null,
  short    text not null,
  kind     text not null check (kind in ('חוף','פארק','מגרש')),
  lat      double precision not null,
  lng      double precision not null,
  sports   text[] not null default '{}',
  radius_m int not null default 400
);

create table if not exists public.checkins (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  spot_id text not null references public.spots(id) on delete cascade,
  at      timestamptz not null default now()
);

create table if not exists public.circles (
  id           uuid primary key default gen_random_uuid(),
  spot_id      text not null references public.spots(id),
  sport        text not null,
  organizer    uuid not null references public.profiles(id) on delete cascade,
  size         int  not null check (size between 2 and 12),
  starts_label text not null default 'עכשיו',
  open_to_all  boolean not null default false,
  court_info   text,
  status       text not null default 'open' check (status in ('open','full','done','cancelled')),
  created_at   timestamptz not null default now(),
  ended_at     timestamptz
);

create table if not exists public.circle_members (
  circle_id uuid references public.circles(id) on delete cascade,
  user_id   uuid references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);

create table if not exists public.messages (
  id         bigint generated always as identity primary key,
  circle_id  uuid not null references public.circles(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  nickname   text not null,
  body       text not null check (char_length(body) between 1 and 300),
  created_at timestamptz not null default now()
);

create table if not exists public.confirmations (
  circle_id  uuid references public.circles(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  happened   boolean not null,
  no_shows   uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);

create table if not exists public.ratings (
  circle_id  uuid references public.circles(id) on delete cascade,
  rater      uuid references public.profiles(id) on delete cascade,
  ratee      uuid references public.profiles(id) on delete cascade,
  level      smallint not null check (level between 1 and 5),
  tags       text[] not null default '{}',
  again      boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (circle_id, rater, ratee),
  check (rater <> ratee)
);

create table if not exists public.levels (
  user_id    uuid references public.profiles(id) on delete cascade,
  sport      text,
  level      numeric(4,2) not null,
  games      int not null,
  raters     int not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, sport)
);

create table if not exists public.crew (
  user_id    uuid references public.profiles(id) on delete cascade,
  friend     uuid references public.profiles(id) on delete cascade,
  alerts     boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (user_id, friend),
  check (user_id <> friend)
);

create table if not exists public.reports (
  id         bigint generated always as identity primary key,
  circle_id  uuid references public.circles(id) on delete set null,
  reporter   uuid references public.profiles(id) on delete cascade,
  reported   uuid references public.profiles(id) on delete cascade,
  reason     text,
  created_at timestamptz not null default now()
);

create index if not exists circles_open_idx on public.circles (status, created_at);
create index if not exists members_user_idx on public.circle_members (user_id);
create index if not exists ratings_ratee_idx on public.ratings (ratee);
create index if not exists ratings_rater_idx on public.ratings (rater);
create index if not exists messages_circle_idx on public.messages (circle_id, id);

-- ---------- מקומות (קואורדינטות משוערות, אפשר לתקן בטבלה) ----------
insert into public.spots (id, name, short, kind, lat, lng, sports, radius_m) values
  ('gordon',   'חוף גורדון',                'גורדון',        'חוף',   32.0849, 34.7680, '{פוצ''יוולי,מטקות,כדורעף}', 450),
  ('frishman', 'חוף פרישמן',                'פרישמן',        'חוף',   32.0806, 34.7662, '{פוצ''יוולי,מטקות,כדורעף}', 450),
  ('hilton',   'חוף הילטון',                'הילטון',        'חוף',   32.0905, 34.7702, '{פוצ''יוולי,מטקות,כדורעף}', 450),
  ('accadia',  'חוף אכדיה',                 'אכדיה',         'חוף',   32.1646, 34.7976, '{פוצ''יוולי,מטקות,כדורעף}', 500),
  ('yarkon',   'מגרש כדורעף, פארק הירקון',  'פארק הירקון',   'פארק',  32.0978, 34.8098, '{כדורעף,פוצ''יוולי}',         700),
  ('padel',    'מגרשי פאדל, הרצליה פיתוח',  'פאדל הרצליה',   'מגרש',  32.1640, 34.8060, '{פאדל}',                      400),
  ('tennis',   'מגרשי טניס, רמת השרון',     'טניס רמת השרון','מגרש',  32.1385, 34.8346, '{טניס}',                      400)
on conflict (id) do nothing;

-- ---------- כלי עזר ----------
create or replace function public.km_between(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
returns float8 language sql immutable as $$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))
$$;

create or replace function public.drive_minutes(km float8) returns int
language sql immutable as $$ select greatest(2, round(km * 2.2 + 3))::int $$;

create or replace function public.level_label(l numeric) returns text
language sql immutable as $$
  select case when l is null then null
              when l < 1.5 then 'מתחיל' when l < 2.5 then 'מתחמם'
              when l < 3.5 then 'סולידי' when l < 4.5 then 'חזק' else 'מפלצת' end
$$;

create or replace function public.member_count(c uuid) returns int
language sql stable security definer set search_path = public as
$$ select count(*)::int from public.circle_members where circle_id = c $$;

create or replace function public.my_level(u uuid, sp text) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select level from public.levels where user_id = u and sport = sp), public.setting('default_level'))
$$;

-- אמינות: אחוז הגעה (כמה פעמים סומן כמבריז מתוך המשחקים שלו)
create or replace function public.reliability(u uuid) returns numeric
language sql stable security definer set search_path = public as $$
  with g as (
    select count(*) n from public.circle_members m join public.circles c on c.id = m.circle_id
    where m.user_id = u and c.status = 'done'),
  ns as (
    select count(distinct circle_id) n from public.confirmations where u = any(no_shows))
  select case when (select n from g) = 0 then 1
              else greatest(0, 1 - (select n from ns)::numeric / (select n from g)) end
$$;

-- משחק מאומת: כולם אישרו שקרה, או אחרי 24 שעות רוב אישר ואף אחד לא אמר שלא
create or replace function public.is_verified(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  with s as (
    select count(*) filter (where happened) yes, count(*) filter (where not happened) no
    from public.confirmations where circle_id = c)
  select (select no from s) = 0 and (
           (select yes from s) >= public.member_count(c)
        or ((select yes from s) * 2 > public.member_count(c)
            and (select ended_at from public.circles where id = c) < now() - make_interval(hours => public.setting('reveal_hours')::int)))
$$;

-- דירוגים נחשפים: כולם דירגו, או עברו 24 שעות
create or replace function public.is_revealed(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select (select count(distinct rater) from public.ratings where circle_id = c) >= public.member_count(c)
      or (select ended_at from public.circles where id = c) < now() - make_interval(hours => public.setting('reveal_hours')::int)
$$;

-- ---------- אלגוריתם הרמה ----------
create or replace function public.recompute_level(u uuid, sp text) returns void
language plpgsql security definer set search_path = public as $$
declare
  lvl numeric := null; g int := 0; avg_l numeric; k numeric; c record;
  nw numeric := setting('new_rater_weight'); tg numeric := setting('trusted_games');
  gap numeric := setting('outlier_gap');      ow numeric := setting('outlier_weight');
  win interval := make_interval(days => setting('pair_window_days')::int);
begin
  for c in
    select ci.id from circles ci
    where ci.sport = sp and ci.status = 'done'
      and exists (select 1 from ratings r where r.circle_id = ci.id and r.ratee = u)
      and is_verified(ci.id) and is_revealed(ci.id)
    order by ci.ended_at
  loop
    select sum(w * level) / nullif(sum(w), 0) into avg_l from (
      select r.level,
        -- ותק המדרג
        (nw + (1 - nw) * least(1, (select count(*) from circle_members m join circles x on x.id = m.circle_id
                                   where m.user_id = r.rater and x.status = 'done')::numeric / tg))
        -- עקביות המדרג: כמה מהדירוגים שלו בעבר היו חריגים
        * (1 - 0.6 * coalesce((
            select avg(case when abs(r3.level - (select percentile_cont(0.5) within group (order by r4.level)
                                                 from ratings r4 where r4.circle_id = r3.circle_id and r4.ratee = r3.ratee)) > gap
                            then 1 else 0 end)
            from ratings r3 where r3.rater = r.rater and r3.circle_id <> c.id), 0))
        -- אותו מדרג שוב ושוב: 100%, 50%, 25%...
        * power(0.5, (select count(*) from ratings r2
                      where r2.rater = r.rater and r2.ratee = u
                        and r2.created_at < r.created_at and r2.created_at > r.created_at - win))
        -- דירוג חריג במשחק עצמו
        * case when abs(r.level - (select percentile_cont(0.5) within group (order by r5.level)
                                   from ratings r5 where r5.circle_id = c.id and r5.ratee = u)) > gap
               then ow else 1 end as w
      from ratings r where r.circle_id = c.id and r.ratee = u
    ) t;

    continue when avg_l is null;
    if lvl is null then lvl := avg_l;
    else
      k := case when g < 3 then setting('k_early') else setting('k_late') end;
      lvl := lvl + k * (avg_l - lvl);
    end if;
    g := g + 1;
  end loop;

  if lvl is not null then
    insert into levels (user_id, sport, level, games, raters, updated_at)
    values (u, sp, round(lvl, 2), g,
            (select count(distinct r.rater) from ratings r join circles ci on ci.id = r.circle_id
             where r.ratee = u and ci.sport = sp and is_verified(ci.id) and is_revealed(ci.id)), now())
    on conflict (user_id, sport) do update
      set level = excluded.level, games = excluded.games, raters = excluded.raters, updated_at = now();
  end if;
end $$;

-- ---------- פרופיל ----------
create or replace function public.save_profile(p_nickname text, p_sports text[], p_visibility text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into profiles (id, nickname, sports, visibility)
  values (auth.uid(), trim(p_nickname), coalesce(p_sports, '{}'), coalesce(p_visibility, 'all'))
  on conflict (id) do update
    set nickname = excluded.nickname, sports = excluded.sports,
        visibility = coalesce(p_visibility, profiles.visibility);
end $$;

-- ---------- צ'ק-אין לפי מיקום ----------
create or replace function public.check_in(p_spot text, p_lat float8, p_lng float8)
returns json language plpgsql security definer set search_path = public as $$
declare s spots; d float8;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into s from spots where id = p_spot;
  if not found then raise exception 'unknown spot'; end if;
  d := km_between(p_lat, p_lng, s.lat, s.lng) * 1000;
  if d > s.radius_m then
    return json_build_object('ok', false, 'meters', round(d));
  end if;
  insert into checkins (user_id, spot_id, at) values (auth.uid(), p_spot, now())
  on conflict (user_id) do update set spot_id = excluded.spot_id, at = now();
  return json_build_object('ok', true, 'meters', round(d));
end $$;

create or replace function public.check_out() returns void
language sql security definer set search_path = public as
$$ delete from checkins where user_id = auth.uid() $$;

-- ---------- המסך הראשי: מקומות לפי מרחק ----------
create or replace function public.spot_feed(p_lat float8 default null, p_lng float8 default null)
returns table (id text, name text, short text, kind text, sports text[], lat float8, lng float8,
               km float8, minutes int, people int, crew_here text[], open_circles int, status text, i_am_here boolean)
language sql stable security definer set search_path = public as $$
  with active as (
    select ch.* from checkins ch where ch.at > now() - make_interval(hours => setting('checkin_hours')::int)),
  oc as (
    select c.spot_id, count(*) n from circles c
    where c.status in ('open','full') and c.created_at > now() - make_interval(mins => setting('circle_ttl_minutes')::int)
    group by c.spot_id)
  select s.id, s.name, s.short, s.kind, s.sports, s.lat, s.lng,
    case when p_lat is null then null else round(km_between(p_lat, p_lng, s.lat, s.lng)::numeric, 1)::float8 end,
    case when p_lat is null then null else drive_minutes(km_between(p_lat, p_lng, s.lat, s.lng)) end,
    (select count(*) from active a where a.spot_id = s.id)::int,
    coalesce((select array_agg(p.nickname) from active a join crew cr on cr.friend = a.user_id and cr.user_id = auth.uid()
              join profiles p on p.id = a.user_id
              where a.spot_id = s.id and p.visibility <> 'none'), '{}'),
    coalesce((select n from oc where oc.spot_id = s.id), 0)::int,
    case when (select count(*) from active a where a.spot_id = s.id) >= 8 or coalesce((select n from oc where oc.spot_id = s.id), 0) >= 2 then 'בוער'
         when (select count(*) from active a where a.spot_id = s.id) >= 3 or coalesce((select n from oc where oc.spot_id = s.id), 0) >= 1 then 'מתחמם'
         else 'שקט' end,
    exists (select 1 from active a where a.spot_id = s.id and a.user_id = auth.uid())
  from spots s
  order by case when p_lat is null then 0 else km_between(p_lat, p_lng, s.lat, s.lng) end, s.id
$$;

-- ---------- אלגוריתם ההתאמה: מעגלים פתוחים עם אחוז ----------
create or replace function public.circle_feed(p_lat float8 default null, p_lng float8 default null, p_spot text default null)
returns table (id uuid, spot_id text, spot_short text, spot_kind text, sport text, organizer_nick text,
               size int, members int, starts_label text, open_to_all boolean, court_info text, status text,
               avg_level numeric, avg_label text, match int, minutes int, i_am_in boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  with c as (
    select c.*, s.short, s.kind, s.lat, s.lng from circles c join spots s on s.id = c.spot_id
    where c.status in ('open','full')
      and c.created_at > now() - make_interval(mins => setting('circle_ttl_minutes')::int)
      and (p_spot is null or c.spot_id = p_spot)),
  x as (
    select c.*,
      (select avg(my_level(m.user_id, c.sport)) from circle_members m where m.circle_id = c.id) avg_lvl,
      case when p_lat is null then null else drive_minutes(km_between(p_lat, p_lng, c.lat, c.lng)) end mins,
      case when exists (select 1 from circle_members m join crew cr on cr.friend = m.user_id
                        where m.circle_id = c.id and cr.user_id = auth.uid()) then 1
           when exists (select 1 from circle_members m join circle_members m2 on m2.user_id = auth.uid()
                        join circles pc on pc.id = m2.circle_id and pc.status = 'done'
                        join circle_members m3 on m3.circle_id = pc.id and m3.user_id = m.user_id
                        where m.circle_id = c.id and m.user_id <> auth.uid()) then 0.5
           else 0 end crew_score
    from c)
  select x.id, x.spot_id, x.short, x.kind, x.sport, p.nickname, x.size, member_count(x.id),
    x.starts_label, x.open_to_all, x.court_info, x.status, round(x.avg_lvl, 1), level_label(x.avg_lvl),
    round(100 * (
        setting('w_level')       * greatest(0, 1 - abs(my_level(auth.uid(), x.sport) - x.avg_lvl) / 4)
      + setting('w_distance')    * case when x.mins is null then 0.5 else greatest(0, 1 - x.mins / setting('max_minutes')) end
      + setting('w_crew')        * x.crew_score
      + setting('w_reliability') * reliability(x.organizer)))::int,
    x.mins,
    exists (select 1 from circle_members m where m.circle_id = x.id and m.user_id = auth.uid()),
    x.created_at
  from x join profiles p on p.id = x.organizer
  order by 15 desc, x.created_at desc
$$;

-- ---------- מעגלים ----------
create or replace function public.create_circle(p_spot text, p_sport text, p_size int, p_label text,
                                                p_open boolean default false, p_court text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into circles (spot_id, sport, organizer, size, starts_label, open_to_all, court_info)
  values (p_spot, p_sport, auth.uid(), greatest(2, least(12, p_size)), coalesce(p_label, 'עכשיו'), p_open, p_court)
  returning id into cid;
  insert into circle_members (circle_id, user_id) values (cid, auth.uid());
  return cid;
end $$;

create or replace function public.join_circle(p_circle uuid) returns json
language plpgsql security definer set search_path = public as $$
declare c circles; n int;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into c from circles where id = p_circle for update;
  if not found then return json_build_object('ok', false, 'reason', 'not_found'); end if;
  if exists (select 1 from circle_members where circle_id = p_circle and user_id = auth.uid()) then
    return json_build_object('ok', true, 'already', true);
  end if;
  if c.status <> 'open' or c.created_at < now() - make_interval(mins => setting('circle_ttl_minutes')::int) then
    return json_build_object('ok', false, 'reason', 'closed');
  end if;
  n := member_count(p_circle);
  if n >= c.size then return json_build_object('ok', false, 'reason', 'full'); end if;
  insert into circle_members (circle_id, user_id) values (p_circle, auth.uid());
  if n + 1 >= c.size then update circles set status = 'full' where id = p_circle; end if;
  return json_build_object('ok', true);
end $$;

create or replace function public.leave_circle(p_circle uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c circles;
begin
  select * into c from circles where id = p_circle;
  if not found or c.status in ('done','cancelled') then return; end if;
  if c.organizer = auth.uid() then
    update circles set status = 'cancelled' where id = p_circle;
  else
    delete from circle_members where circle_id = p_circle and user_id = auth.uid();
    update circles set status = 'open' where id = p_circle and status = 'full';
  end if;
end $$;

create or replace function public.finish_circle(p_circle uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from circle_members where circle_id = p_circle and user_id = auth.uid()) then
    raise exception 'not a member';
  end if;
  if member_count(p_circle) < 2 then raise exception 'need at least 2 players'; end if;
  update circles set status = 'done', ended_at = now()
  where id = p_circle and status in ('open','full');
end $$;

create or replace function public.circle_detail(p_circle uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'id', c.id, 'sport', c.sport, 'size', c.size, 'starts_label', c.starts_label,
    'open_to_all', c.open_to_all, 'court_info', c.court_info, 'status', c.status,
    'created_at', c.created_at, 'organizer', c.organizer,
    'spot', json_build_object('id', s.id, 'name', s.name, 'short', s.short, 'kind', s.kind),
    'i_am_in', exists (select 1 from circle_members m where m.circle_id = c.id and m.user_id = auth.uid()),
    'i_rated', exists (select 1 from ratings r where r.circle_id = c.id and r.rater = auth.uid()),
    'members', coalesce((select json_agg(json_build_object(
        'id', p.id, 'nickname', p.nickname, 'is_organizer', p.id = c.organizer,
        'level', level_label((select level from levels l where l.user_id = p.id and l.sport = c.sport
                              and l.games >= setting('games_for_level') and l.raters >= setting('raters_for_level'))))
        order by m.joined_at)
      from circle_members m join profiles p on p.id = m.user_id where m.circle_id = c.id), '[]'))
  from circles c join spots s on s.id = c.spot_id where c.id = p_circle
$$;

-- ---------- צ'אט ----------
create or replace function public.send_message(p_circle uuid, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from circle_members where circle_id = p_circle and user_id = auth.uid()) then
    raise exception 'not a member';
  end if;
  insert into messages (circle_id, user_id, nickname, body)
  values (p_circle, auth.uid(), (select nickname from profiles where id = auth.uid()), left(trim(p_body), 300));
end $$;

-- ---------- דירוג אחרי משחק ----------
-- p_items: [{"ratee":"uuid","level":1-5,"tags":["..."],"again":true}]
create or replace function public.submit_ratings(p_circle uuid, p_happened boolean, p_no_shows uuid[], p_items jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare c circles; it jsonb; r uuid;
begin
  select * into c from circles where id = p_circle;
  if not found then raise exception 'unknown circle'; end if;
  if c.status <> 'done' then raise exception 'game not finished'; end if;
  if not exists (select 1 from circle_members where circle_id = p_circle and user_id = auth.uid()) then
    raise exception 'only players in this circle can rate';
  end if;

  insert into confirmations (circle_id, user_id, happened, no_shows)
  values (p_circle, auth.uid(), p_happened, coalesce(p_no_shows, '{}'))
  on conflict (circle_id, user_id) do update set happened = excluded.happened, no_shows = excluded.no_shows;

  if p_happened then
    for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
      r := (it->>'ratee')::uuid;
      continue when r = auth.uid();
      continue when not exists (select 1 from circle_members where circle_id = p_circle and user_id = r);
      continue when r = any(coalesce(p_no_shows, '{}'));
      insert into ratings (circle_id, rater, ratee, level, tags, again)
      values (p_circle, auth.uid(), r, greatest(1, least(5, (it->>'level')::int)),
              case when jsonb_typeof(it->'tags') = 'array' then array(select jsonb_array_elements_text(it->'tags')) else '{}' end,
              coalesce((it->>'again')::boolean, false))
      on conflict do nothing;
      if coalesce((it->>'again')::boolean, false) then
        insert into crew (user_id, friend) values (auth.uid(), r) on conflict do nothing;
      end if;
    end loop;
  end if;

  -- מחשבים מחדש את כל מי שבמעגל (נכנס רק אם המשחק מאומת והדירוגים נחשפו)
  for r in select user_id from circle_members where circle_id = p_circle loop
    perform recompute_level(r, c.sport);
  end loop;
end $$;

-- משחקים שמחכים לדירוג שלי
create or replace function public.pending_ratings() returns table (id uuid, sport text, spot_short text, ended_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.sport, s.short, c.ended_at from circles c
  join circle_members m on m.circle_id = c.id and m.user_id = auth.uid()
  join spots s on s.id = c.spot_id
  where c.status = 'done' and c.ended_at > now() - interval '7 days'
    and not exists (select 1 from confirmations f where f.circle_id = c.id and f.user_id = auth.uid())
  order by c.ended_at desc
$$;

-- רענון הרמות שלי (דירוגים שנחשפו אחרי 24 שעות)
create or replace function public.refresh_my_levels() returns void
language plpgsql security definer set search_path = public as $$
declare sp text;
begin
  for sp in select distinct c.sport from ratings r join circles c on c.id = r.circle_id where r.ratee = auth.uid() loop
    perform recompute_level(auth.uid(), sp);
  end loop;
end $$;

-- ---------- פרופיל וחבר'ה ----------
create or replace function public.my_profile() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'id', p.id, 'nickname', p.nickname, 'sports', p.sports, 'visibility', p.visibility,
    'games', (select count(*) from circle_members m join circles c on c.id = m.circle_id
              where m.user_id = p.id and c.status = 'done'),
    'reliability', round(reliability(p.id) * 100),
    'crew_count', (select count(*) from crew where user_id = p.id),
    'games_for_level', setting('games_for_level'),
    'levels', coalesce((select json_agg(json_build_object(
        'sport', l.sport, 'level', l.level, 'games', l.games, 'raters', l.raters,
        'label', level_label(l.level),
        'confirmed', l.games >= setting('games_for_level') and l.raters >= setting('raters_for_level'))
        order by l.games desc) from levels l where l.user_id = p.id), '[]'),
    'tags', coalesce((select json_object_agg(t, n) from (
        select t, count(*) n from ratings r, unnest(r.tags) t
        where r.ratee = p.id and is_revealed(r.circle_id) group by t order by 2 desc limit 6) z), '{}'))
  from profiles p where p.id = auth.uid()
$$;

create or replace function public.my_crew() returns table (id uuid, nickname text, spot_short text, since timestamptz, alerts boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.nickname,
    case when p.visibility <> 'none' then s.short end,
    case when p.visibility <> 'none' then ch.at end,
    cr.alerts
  from crew cr join profiles p on p.id = cr.friend
  left join checkins ch on ch.user_id = p.id and ch.at > now() - make_interval(hours => setting('checkin_hours')::int)
  left join spots s on s.id = ch.spot_id
  where cr.user_id = auth.uid()
  order by (ch.at is null), p.nickname
$$;

create or replace function public.report_player(p_circle uuid, p_player uuid, p_reason text) returns void
language sql security definer set search_path = public as $$
  insert into reports (circle_id, reporter, reported, reason) values (p_circle, auth.uid(), p_player, left(p_reason, 300))
$$;

-- ---------- אבטחה (RLS): הטלפון קורא, את השינויים עושים רק הפונקציות למעלה ----------
alter table public.settings       enable row level security;
alter table public.profiles       enable row level security;
alter table public.spots          enable row level security;
alter table public.checkins       enable row level security;
alter table public.circles        enable row level security;
alter table public.circle_members enable row level security;
alter table public.messages       enable row level security;
alter table public.confirmations  enable row level security;
alter table public.ratings        enable row level security;
alter table public.levels         enable row level security;
alter table public.crew           enable row level security;
alter table public.reports        enable row level security;

drop policy if exists "settings readable" on public.settings;
create policy "settings readable" on public.settings for select to authenticated using (true);
drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select to authenticated using (true);
drop policy if exists "spots readable" on public.spots;
create policy "spots readable" on public.spots for select to anon, authenticated using (true);
drop policy if exists "circles readable" on public.circles;
create policy "circles readable" on public.circles for select to authenticated using (true);
drop policy if exists "members readable" on public.circle_members;
create policy "members readable" on public.circle_members for select to authenticated using (true);
drop policy if exists "messages for members" on public.messages;
create policy "messages for members" on public.messages for select to authenticated
  using (exists (select 1 from public.circle_members m where m.circle_id = messages.circle_id and m.user_id = auth.uid()));
drop policy if exists "levels readable" on public.levels;
create policy "levels readable" on public.levels for select to authenticated using (true);
drop policy if exists "own crew" on public.crew;
create policy "own crew" on public.crew for select to authenticated using (user_id = auth.uid());
-- checkins, ratings, confirmations, reports: אין קריאה ישירה בכלל (פרטיות וחיסיון)

-- הפונקציות זמינות רק למחוברים
do $$
declare f record;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in (
             'setting','member_count','my_level','reliability','is_verified','is_revealed','recompute_level',
             'save_profile','check_in','check_out','spot_feed','circle_feed','create_circle','join_circle',
             'leave_circle','finish_circle','circle_detail','send_message','submit_ratings','pending_ratings',
             'refresh_my_levels','my_profile','my_crew','report_player')
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
-- את החישוב הפנימי אי אפשר להפעיל ישירות מהטלפון
revoke execute on function public.recompute_level(uuid, text) from authenticated;

-- ---------- עדכונים חיים ----------
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.messages;       exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.circle_members; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.circles;        exception when duplicate_object then null; end;
  end if;
end $$;
