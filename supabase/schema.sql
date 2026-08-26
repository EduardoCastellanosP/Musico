-- VallenatoConnect — esquema de base de datos
-- Ejecutar en el SQL Editor de Supabase (o vía `supabase db push`).
-- Requiere la extensión pgcrypto para gen_random_uuid() (habilitada por defecto en Supabase).

-- =========================================================
-- 1. Tabla `profiles`
-- =========================================================
create table if not exists public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  full_name          text not null default '',
  city               text not null default '',
  experience_years   integer not null default 0 check (experience_years >= 0),
  rating             numeric(2, 1) not null default 5.0 check (rating >= 0 and rating <= 5),
  reviews_count      integer not null default 0 check (reviews_count >= 0),
  is_free            boolean not null default true,
  status_message     text not null default '' check (char_length(status_message) <= 120),
  available_from     text not null default '08:00', -- formato 24h "HH:mm"
  available_to       text not null default '22:00',  -- formato 24h "HH:mm"
  phone              text not null default '',
  avatar_url         text,
  coverage_cities    text[] not null default '{}',
  busy_until         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.profiles is 'Directorio público de músicos vallenatos. Cada fila está vinculada 1:1 con auth.users.';
comment on column public.profiles.coverage_cities is 'Municipios adicionales donde el músico se desplaza a tocar, más allá de su ciudad base (`city`).';
comment on column public.profiles.busy_until is 'Fin programado de la ocupación actual (franja "ocupado hasta"); usado por el asistente de check-out automático. Null cuando el músico está libre o no definió una hora límite.';

-- Columnas añadidas después del lanzamiento inicial: reintentables en bases
-- de datos que ya tenían `profiles` creada antes de que existieran.
alter table public.profiles
  add column if not exists coverage_cities text[] not null default '{}';

alter table public.profiles
  add column if not exists busy_until timestamptz;

-- =========================================================
-- 1.1 Selección múltiple: instrumentos, géneros y servicios
-- Reemplaza las columnas escalares `instrument`/`genre` por arreglos, y
-- añade `services` para que un músico pueda ofrecerse como "Músico",
-- "Sonido", "Ensayaderos", etc. al mismo tiempo. `service_description` es el
-- inventario/descripción libre para servicios técnicos (sonido, ensayadero,
-- ...); `availability_note` es la franja horaria habitual que el músico
-- describe mientras está "libre" (cuando está "ocupado" se usan en cambio
-- `available_from`/`available_to`, ya existentes, como el rango exacto de la
-- jornada actual).
-- =========================================================
alter table public.profiles
  add column if not exists instruments text[] not null default '{}';

alter table public.profiles
  add column if not exists genres text[] not null default '{}';

alter table public.profiles
  add column if not exists services text[] not null default '{}';

alter table public.profiles
  add column if not exists service_description text not null default '';

alter table public.profiles
  add column if not exists availability_note text not null default '';

-- Backfill único: copia los valores escalares existentes a los nuevos
-- arreglos antes de retirar las columnas viejas `instrument`/`genre`. El
-- bloque completo es un no-op seguro en instalaciones nuevas, donde esas
-- columnas nunca existieron.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'instrument'
  ) then
    update public.profiles
    set instruments = array[instrument]
    where coalesce(instrument, '') <> '' and instruments = '{}';

    update public.profiles
    set services = array['Músico']
    where services = '{}' and coalesce(instrument, '') <> '';

    alter table public.profiles drop column instrument;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'genre'
  ) then
    update public.profiles
    set genres = array[genre]
    where coalesce(genre, '') <> '' and genres = '{}';

    update public.profiles
    set services = array['Músico']
    where services = '{}' and coalesce(genre, '') <> '';

    alter table public.profiles drop constraint if exists profiles_genre_check;
    alter table public.profiles drop column genre;
  end if;
end $$;

comment on column public.profiles.instruments is 'Instrumentos que toca el músico (selección múltiple). Vacío si solo ofrece servicios técnicos.';
comment on column public.profiles.genres is 'Géneros musicales que interpreta (selección múltiple).';
comment on column public.profiles.services is 'Servicios ofrecidos: "Músico", "Sonido", "Ensayaderos", etc. (selección múltiple).';
comment on column public.profiles.service_description is 'Inventario/descripción libre de servicios técnicos (sonido, ensayadero, ...).';
comment on column public.profiles.availability_note is 'Franja horaria habitual descrita en texto libre mientras el músico está "libre".';

-- =========================================================
-- 1.2 Índices para los filtros multinivel del directorio
-- GIN para los `.contains()`/`cs` que dispara cada chip de instrumento,
-- género o servicio, y para la cláusula `coverage_cities.cs.{"..."}` del
-- filtro geográfico "Cercanías"; btree para el `city.eq.` que lo acompaña.
-- =========================================================
create index if not exists profiles_instruments_gin_idx
  on public.profiles using gin (instruments);

create index if not exists profiles_genres_gin_idx
  on public.profiles using gin (genres);

create index if not exists profiles_services_gin_idx
  on public.profiles using gin (services);

create index if not exists profiles_coverage_cities_gin_idx
  on public.profiles using gin (coverage_cities);

create index if not exists profiles_city_idx
  on public.profiles (city);

-- =========================================================
-- 1.3 Multimedia del perfil: fotos y videos
-- Reemplaza la tabla relacional `musician_photos` (sección 3, más abajo)
-- como fuente de verdad para el portafolio: `photos`/`videos` viven
-- directamente en `profiles`, igual que `instruments`/`genres`/`services`,
-- que ya siguen este mismo patrón de arreglo. `musician_photos` se deja
-- intacta (no se borra) para no perder datos existentes; el backfill de
-- abajo la copia una sola vez a `photos` y de ahí en adelante la app solo
-- lee/escribe `profiles.photos`. Los CHECK de abajo son la contraparte en
-- base de datos de los límites de la UI (10 fotos / 3 videos): la UI ya los
-- valida antes de subir nada, pero el CHECK es lo que garantiza el límite
-- de verdad, sin importar qué cliente esté escribiendo.
-- =========================================================
alter table public.profiles
  add column if not exists photos text[] not null default '{}';

alter table public.profiles
  add column if not exists videos text[] not null default '{}';

-- Timestamp of the musician's most recent portfolio upload (photo or
-- video) — drives the dashboard's WhatsApp/Instagram-style "story ring"
-- around a card's avatar. Bumped by `add_profile_photo` below and by the
-- `musician_videos_bump_last_media` trigger (section 11) since videos are
-- inserted directly into `musician_videos`, not through an RPC.
alter table public.profiles
  add column if not exists last_media_at timestamptz;

-- Public header/background photo behind the avatar on the profile detail
-- screen — same `avatars` Storage bucket as `avatar_url`, just a different
-- filename prefix (see `MusicianRepository.updateCover`). Null falls back
-- to a themed gradient placeholder client-side.
alter table public.profiles
  add column if not exists cover_url text;

alter table public.profiles drop constraint if exists profiles_photos_max_10;
alter table public.profiles add constraint profiles_photos_max_10
  check (array_length(photos, 1) is null or array_length(photos, 1) <= 10);

alter table public.profiles drop constraint if exists profiles_videos_max_3;
alter table public.profiles add constraint profiles_videos_max_3
  check (array_length(videos, 1) is null or array_length(videos, 1) <= 3);

comment on column public.profiles.photos is 'Hasta 10 URLs públicas del bucket `musician-photos`, portafolio visible en el directorio.';
comment on column public.profiles.videos is 'DEPRECADA (histórica): superseded por la tabla relacional `musician_videos` (sección 11) — el conteo de vistas por video no es representable en un arreglo plano. Se conserva sin borrar como respaldo de lo ya migrado por el backfill de la sección 11.';

-- Backfill único desde `musician_photos`: solo corre mientras `photos` siga
-- vacío para un perfil dado, así que es seguro volver a ejecutar este
-- script completo sin duplicar nada.
update public.profiles p
set photos = coalesce(
  (
    select array_agg(mp.image_url order by mp.created_at desc)
    from public.musician_photos mp
    where mp.musician_id = p.id
  ),
  '{}'
)
where p.photos = '{}'
  and exists (select 1 from public.musician_photos mp where mp.musician_id = p.id);

-- Añadir/quitar un elemento vía RPC en lugar de un `.update()` directo
-- desde PostgREST es lo que permite una mutación atómica de tipo
-- "append"/"remove" sobre el arreglo (PostgREST solo puede *reemplazar* una
-- columna completa, no expresar `array_append`/`array_remove`), y es lo que
-- hace valer el CHECK de arriba ante ediciones concurrentes desde dos
-- dispositivos a la vez. `add_profile_video`/`remove_profile_video` quedan
-- abajo por compatibilidad histórica, pero DEPRECADAS: la app ya no las
-- llama — ver sección 11 para el reemplazo relacional.
create or replace function public.add_profile_photo(photo_url text)
returns void
language plpgsql
security invoker
as $$
begin
  update public.profiles
  set photos = array_append(photos, photo_url),
      last_media_at = now()
  where id = auth.uid();

  if not found then
    raise exception 'No hay una sesión activa o el perfil no existe.';
  end if;
end;
$$;

create or replace function public.remove_profile_photo(photo_url text)
returns void
language plpgsql
security invoker
as $$
begin
  update public.profiles
  set photos = array_remove(photos, photo_url)
  where id = auth.uid();
end;
$$;

create or replace function public.add_profile_video(video_url text)
returns void
language plpgsql
security invoker
as $$
begin
  update public.profiles
  set videos = array_append(videos, video_url)
  where id = auth.uid();

  if not found then
    raise exception 'No hay una sesión activa o el perfil no existe.';
  end if;
end;
$$;

create or replace function public.remove_profile_video(video_url text)
returns void
language plpgsql
security invoker
as $$
begin
  update public.profiles
  set videos = array_remove(videos, video_url)
  where id = auth.uid();
end;
$$;

grant execute on function public.add_profile_photo(text) to authenticated;
grant execute on function public.remove_profile_photo(text) to authenticated;
grant execute on function public.add_profile_video(text) to authenticated;
grant execute on function public.remove_profile_video(text) to authenticated;

-- =========================================================
-- 2. Tabla `contact_events`
-- Registra cada vez que alguien contacta a un músico (WhatsApp/llamada),
-- usada para alimentar el panel de estadísticas de "Mi Estado".
-- =========================================================
create table if not exists public.contact_events (
  id            uuid primary key default gen_random_uuid(),
  musician_id   uuid not null references public.profiles (id) on delete cascade,
  contact_type  text not null check (contact_type in ('whatsapp', 'call')),
  created_at    timestamptz not null default now()
);

create index if not exists contact_events_musician_id_created_at_idx
  on public.contact_events (musician_id, created_at desc);

-- =========================================================
-- 3. Tabla `musician_photos` (histórica/deprecada)
-- Superseded por `profiles.photos` (sección 1.3): la app ya no lee ni
-- escribe esta tabla. Se conserva sin borrar únicamente como respaldo de
-- los datos ya migrados por el backfill de la sección 1.3 — se puede
-- eliminar en una limpieza futura una vez confirmada la migración.
-- =========================================================
create table if not exists public.musician_photos (
  id            uuid primary key default gen_random_uuid(),
  musician_id   uuid not null references public.profiles (id) on delete cascade,
  image_url     text not null,
  created_at    timestamptz not null default now()
);

create index if not exists musician_photos_musician_id_created_at_idx
  on public.musician_photos (musician_id, created_at desc);

-- =========================================================
-- 4. updated_at automático en `profiles`
-- =========================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

-- =========================================================
-- 5. Auto-creación de perfil al registrarse (auth.users -> profiles)
-- =========================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      'Nuevo Músico'
    ),
    coalesce(new.phone, ''),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- =========================================================
-- 6. Row Level Security
-- =========================================================
alter table public.profiles enable row level security;
alter table public.contact_events enable row level security;
alter table public.musician_photos enable row level security;

-- Cualquier usuario autenticado puede leer el directorio completo.
drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
  on public.profiles
  for select
  to authenticated
  using (true);

-- Solo el dueño del registro puede modificar su propio perfil/estado.
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Respaldo por si se necesita insertar el perfil desde el cliente
-- (normalmente lo hace el trigger `handle_new_user`).
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles
  for insert
  to authenticated
  with check (auth.uid() = id);

-- Cualquier usuario autenticado puede registrar que contactó a un músico.
drop policy if exists "contact_events_insert_authenticated" on public.contact_events;
create policy "contact_events_insert_authenticated"
  on public.contact_events
  for insert
  to authenticated
  with check (true);

-- Solo el músico dueño puede leer sus propias estadísticas de contacto.
drop policy if exists "contact_events_select_own" on public.contact_events;
create policy "contact_events_select_own"
  on public.contact_events
  for select
  to authenticated
  using (auth.uid() = musician_id);

-- Cualquiera (organizadores incluidos) puede ver el portafolio de fotos.
drop policy if exists "musician_photos_select_authenticated" on public.musician_photos;
create policy "musician_photos_select_authenticated"
  on public.musician_photos
  for select
  to authenticated
  using (true);

-- Solo el músico dueño puede subir fotos a su propio portafolio.
drop policy if exists "musician_photos_insert_own" on public.musician_photos;
create policy "musician_photos_insert_own"
  on public.musician_photos
  for insert
  to authenticated
  with check (auth.uid() = musician_id);

-- Solo el músico dueño puede borrar sus propias fotos.
drop policy if exists "musician_photos_delete_own" on public.musician_photos;
create policy "musician_photos_delete_own"
  on public.musician_photos
  for delete
  to authenticated
  using (auth.uid() = musician_id);

-- =========================================================
-- 7. Storage: bucket `musician-photos`
-- Bucket público (lectura) para las imágenes del portafolio; la escritura
-- está restringida al propio músico vía el prefijo de carpeta `{uid}/...`.
-- =========================================================
insert into storage.buckets (id, name, public)
values ('musician-photos', 'musician-photos', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "musician_photos_storage_select" on storage.objects;
create policy "musician_photos_storage_select"
  on storage.objects
  for select
  to public
  using (bucket_id = 'musician-photos');

drop policy if exists "musician_photos_storage_insert" on storage.objects;
create policy "musician_photos_storage_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'musician-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "musician_photos_storage_delete" on storage.objects;
create policy "musician_photos_storage_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'musician-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- =========================================================
-- 8. Búsqueda global: nombre, ciudad, cobertura, instrumentos, géneros y
-- servicios
-- Usada por `MusicianRepository.fetchMusicians` cuando hay un término de
-- búsqueda: PostgREST permite seguir filtrando (instrumento, género,
-- servicio, solo libres, cercanía geográfica) y ordenando sobre el
-- resultado de esta función, igual que si fuera un `select()` normal.
-- =========================================================
create or replace function public.search_musicians(search_term text)
returns setof public.profiles
language sql
stable
as $$
  select p.*
  from public.profiles p
  where
    search_term is null or btrim(search_term) = ''
    or p.full_name ilike '%' || search_term || '%'
    or p.city ilike '%' || search_term || '%'
    or exists (
      select 1 from unnest(p.coverage_cities) as covered_city
      where covered_city ilike '%' || search_term || '%'
    )
    or exists (
      select 1 from unnest(p.instruments) as instrument
      where instrument ilike '%' || search_term || '%'
    )
    or exists (
      select 1 from unnest(p.genres) as genre
      where genre ilike '%' || search_term || '%'
    )
    or exists (
      select 1 from unnest(p.services) as service
      where service ilike '%' || search_term || '%'
    );
$$;

grant execute on function public.search_musicians(text) to authenticated;

-- =========================================================
-- 9. Realtime
-- Habilita cambios en vivo sobre `profiles` para el contador de
-- "músicos disponibles" del dashboard.
-- =========================================================
-- alter publication supabase_realtime add table public.profiles;

-- =========================================================
-- 10. Auto-eliminación de cuenta
-- Permite borrar la propia cuenta desde el cliente sin exponer la
-- service_role key. `security definer` + `search_path` fijo es lo que le da
-- a esta función permiso para tocar `auth.users` (vedado a `authenticated`
-- por defecto); `auth.uid()` dentro del cuerpo garantiza que un usuario solo
-- puede borrarse a sí mismo. El `on delete cascade` ya configurado en
-- `profiles` (-> auth.users), `contact_events` y `musician_photos`
-- (-> profiles) limpia todo lo demás automáticamente; los archivos en
-- Storage (avatar, galería) se borran desde el cliente antes de llamar a
-- esta función, ya que Storage vive fuera del grafo de llaves foráneas.
--
-- El `alter function ... owner to postgres` es la parte que de verdad
-- importa: una función `security definer` corre con los privilegios de su
-- DUEÑO, no de quien la llama. Si el owner terminó siendo un rol sin
-- privilegios sobre el esquema `auth` (posible según cómo se haya
-- ejecutado este script), el `delete from auth.users` falla con
-- "permission denied" — fijar el owner a `postgres` (miembro de
-- `supabase_auth_admin` en todo proyecto Supabase) es lo que lo corrige. El
-- `grant` envuelto en `do $$ ... exception ... $$` es un refuerzo best-effort:
-- normalmente ya innecesario tras el `alter owner`, pero no rompe el script
-- si el rol que lo ejecuta no tiene autoridad para otorgarlo.
-- =========================================================
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'No hay una sesión activa.';
  end if;

  delete from auth.users where id = uid;
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
alter function public.delete_own_account() owner to postgres;

do $$
begin
  grant delete on auth.users to postgres;
exception when others then
  raise notice 'No se pudo otorgar DELETE sobre auth.users a postgres (probablemente ya lo tiene). Continuando...';
end;
$$;

-- =========================================================
-- 11. Multimedia de video: tabla relacional, vistas y storage
-- Reemplaza `profiles.videos` (arreglo plano, sección 1.3, ahora
-- deprecada): un contador de vistas por video no es representable en un
-- arreglo de texto, así que los videos pasan a ser filas propias con su
-- `views_count`. Los videos ahora son archivos subidos al bucket
-- `musician-videos` (comprimidos en el dispositivo antes de subir), no
-- enlaces externos — de ahí que ya no haga falta un `isSupportedVideoUrl`
-- del lado del cliente.
-- =========================================================
create table if not exists public.musician_videos (
  id           uuid primary key default gen_random_uuid(),
  musician_id  uuid not null references public.profiles (id) on delete cascade,
  video_url    text not null,
  views_count  integer not null default 0 check (views_count >= 0),
  created_at   timestamptz not null default now()
);

create index if not exists musician_videos_musician_id_created_at_idx
  on public.musician_videos (musician_id, created_at desc);

comment on table public.musician_videos is 'Portafolio de video de cada músico, hasta 5 por músico (musician_videos_max_3), con conteo de vistas.';

-- Un CHECK no puede contar filas hermanas, así que el límite (a diferencia
-- del de fotos, un simple `array_length <= 10`) se aplica con un trigger —
-- la contraparte en base de datos del bloqueo que ya hace la UI en
-- `MediaManagerCard`/`MediaLimits.maxVideos`.
create or replace function public.enforce_max_videos()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.musician_videos where musician_id = new.musician_id) >= 5 then
    raise exception 'Ya tienes el máximo de 5 videos.';
  end if;
  return new;
end;
$$;

drop trigger if exists musician_videos_max_3 on public.musician_videos;
create trigger musician_videos_max_3
  before insert on public.musician_videos
  for each row
  execute function public.enforce_max_videos();

-- Videos are inserted directly into this table by `MusicianRepository.addVideo`
-- (no RPC in the middle, unlike photos' `add_profile_photo`), so
-- `profiles.last_media_at` needs its own trigger instead of an inline
-- update alongside the insert.
create or replace function public.bump_last_media_at()
returns trigger
language plpgsql
as $$
begin
  update public.profiles set last_media_at = now() where id = new.musician_id;
  return new;
end;
$$;

drop trigger if exists musician_videos_bump_last_media on public.musician_videos;
create trigger musician_videos_bump_last_media
  after insert on public.musician_videos
  for each row
  execute function public.bump_last_media_at();

alter table public.musician_videos enable row level security;

drop policy if exists "musician_videos_select_authenticated" on public.musician_videos;
create policy "musician_videos_select_authenticated"
  on public.musician_videos
  for select
  to authenticated
  using (true);

drop policy if exists "musician_videos_insert_own" on public.musician_videos;
create policy "musician_videos_insert_own"
  on public.musician_videos
  for insert
  to authenticated
  with check (auth.uid() = musician_id);

drop policy if exists "musician_videos_delete_own" on public.musician_videos;
create policy "musician_videos_delete_own"
  on public.musician_videos
  for delete
  to authenticated
  using (auth.uid() = musician_id);

-- Deliberadamente SIN policy de `update` para `authenticated`: la única
-- columna mutable, `views_count`, solo debe cambiar a través de
-- `increment_video_view` (más abajo), nunca por un `.update()` directo
-- desde el cliente — ni siquiera el propio dueño del video.

-- Backfill único desde `profiles.videos`: cada perfil ya estaba limitado a
-- 3 por el CHECK `profiles_videos_max_3`, así que el trigger de arriba
-- nunca debería rechazar estas filas. Solo corre una vez por músico (el
-- `not exists` evita duplicar en reintentos de este script).
insert into public.musician_videos (musician_id, video_url)
select p.id, v.video_url
from public.profiles p
cross join lateral unnest(p.videos) as v(video_url)
where not exists (
  select 1 from public.musician_videos mv where mv.musician_id = p.id
);

-- Log de vistas: una fila por (video, espectador, momento), usado solo
-- para el control anti-spam de `increment_video_view` — no se expone
-- ninguna escritura directa a `authenticated`, todo pasa por esa función.
create table if not exists public.video_view_events (
  id         uuid primary key default gen_random_uuid(),
  video_id   uuid not null references public.musician_videos (id) on delete cascade,
  viewer_id  uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists video_view_events_video_viewer_idx
  on public.video_view_events (video_id, viewer_id, created_at desc);

alter table public.video_view_events enable row level security;

drop policy if exists "video_view_events_select_own" on public.video_view_events;
create policy "video_view_events_select_own"
  on public.video_view_events
  for select
  to authenticated
  using (auth.uid() = viewer_id);

-- Incremento atómico con enfriamiento anti-spam: el mismo espectador
-- viendo el mismo video más de una vez en 30 minutos no vuelve a contar.
-- `security definer` + owner `postgres` (que en Supabase tiene el atributo
-- BYPASSRLS) es lo que le permite escribir en `video_view_events` y
-- `musician_videos.views_count` sin necesitar una policy de `update`
-- pública sobre esa columna — mismo patrón de refuerzo que
-- `delete_own_account` (sección 10).
create or replace function public.increment_video_view(video_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer uuid := auth.uid();
  recent_view_exists boolean;
begin
  if viewer is null then
    raise exception 'No hay una sesión activa.';
  end if;

  select exists (
    select 1 from public.video_view_events e
    where e.video_id = increment_video_view.video_id
      and e.viewer_id = viewer
      and e.created_at > now() - interval '30 minutes'
  ) into recent_view_exists;

  if recent_view_exists then
    return;
  end if;

  insert into public.video_view_events (video_id, viewer_id) values (video_id, viewer);

  update public.musician_videos
  set views_count = views_count + 1
  where id = video_id;
end;
$$;

grant execute on function public.increment_video_view(uuid) to authenticated;
alter function public.increment_video_view(uuid) owner to postgres;

-- Storage: bucket `musician-videos`, mismo patrón que `musician-photos`
-- (lectura pública, escritura restringida al propio músico vía el
-- prefijo de carpeta `{uid}/...`).
insert into storage.buckets (id, name, public)
values ('musician-videos', 'musician-videos', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "musician_videos_storage_select" on storage.objects;
create policy "musician_videos_storage_select"
  on storage.objects
  for select
  to public
  using (bucket_id = 'musician-videos');

drop policy if exists "musician_videos_storage_insert" on storage.objects;
create policy "musician_videos_storage_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'musician-videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "musician_videos_storage_delete" on storage.objects;
create policy "musician_videos_storage_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'musician-videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- =========================================================
-- 12. Likes y follows del feed de videos
-- Ambas tablas solo exponen las filas del propio usuario a `select` — ni
-- un conteo agregado ni "quién más le dio like" son necesarios todavía, así
-- que no hace falta abrir lectura pública. `VideoFeedScreen` hace una sola
-- consulta por lote (`in`) al cargar la página para saber cuáles de los
-- videos/músicos visibles ya tienen like/follow del usuario actual, y
-- aplica un toggle optimista en el cliente antes de esperar la respuesta.
-- =========================================================
create table if not exists public.video_likes (
  video_id    uuid not null references public.musician_videos (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (video_id, user_id)
);

alter table public.video_likes enable row level security;

drop policy if exists "video_likes_select_own" on public.video_likes;
create policy "video_likes_select_own"
  on public.video_likes
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "video_likes_insert_own" on public.video_likes;
create policy "video_likes_insert_own"
  on public.video_likes
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "video_likes_delete_own" on public.video_likes;
create policy "video_likes_delete_own"
  on public.video_likes
  for delete
  to authenticated
  using (auth.uid() = user_id);

create table if not exists public.musician_follows (
  follower_id  uuid not null references auth.users (id) on delete cascade,
  musician_id  uuid not null references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (follower_id, musician_id),
  check (follower_id <> musician_id)
);

alter table public.musician_follows enable row level security;

drop policy if exists "musician_follows_select_own" on public.musician_follows;
create policy "musician_follows_select_own"
  on public.musician_follows
  for select
  to authenticated
  using (auth.uid() = follower_id);

drop policy if exists "musician_follows_insert_own" on public.musician_follows;
create policy "musician_follows_insert_own"
  on public.musician_follows
  for insert
  to authenticated
  with check (auth.uid() = follower_id);

drop policy if exists "musician_follows_delete_own" on public.musician_follows;
create policy "musician_follows_delete_own"
  on public.musician_follows
  for delete
  to authenticated
  using (auth.uid() = follower_id);