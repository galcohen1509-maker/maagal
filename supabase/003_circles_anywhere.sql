-- =====================================================================
-- maagal · 003 · מעגל בכל מקום (רץ אחרי 002_user_spots.sql)
-- 1. מעגלים מוצגים רק בטווח מהשחקן (חוץ ממעגלים שאני בהם, או שהחבר'ה שלי בהם)
-- 2. דף מעגל מחזיר את מיקום המקום, כדי לנווט אליו
-- =====================================================================
insert into public.settings (key, value, note) values
  ('circle_feed_km', 30, 'מעגלים מוצגים רק בטווח הזה מהשחקן')
on conflict (key) do nothing;

create or replace function public.circle_feed(p_lat float8 default null, p_lng float8 default null, p_spot text default null)
returns table (id uuid, spot_id text, spot_short text, spot_kind text, sport text, organizer_nick text,
               size int, members int, starts_label text, open_to_all boolean, court_info text, status text,
               avg_level numeric, avg_label text, match int, minutes int, i_am_in boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  with c as (
    select c.*, s.short, s.kind, s.lat, s.lng from circles c join spots s on s.id = c.spot_id
    where c.status in ('open','full')
      and c.created_at > now() - make_interval(mins => setting('circle_ttl_minutes')::int)
      and (p_spot is null or c.spot_id = p_spot)
      and (p_spot is not null or p_lat is null
           or km_between(p_lat, p_lng, s.lat, s.lng) <= setting('circle_feed_km')
           or exists (select 1 from circle_members m where m.circle_id = c.id and m.user_id = auth.uid())
           or exists (select 1 from circle_members m join crew cr on cr.friend = m.user_id
                      where m.circle_id = c.id and cr.user_id = auth.uid()))),
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

-- זהה לגרסה ב-schema.sql, רק עם lat/lng של המקום
create or replace function public.circle_detail(p_circle uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'id', c.id, 'sport', c.sport, 'size', c.size, 'starts_label', c.starts_label,
    'open_to_all', c.open_to_all, 'court_info', c.court_info, 'status', c.status,
    'created_at', c.created_at, 'organizer', c.organizer,
    'spot', json_build_object('id', s.id, 'name', s.name, 'short', s.short, 'kind', s.kind, 'lat', s.lat, 'lng', s.lng),
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
