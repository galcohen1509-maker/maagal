-- =====================================================================
-- maagal · 002 · מקומות שמשתמשים מוסיפים ("מקום חדש כאן")
-- =====================================================================
alter table public.spots add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.spots add column if not exists created_at timestamptz not null default now();
alter table public.spots drop constraint if exists spots_kind_check;
alter table public.spots add constraint spots_kind_check check (kind in ('חוף','פארק','מגרש','אחר'));

insert into public.settings (key, value, note) values
  ('spot_dedupe_m',     150, 'מקום חדש קרוב יותר מזה = משתמשים בקיים'),
  ('spots_per_day',     5,   'כמה מקומות חדשים שחקן יכול להוסיף ביום'),
  ('user_spot_radius',  300, 'רדיוס "אני פה" במקום שמשתמש הוסיף'),
  ('feed_km',           25,  'מקומות שמשתמשים הוסיפו מוצגים רק בטווח הזה')
on conflict (key) do nothing;

-- מוסיף מקום במיקום הנוכחי (או מחזיר מקום קיים קרוב) ומסמן "אני פה"
create or replace function public.add_spot(p_name text, p_kind text, p_sports text[], p_lat float8, p_lng float8)
returns json language plpgsql security definer set search_path = public as $$
declare near spots; nid text; n int;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if char_length(trim(coalesce(p_name, ''))) not between 2 and 30 then
    return json_build_object('ok', false, 'reason', 'name');
  end if;
  select * into near from spots
  where km_between(p_lat, p_lng, lat, lng) * 1000 < setting('spot_dedupe_m')
  order by km_between(p_lat, p_lng, lat, lng) limit 1;
  if found then
    insert into checkins (user_id, spot_id, at) values (auth.uid(), near.id, now())
    on conflict (user_id) do update set spot_id = excluded.spot_id, at = now();
    return json_build_object('ok', true, 'id', near.id, 'existing', true, 'name', near.name);
  end if;
  select count(*) into n from spots where created_by = auth.uid() and created_at > now() - interval '1 day';
  if n >= setting('spots_per_day') then return json_build_object('ok', false, 'reason', 'limit'); end if;
  nid := 'u-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
  insert into spots (id, name, short, kind, lat, lng, sports, radius_m, created_by)
  values (nid, trim(p_name), left(trim(p_name), 18),
          case when p_kind in ('חוף','פארק','מגרש','אחר') then p_kind else 'אחר' end,
          p_lat, p_lng, coalesce(p_sports, '{}'), setting('user_spot_radius')::int, auth.uid());
  insert into checkins (user_id, spot_id, at) values (auth.uid(), nid, now())
  on conflict (user_id) do update set spot_id = excluded.spot_id, at = now();
  return json_build_object('ok', true, 'id', nid, 'existing', false);
end $$;
revoke execute on function public.add_spot(text, text, text[], float8, float8) from public, anon;
grant execute on function public.add_spot(text, text, text[], float8, float8) to authenticated;

-- המסך הראשי: מקומות של משתמשים מוצגים רק בטווח, או אם יש בהם פעילות, או שאני יצרתי
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
    where s.created_by is null
       or s.created_by = auth.uid()
       or exists (select 1 from active a where a.spot_id = s.id)
       or exists (select 1 from oc where oc.spot_id = s.id)
       or (p_lat is not null and km_between(p_lat, p_lng, s.lat, s.lng) < setting('feed_km')))
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

-- מעגל במקום של משתמש מוסיף את הספורט לרשימת הספורט של המקום
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
  update spots set sports = array_append(sports, p_sport)
  where id = p_spot and created_by is not null and not (p_sport = any(sports));
  return cid;
end $$;
