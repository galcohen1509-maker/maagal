-- =====================================================================
-- maagal · 005 · הקפצות: "טינדר" לשחקנים, ניקוד וטבלה ארצית, כינוי ייחודי (רץ אחרי 004)
-- =====================================================================
insert into public.settings (key, value, note) values
  ('nearby_km',          15, 'שחקנים זמינים מוצגים בטווח הזה'),
  ('available_hours',     2, 'כמה זמן "זמין להקפיץ" נשאר דלוק'),
  ('swipe_reset_hours',  12, 'אחרי כמה שעות שחקן שדילגת עליו יכול להופיע שוב'),
  ('match_spot_km',      30, 'התאמה פותחת מעגל במקום מאושר בטווח הזה'),
  ('level_gap',           1, '"ברמה שלי" = הפרש רמה עד כאן'),
  ('pts_level5',          3, 'נקודות על דירוג "מפלצת"'),
  ('pts_level4',          2, 'נקודות על דירוג "חזק"'),
  ('pts_level3',          1, 'נקודות על דירוג "סולידי"'),
  ('pts_again',           1, 'נקודה על "בא לי עוד משחק ביחד"')
on conflict (key) do nothing;

-- שני סוגים: הקפצות (בכל מקום) ופוצ'יוולי (רק איפה שיש רשת).
-- spots.sports: תמיד כולל הקפצות. פוצ'יוולי = יש רשת (האדמין מסמן).
update public.spots set sports = case when 'פוצ''יוולי' = any(sports) then '{הקפצות,פוצ''יוולי}'::text[] else '{הקפצות}'::text[] end;

-- סוגי משטח: חוף, חול, דשא, אספלט, מגרש, פארק, אחר
alter table public.spots drop constraint if exists spots_kind_check;
alter table public.spots add constraint spots_kind_check check (kind in ('חוף','חול','דשא','אספלט','מגרש','פארק','אחר'));
create or replace function public.norm_kind(k text) returns text language sql immutable as
$$ select case when k in ('חוף','חול','דשא','אספלט','מגרש','פארק','אחר') then k else 'אחר' end $$;

create or replace function public.add_spot(p_name text, p_kind text, p_sports text[], p_lat float8, p_lng float8)
returns json language plpgsql security definer set search_path = public as $$
declare near spots; nid text; n int; adm boolean := is_admin();
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if char_length(trim(coalesce(p_name, ''))) not between 2 and 30 then
    return json_build_object('ok', false, 'reason', 'name');
  end if;
  select * into near from spots
  where approved and km_between(p_lat, p_lng, lat, lng) * 1000 < setting('spot_dedupe_m')
  order by km_between(p_lat, p_lng, lat, lng) limit 1;
  if found then
    insert into checkins (user_id, spot_id, at) values (auth.uid(), near.id, now())
    on conflict (user_id) do update set spot_id = excluded.spot_id, at = now();
    return json_build_object('ok', true, 'id', near.id, 'existing', true, 'name', near.name);
  end if;
  if not adm then
    if exists (select 1 from spots where not approved and created_by = auth.uid()
               and km_between(p_lat, p_lng, lat, lng) * 1000 < setting('spot_dedupe_m')) then
      return json_build_object('ok', true, 'pending', true, 'again', true);
    end if;
    select count(*) into n from spots where created_by = auth.uid() and created_at > now() - interval '1 day';
    if n >= setting('spot_requests_per_day') then return json_build_object('ok', false, 'reason', 'limit'); end if;
  end if;
  nid := 'u-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
  insert into spots (id, name, short, kind, lat, lng, sports, radius_m, created_by, approved)
  values (nid, trim(p_name), left(trim(p_name), 18), norm_kind(p_kind),
          p_lat, p_lng, '{הקפצות}', setting('user_spot_radius')::int, auth.uid(), adm);
  if not adm then return json_build_object('ok', true, 'pending', true, 'id', nid); end if;
  insert into checkins (user_id, spot_id, at) values (auth.uid(), nid, now())
  on conflict (user_id) do update set spot_id = excluded.spot_id, at = now();
  return json_build_object('ok', true, 'id', nid, 'existing', false);
end $$;

create or replace function public.admin_save_spot(p_id text, p_name text, p_kind text, p_lat float8, p_lng float8,
                                                  p_radius int, p_sports text[] default null)
returns text language plpgsql security definer set search_path = public as $$
declare nid text;
begin
  perform require_admin();
  if char_length(trim(coalesce(p_name, ''))) not between 2 and 40 then raise exception 'name'; end if;
  if p_id is null or p_id = '' then
    nid := 'a-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
    insert into spots (id, name, short, kind, lat, lng, sports, radius_m)
    values (nid, trim(p_name), left(trim(p_name), 18), norm_kind(p_kind), p_lat, p_lng, coalesce(p_sports, '{הקפצות}'),
            greatest(50, least(2000, coalesce(p_radius, 400))));
    return nid;
  end if;
  update spots set name = trim(p_name), short = left(trim(p_name), 18), kind = norm_kind(p_kind), lat = p_lat, lng = p_lng,
         radius_m = greatest(50, least(2000, coalesce(p_radius, radius_m))), sports = coalesce(p_sports, sports)
  where id = p_id;
  if not found then raise exception 'unknown spot'; end if;
  return p_id;
end $$;

-- פוצ'יוולי רק במקום עם רשת
create or replace function public.require_net() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.sport = 'פוצ''יוולי' and not exists (select 1 from spots where id = new.spot_id and 'פוצ''יוולי' = any(sports)) then
    raise exception 'no net here';
  end if;
  return new;
end $$;
drop trigger if exists require_net on public.circles;
create trigger require_net before insert on public.circles for each row execute function public.require_net();
revoke execute on function public.require_net() from public, anon, authenticated;

-- ---------- כינוי ייחודי (בלי הבדל אותיות גדולות/קטנות ורווחים) ----------
with d as (
  select id, row_number() over (partition by lower(trim(nickname)) order by created_at) rn from public.profiles)
update public.profiles p set nickname = left(trim(p.nickname), 17) || '-' || d.rn
from d where d.id = p.id and d.rn > 1;
create unique index if not exists profiles_nickname_uniq on public.profiles (lower(trim(nickname)));

create or replace function public.save_profile(p_nickname text, p_sports text[], p_visibility text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if exists (select 1 from profiles where lower(trim(nickname)) = lower(trim(p_nickname)) and id <> auth.uid()) then
    raise exception 'nickname taken';
  end if;
  insert into profiles (id, nickname, sports, visibility)
  values (auth.uid(), trim(p_nickname), coalesce(p_sports, '{}'), coalesce(p_visibility, 'all'))
  on conflict (id) do update
    set nickname = excluded.nickname, sports = excluded.sports,
        visibility = coalesce(p_visibility, profiles.visibility);
end $$;

-- ---------- ניקוד ----------
-- נקודות נצברות רק מדירוגים במעגל שקרה באמת (מאומת) ושהדירוגים בו נחשפו.
-- מאותו מדרג נספר רק הדירוג הכי טוב בכל חודש, כדי שחברים לא ינפחו.
-- הניקוד שנצבר לא יורד (בשביל הטבלה). היתרה = נצבר פחות מה שהוצא (points_spent), לרכישות בעתיד.
create table if not exists public.points_spent (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  amount     int not null check (amount > 0),
  item       text not null,
  created_at timestamptz not null default now()
);
alter table public.points_spent enable row level security;

create or replace function public.points_earned(u uuid) returns int
language sql stable security definer set search_path = public as $$
  with r as (
    select r.rater, date_trunc('month', r.created_at) m,
      case r.level when 5 then setting('pts_level5') when 4 then setting('pts_level4')
                   when 3 then setting('pts_level3') else 0 end
      + case when r.again then setting('pts_again') else 0 end pts
    from ratings r join circles c on c.id = r.circle_id
    where r.ratee = u and c.status = 'done' and is_verified(c.id) and is_revealed(c.id))
  select coalesce(sum(mx), 0)::int from (select max(pts) mx from r group by rater, m) z
$$;

-- כוכבים = הרמה המאושרת הכי גבוהה (1 עד 5), או 0 אם עוד אין רמה
create or replace function public.player_stars(u uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select round(max(level))::int from levels
                   where user_id = u and games >= setting('games_for_level') and raters >= setting('raters_for_level')), 0)
$$;

create or replace function public.leaderboard(p_limit int default 50) returns json
language sql stable security definer set search_path = public as $$
  with s as (
    select p.id, p.nickname, points_earned(p.id) pts, player_stars(p.id) stars,
      (select count(*) from circle_members m join circles c on c.id = m.circle_id
       where m.user_id = p.id and c.status = 'done') games
    from profiles p where not p.banned),
  r as (select s.*, rank() over (order by pts desc) rnk from s where pts > 0)
  select json_build_object(
    'top', coalesce((select json_agg(json_build_object('rank', rnk, 'nickname', nickname, 'points', pts,
                     'stars', stars, 'games', games, 'me', id = auth.uid()) order by rnk, nickname)
                     from (select * from r order by rnk, nickname limit greatest(0, least(200, p_limit))) t), '[]'),
    'me', (select json_build_object('rank', (select rnk from r where id = auth.uid()),
             'points', pts, 'stars', stars, 'games', games,
             'balance', pts - coalesce((select sum(amount) from points_spent where user_id = auth.uid()), 0))
           from s where id = auth.uid()),
    'players', (select count(*) from r))
$$;

-- ---------- "זמין להקפיץ עכשיו" ----------
-- המיקום נשמר רק כדי לחשב מרחק. אף אחד לא רואה אותו: מוצג רק מרחק מעוגל.
create table if not exists public.availability (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  lat     double precision not null,
  lng     double precision not null,
  pref    text not null default 'any' check (pref in ('mine','any')),
  until   timestamptz not null
);
alter table public.availability enable row level security;

create table if not exists public.swipes (
  from_id uuid references public.profiles(id) on delete cascade,
  to_id   uuid references public.profiles(id) on delete cascade,
  liked   boolean not null,
  at      timestamptz not null default now(),
  primary key (from_id, to_id),
  check (from_id <> to_id)
);
alter table public.swipes enable row level security;

create table if not exists public.matches (
  id         bigint generated always as identity primary key,
  a          uuid references public.profiles(id) on delete cascade,
  b          uuid references public.profiles(id) on delete cascade,
  circle_id  uuid references public.circles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.matches enable row level security;

drop trigger if exists block_banned on public.availability;
create trigger block_banned before insert or update on public.availability for each row execute function public.block_banned();

create or replace function public.set_available(p_on boolean, p_lat float8 default null, p_lng float8 default null,
                                                p_pref text default 'any') returns json
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not p_on or p_lat is null then
    delete from availability where user_id = auth.uid();
    return json_build_object('on', false);
  end if;
  insert into availability (user_id, lat, lng, pref, until)
  values (auth.uid(), p_lat, p_lng, case when p_pref = 'mine' then 'mine' else 'any' end,
          now() + make_interval(hours => setting('available_hours')::int))
  on conflict (user_id) do update set lat = excluded.lat, lng = excluded.lng, pref = excluded.pref, until = excluded.until;
  return json_build_object('on', true, 'until', now() + make_interval(hours => setting('available_hours')::int));
end $$;

create or replace function public.my_availability() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('on', until > now(), 'until', until, 'pref', pref)
  from availability where user_id = auth.uid()
$$;

-- שחקנים זמינים באזור. מסנן לפי רמה אם אני או הוא ביקשנו "ברמה שלי".
create or replace function public.nearby_players(p_lat float8, p_lng float8, p_pref text default 'any')
returns table (id uuid, nickname text, stars int, level_label text, games int, km float8, points int)
language sql stable security definer set search_path = public as $$
  with me as (select my_level(auth.uid(), 'הקפצות') lvl)
  select p.id, p.nickname, player_stars(p.id),
    case when player_stars(p.id) > 0 then level_label(my_level(p.id, 'הקפצות')) else null end,
    (select count(*) from circle_members m join circles c on c.id = m.circle_id
     where m.user_id = p.id and c.status = 'done')::int,
    greatest(0.5, round(km_between(p_lat, p_lng, a.lat, a.lng) * 2) / 2)::float8,
    points_earned(p.id)
  from availability a join profiles p on p.id = a.user_id, me
  where a.until > now() and a.user_id <> auth.uid() and not p.banned
    and km_between(p_lat, p_lng, a.lat, a.lng) <= setting('nearby_km')
    and not exists (select 1 from swipes s where s.from_id = auth.uid() and s.to_id = p.id
                    and s.at > now() - make_interval(hours => setting('swipe_reset_hours')::int))
    and (p_pref <> 'mine' or abs(my_level(p.id, 'הקפצות') - me.lvl) <= setting('level_gap'))
    and (a.pref <> 'mine' or abs(my_level(p.id, 'הקפצות') - me.lvl) <= setting('level_gap'))
  order by km_between(p_lat, p_lng, a.lat, a.lng)
  limit 30
$$;

-- "בוא נקפיץ" או "דלג". אם שניכם לחצתם "בוא נקפיץ": נפתח מעגל במקום המאושר הכי קרוב לשניכם.
create or replace function public.swipe(p_to uuid, p_like boolean) returns json
language plpgsql security definer set search_path = public as $$
declare mine availability; theirs availability; sp spots; cid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into theirs from availability where user_id = p_to and until > now();
  if not found then return json_build_object('ok', false, 'reason', 'gone'); end if;
  insert into swipes (from_id, to_id, liked, at) values (auth.uid(), p_to, p_like, now())
  on conflict (from_id, to_id) do update set liked = excluded.liked, at = now();
  if not p_like then return json_build_object('ok', true, 'match', false); end if;
  if not exists (select 1 from swipes where from_id = p_to and to_id = auth.uid() and liked
                 and at > now() - make_interval(hours => setting('swipe_reset_hours')::int)) then
    return json_build_object('ok', true, 'match', false);
  end if;
  -- התאמה
  select * into mine from availability where user_id = auth.uid();
  select * into sp from spots
  where approved and km_between((coalesce(mine.lat, theirs.lat) + theirs.lat) / 2, (coalesce(mine.lng, theirs.lng) + theirs.lng) / 2, lat, lng)
        <= setting('match_spot_km')
  order by km_between((coalesce(mine.lat, theirs.lat) + theirs.lat) / 2, (coalesce(mine.lng, theirs.lng) + theirs.lng) / 2, lat, lng)
  limit 1;
  if found then
    insert into circles (spot_id, sport, organizer, size, starts_label, open_to_all)
    values (sp.id, 'הקפצות', auth.uid(), 4, 'עכשיו', false) returning id into cid;
    insert into circle_members (circle_id, user_id) values (cid, auth.uid()), (cid, p_to) on conflict do nothing;
  end if;
  insert into matches (a, b, circle_id) values (auth.uid(), p_to, cid);
  return json_build_object('ok', true, 'match', true, 'circle', cid, 'spot', sp.name);
end $$;

create or replace function public.my_matches() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
      'circle', m.circle_id, 'created_at', m.created_at,
      'nickname', (select nickname from profiles where id = case when m.a = auth.uid() then m.b else m.a end))
      order by m.created_at desc), '[]')
  from matches m left join circles c on c.id = m.circle_id
  where (m.a = auth.uid() or m.b = auth.uid()) and m.created_at > now() - interval '3 hours'
    and (c.id is null or c.status in ('open','full'))
$$;


-- כמו ב-004, עם sports לכל מקום (בשביל "יש רשת")
create or replace function public.admin_overview() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  perform require_admin();
  return json_build_object(
    'counts', json_build_object(
      'users',   (select count(*) from profiles),
      'circles', (select count(*) from circles),
      'games',   (select count(*) from circles where status = 'done'),
      'ratings', (select count(*) from ratings)),
    'spots', coalesce((select json_agg(json_build_object(
        'id', s.id, 'name', s.name, 'kind', s.kind, 'lat', s.lat, 'lng', s.lng, 'radius_m', s.radius_m, 'sports', s.sports,
        'by', (select nickname from profiles where id = s.created_by),
        'circles', (select count(*) from circles c where c.spot_id = s.id)) order by s.created_by nulls first, s.name)
      from spots s where s.approved), '[]'),
    'pending', coalesce((select json_agg(json_build_object(
        'id', s.id, 'name', s.name, 'kind', s.kind, 'lat', s.lat, 'lng', s.lng, 'created_at', s.created_at,
        'by', (select nickname from profiles where id = s.created_by)) order by s.created_at)
      from spots s where not s.approved), '[]'),
    'circles', coalesce((select json_agg(json_build_object(
        'id', c.id, 'sport', c.sport, 'spot', s.short, 'org', p.nickname, 'status', c.status,
        'members', member_count(c.id), 'size', c.size, 'created_at', c.created_at) order by c.created_at desc)
      from circles c join spots s on s.id = c.spot_id join profiles p on p.id = c.organizer
      where c.status in ('open','full') and c.created_at > now() - make_interval(mins => setting('circle_ttl_minutes')::int)), '[]'),
    'reports', coalesce((select json_agg(x order by x.created_at desc) from (
        select r.id, r.reason, r.created_at, r.reported reported_id,
          (select nickname from profiles where id = r.reporter) reporter,
          (select nickname from profiles where id = r.reported) reported,
          (select banned from profiles where id = r.reported) banned,
          (select s.short from circles c join spots s on s.id = c.spot_id where c.id = r.circle_id) spot
        from reports r order by r.created_at desc limit 200) x), '[]'),
    'ratings', coalesce((select json_agg(x order by x.created_at desc) from (
        select r.created_at, r.level, r.tags, r.again, c.sport,
          (select nickname from profiles where id = r.rater) rater,
          (select nickname from profiles where id = r.ratee) ratee
        from ratings r join circles c on c.id = r.circle_id order by r.created_at desc limit 200) x), '[]'),
    'feedback', coalesce((select json_agg(x order by x.created_at desc) from (
        select f.body, f.created_at, (select nickname from profiles where id = f.user_id) nick
        from feedback f order by f.created_at desc limit 200) x), '[]'),
    'banned', coalesce((select json_agg(json_build_object('id', id, 'nickname', nickname)) from profiles where banned), '[]'),
    'settings', coalesce((select json_agg(json_build_object('key', key, 'value', value, 'note', note) order by key) from settings), '[]'));
end $$;

-- ---------- הרשאות ----------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in (
             'save_profile','points_earned','player_stars','leaderboard','set_available','my_availability',
             'nearby_players','swipe','my_matches','add_spot','admin_save_spot','admin_overview')
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
