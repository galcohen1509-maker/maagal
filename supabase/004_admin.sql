-- =====================================================================
-- maagal · 004 · ניהול (אדמין) + ביקורות על האפליקציה (רץ אחרי 003)
-- אדמין נקבע רק כאן, ב-SQL Editor. מהטלפון אי אפשר להפוך לאדמין.
-- כל פעולת ניהול נבדקת בשרת (is_admin), גם אם מישהו עוקף את המסך.
-- =====================================================================
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;  -- אין policies: אין גישה ישירה

alter table public.profiles add column if not exists banned boolean not null default false;

create table if not exists public.feedback (
  id         bigint generated always as identity primary key,
  user_id    uuid references public.profiles(id) on delete set null,
  body       text not null check (char_length(body) between 2 and 1000),
  created_at timestamptz not null default now()
);
alter table public.feedback enable row level security;  -- אין policies: רק דרך פונקציות

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from admins where user_id = auth.uid()) $$;

create or replace function public.require_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from admins where user_id = auth.uid()) then raise exception 'admin only'; end if;
end $$;

-- ---------- חסימה: שחקן חסום לא יכול לפתוח, להצטרף, לכתוב, להוסיף מקום או לסמן "אני פה" ----------
create or replace function public.block_banned() returns trigger
language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  if tg_table_name = 'circles' then u := new.organizer;
  elsif tg_table_name = 'spots' then u := new.created_by;
  else u := new.user_id; end if;
  if u is not null and exists (select 1 from profiles where id = u and banned) then
    raise exception 'banned';
  end if;
  return new;
end $$;
drop trigger if exists block_banned on public.circles;
create trigger block_banned before insert on public.circles for each row execute function public.block_banned();
drop trigger if exists block_banned on public.circle_members;
create trigger block_banned before insert on public.circle_members for each row execute function public.block_banned();
drop trigger if exists block_banned on public.messages;
create trigger block_banned before insert on public.messages for each row execute function public.block_banned();
drop trigger if exists block_banned on public.spots;
create trigger block_banned before insert on public.spots for each row execute function public.block_banned();
drop trigger if exists block_banned on public.checkins;
create trigger block_banned before insert or update on public.checkins for each row execute function public.block_banned();

-- ---------- ביקורת על האפליקציה (כל משתמש) ----------
create or replace function public.send_feedback(p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if (select count(*) from feedback where user_id = auth.uid() and created_at > now() - interval '1 day') >= 10 then
    raise exception 'too many';
  end if;
  insert into feedback (user_id, body) values (auth.uid(), left(trim(p_body), 1000));
end $$;

-- ---------- מסך הניהול: הכל בקריאה אחת ----------
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
        'id', s.id, 'name', s.name, 'kind', s.kind, 'lat', s.lat, 'lng', s.lng, 'radius_m', s.radius_m,
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

-- ---------- מקומות ----------
create or replace function public.admin_save_spot(p_id text, p_name text, p_kind text, p_lat float8, p_lng float8,
                                                  p_radius int, p_sports text[] default null)
returns text language plpgsql security definer set search_path = public as $$
declare nid text;
begin
  perform require_admin();
  if char_length(trim(coalesce(p_name, ''))) not between 2 and 40 then raise exception 'name'; end if;
  if p_kind not in ('חוף','פארק','מגרש','אחר') then p_kind := 'אחר'; end if;
  if p_id is null or p_id = '' then
    nid := 'a-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
    insert into spots (id, name, short, kind, lat, lng, sports, radius_m)
    values (nid, trim(p_name), left(trim(p_name), 18), p_kind, p_lat, p_lng, coalesce(p_sports, '{}'),
            greatest(50, least(2000, coalesce(p_radius, 400))));
    return nid;
  end if;
  update spots set name = trim(p_name), short = left(trim(p_name), 18), kind = p_kind, lat = p_lat, lng = p_lng,
         radius_m = greatest(50, least(2000, coalesce(p_radius, radius_m))), sports = coalesce(p_sports, sports)
  where id = p_id;
  if not found then raise exception 'unknown spot'; end if;
  return p_id;
end $$;

create or replace function public.admin_delete_spot(p_id text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform require_admin();
  if exists (select 1 from circles where spot_id = p_id) then
    return json_build_object('ok', false, 'reason', 'has_circles');
  end if;
  delete from spots where id = p_id;
  return json_build_object('ok', true);
end $$;

-- ---------- מעגלים ----------
create or replace function public.admin_close_circle(p_circle uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_admin();
  update circles set status = 'cancelled', ended_at = now() where id = p_circle and status in ('open','full');
end $$;

-- ---------- משתמשים ----------
create or replace function public.admin_ban(p_user uuid, p_ban boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_admin();
  if p_ban and exists (select 1 from admins where user_id = p_user) then raise exception 'cannot ban admin'; end if;
  update profiles set banned = p_ban where id = p_user;
  if p_ban then
    delete from checkins where user_id = p_user;
    update circles set status = 'cancelled', ended_at = now() where organizer = p_user and status in ('open','full');
  end if;
end $$;

-- ---------- הגדרות ----------
create or replace function public.admin_set_setting(p_key text, p_value numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_admin();
  update settings set value = p_value where key = p_key;
  if not found then raise exception 'unknown setting'; end if;
end $$;

-- ---------- הרשאות: רק למחוברים. הבדיקה של אדמין בתוך כל פונקציה ----------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in (
             'is_admin','send_feedback','admin_overview','admin_save_spot','admin_delete_spot',
             'admin_close_circle','admin_ban','admin_set_setting')
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
revoke execute on function public.require_admin() from public, anon, authenticated;
revoke execute on function public.block_banned() from public, anon, authenticated;

-- =====================================================================
-- מקום חדש = בקשה. רק הבעלים (אדמין) מוסיף מקום ישירות או מאשר בקשה.
-- מקום שלא אושר: לא מופיע לאף אחד, ואי אפשר לפתוח בו מעגל או לסמן בו "אני פה".
-- =====================================================================
alter table public.spots add column if not exists approved boolean not null default true;

insert into public.settings (key, value, note) values
  ('spot_requests_per_day', 3, 'כמה בקשות למקום חדש שחקן יכול לשלוח ביום')
on conflict (key) do nothing;

create or replace function public.require_approved_spot() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from spots where id = new.spot_id and approved) then raise exception 'spot not approved'; end if;
  return new;
end $$;
drop trigger if exists require_approved_spot on public.circles;
create trigger require_approved_spot before insert on public.circles for each row execute function public.require_approved_spot();
drop trigger if exists require_approved_spot on public.checkins;
create trigger require_approved_spot before insert or update on public.checkins for each row execute function public.require_approved_spot();

-- שחקן: אם יש מקום מאושר קרוב, משתמשים בו (ומסמנים "אני פה"). אחרת נשלחת בקשה לאישור.
-- אדמין: המקום נוסף מיד, מאושר.
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
  values (nid, trim(p_name), left(trim(p_name), 18),
          case when p_kind in ('חוף','פארק','מגרש','אחר') then p_kind else 'אחר' end,
          p_lat, p_lng, coalesce(p_sports, '{}'), setting('user_spot_radius')::int, auth.uid(), adm);
  if not adm then return json_build_object('ok', true, 'pending', true, 'id', nid); end if;
  insert into checkins (user_id, spot_id, at) values (auth.uid(), nid, now())
  on conflict (user_id) do update set spot_id = excluded.spot_id, at = now();
  return json_build_object('ok', true, 'id', nid, 'existing', false);
end $$;

-- כמו ב-002, רק מקומות מאושרים
create or replace function public.spot_feed(p_lat float8 default null, p_lng float8 default null)
returns table (id text, name text, short text, kind text, sports text[], lat float8, lng float8,
               km float8, minutes int, people int, crew_here text[], open_circles int, status text, i_am_here boolean)
language sql stable security definer set search_path = public as $$
  with active as (
    select ch.* from checkins ch where ch.at > now() - make_interval(hours => setting('checkin_hours')::int)),
  oc as (
    select c.spot_id, count(*) n from circles c
    where c.status in ('open','full') and c.created_at > now() - make_interval(mins => setting('circle_ttl_minutes')::int)
    group by c.spot_id),
  vis as (
    select s.* from spots s
    where s.approved and (
          s.created_by is null
       or s.created_by = auth.uid()
       or exists (select 1 from active a where a.spot_id = s.id)
       or exists (select 1 from oc where oc.spot_id = s.id)
       or (p_lat is not null and km_between(p_lat, p_lng, s.lat, s.lng) < setting('feed_km'))))
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
  from vis s
  order by case when p_lat is null then 0 else km_between(p_lat, p_lng, s.lat, s.lng) end, s.id
  limit 30
$$;

create or replace function public.admin_review_spot(p_id text, p_approve boolean, p_name text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_admin();
  if p_approve then
    update spots set approved = true,
           name = coalesce(nullif(trim(p_name), ''), name), short = left(coalesce(nullif(trim(p_name), ''), name), 18)
    where id = p_id;
  else
    delete from spots where id = p_id and not approved;
  end if;
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('add_spot','spot_feed','admin_review_spot')
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
revoke execute on function public.require_approved_spot() from public, anon, authenticated;

-- ---------- להפוך את גל לאדמין: מריצים פעם אחת, עם המייל שאיתו גל נכנס ----------
-- insert into public.admins (user_id) select id from auth.users where email = 'MAIL@gmail.com' on conflict do nothing;
