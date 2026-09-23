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

-- YouTube fue retirado por completo de la app (ver sección 16 más abajo:
-- ahora el video es 100% Supabase Storage y los perfiles enlazan sus
-- redes sociales en su lugar).
alter table public.profiles drop column if exists youtube_channel;

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

-- "Thumbnail first": una miniatura JPEG liviana que VideoFeedScreen puede
-- mostrar de inmediato mientras decide si vale la pena empezar a
-- descargar el video real (pesado) para esa página. Nullable porque los
-- videos subidos antes de este cambio no tienen una.
alter table public.musician_videos add column if not exists thumbnail_url text;

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

-- Allows a user to read both "who I follow" (follower_id = me) and
-- "who follows me" (musician_id = me) — without the second half, a
-- musician's own followers_count query can never see rows where someone
-- else follows them, so it always reads back as 0.
drop policy if exists "musician_follows_select_own" on public.musician_follows;
create policy "musician_follows_select_own"
  on public.musician_follows
  for select
  to authenticated
  using (auth.uid() = follower_id or auth.uid() = musician_id);

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

-- =========================================================
-- 12. Listados públicos de seguidores / likes
-- La app es un directorio público: cualquier usuario autenticado puede
-- abrir la lista de seguidores o de "me gusta" de CUALQUIER músico (no solo
-- la propia), a diferencia de las políticas RLS de arriba (que solo dejan
-- ver tus propias filas). `security definer` es lo que permite a estas
-- funciones saltarse esa restricción de forma controlada: solo exponen las
-- columnas de perfil (id, nombre, avatar) que ya son públicas en el
-- directorio, nunca las tablas base completas.
-- =========================================================
create or replace function public.get_musician_followers(target_musician_id uuid)
returns table (id uuid, full_name text, avatar_url text, followed_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.avatar_url, mf.created_at as followed_at
  from public.musician_follows mf
  join public.profiles p on p.id = mf.follower_id
  where mf.musician_id = target_musician_id
  order by mf.created_at desc;
$$;

grant execute on function public.get_musician_followers(uuid) to authenticated;

create or replace function public.get_video_likers(target_musician_id uuid)
returns table (id uuid, full_name text, avatar_url text, liked_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.avatar_url, max(vl.created_at) as liked_at
  from public.video_likes vl
  join public.musician_videos mv on mv.id = vl.video_id
  join public.profiles p on p.id = vl.user_id
  where mv.musician_id = target_musician_id
  group by p.id, p.full_name, p.avatar_url
  order by liked_at desc;
$$;

grant execute on function public.get_video_likers(uuid) to authenticated;

-- =========================================================
-- 13. Completitud de perfil: revertida — la lectura es abierta
-- Un intento anterior de esta sección bloqueaba la LECTURA (`fetchMusicians`/
-- `fetchVideoFeed`) de cualquier perfil sin ciudad+teléfono+servicio+foto+
-- video, vía una columna `is_complete` recalculada por trigger. El
-- problema: eso escondía a TODOS los músicos (incluidos los ya completos)
-- de cualquiera cuyo propio perfil aún no cumpliera esos requisitos —
-- volviendo el directorio inutilizable para cuentas nuevas.
--
-- La regla de completitud correcta solo aplica en ESCRITURA: bloquear el
-- botón "Guardar cambios" hasta que el perfil propio esté completo (ver
-- `StatusScreen._validate` en Flutter, 100% cliente) y, por separado,
-- bloquear el botón de contactar a OTRO músico hasta que el perfil propio
-- lo esté (ver `MusicianRepository.currentProfileCanContact` /
-- `Musician.hasCompleteProfile`, también client-side). Ninguna de las dos
-- necesita un flag en la base de datos, así que esta sección solo deshace
-- lo que la anterior creó — reintentable si ya se corrió antes.
-- =========================================================
drop trigger if exists profiles_recompute_complete on public.profiles;
drop trigger if exists musician_videos_recompute_complete on public.musician_videos;
drop function if exists public.profiles_recompute_complete();
drop function if exists public.musician_videos_recompute_owner_complete();
drop function if exists public.recompute_profile_complete(uuid);
alter table public.profiles drop column if exists is_complete;

-- =========================================================
-- 14. Chat interno
-- Reemplaza la exposición directa de número de teléfono/WhatsApp en el
-- directorio (ver `musician_detail_screen.dart`): el contacto ahora pasa por
-- un chat 1:1 dentro de la app. `conversations` guarda un par de
-- participantes (orden normalizado por el CHECK de abajo para que el par
-- {A,B} nunca se duplique en ambos sentidos); `messages` cuelga de una
-- conversación. `message_type` distingue el texto normal de los mensajes
-- especiales que ChatScreen/ShareContactModal insertan cuando un músico
-- decide compartir su WhatsApp o su número para llamadas dentro del chat.
-- =========================================================
create table if not exists public.conversations (
  id               uuid primary key default gen_random_uuid(),
  participant1_id  uuid not null references auth.users (id) on delete cascade,
  participant2_id  uuid not null references auth.users (id) on delete cascade,
  created_at       timestamptz not null default now(),
  constraint conversations_distinct_participants check (participant1_id <> participant2_id),
  constraint conversations_ordered_participants check (participant1_id < participant2_id),
  constraint conversations_unique_pair unique (participant1_id, participant2_id)
);

comment on table public.conversations is 'Conversación 1:1 entre un contratante y un músico. participant1_id/participant2_id se guardan en orden (menor uuid primero) para que el par nunca se duplique.';

create index if not exists conversations_participant1_idx on public.conversations (participant1_id);
create index if not exists conversations_participant2_idx on public.conversations (participant2_id);

-- Abre (o reutiliza) la conversación entre el usuario actual y `other_user_id`.
-- `security invoker` + normalización del orden es lo que hace que dos
-- llamadas simétricas (A abre con B, B abre con A) siempre resuelvan a la
-- misma fila en vez de crear un duplicado.
create or replace function public.get_or_create_conversation(other_user_id uuid)
returns uuid
language plpgsql
security invoker
as $$
declare
  me uuid := auth.uid();
  p1 uuid;
  p2 uuid;
  conversation_id uuid;
begin
  if me is null then
    raise exception 'No hay una sesión activa.';
  end if;
  if me = other_user_id then
    raise exception 'No puedes iniciar una conversación contigo mismo.';
  end if;

  if me < other_user_id then
    p1 := me;
    p2 := other_user_id;
  else
    p1 := other_user_id;
    p2 := me;
  end if;

  insert into public.conversations (participant1_id, participant2_id)
  values (p1, p2)
  on conflict (participant1_id, participant2_id) do nothing;

  select id into conversation_id
  from public.conversations
  where participant1_id = p1 and participant2_id = p2;

  return conversation_id;
end;
$$;

grant execute on function public.get_or_create_conversation(uuid) to authenticated;

create table if not exists public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id       uuid not null references auth.users (id) on delete cascade,
  content         text not null check (char_length(btrim(content)) > 0),
  message_type    text not null default 'text'
                    check (message_type in ('text', 'whatsapp_share', 'call_share')),
  created_at      timestamptz not null default now()
);

comment on table public.messages is 'Mensajes de un chat interno. message_type = whatsapp_share/call_share marca los mensajes especiales con los que un músico decide compartir su contacto directo dentro del chat; content trae el link https://wa.me/... o tel:... completo.';

-- Migra bases de datos donde esta sección ya se había corrido con la forma
-- anterior (`is_whatsapp_reveal boolean`) antes de introducir
-- `message_type`: el CREATE TABLE de arriba no toca una tabla que ya
-- existe, así que sin esto el INSERT desde ChatRepository falla contra una
-- columna que no existe en el `messages` real.
alter table public.messages drop column if exists is_whatsapp_reveal;
alter table public.messages add column if not exists message_type text not null default 'text';
do $$
begin
  alter table public.messages
    add constraint messages_message_type_check
    check (message_type in ('text', 'whatsapp_share', 'call_share'));
exception
  when duplicate_object then null;
end $$;

create index if not exists messages_conversation_id_created_at_idx
  on public.messages (conversation_id, created_at);

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

-- Un usuario solo ve las conversaciones donde participa.
drop policy if exists "conversations_select_participant" on public.conversations;
create policy "conversations_select_participant"
  on public.conversations
  for select
  to authenticated
  using (auth.uid() = participant1_id or auth.uid() = participant2_id);

-- Inserción directa disponible como respaldo de `get_or_create_conversation`;
-- exige que quien inserta sea uno de los dos participantes.
drop policy if exists "conversations_insert_participant" on public.conversations;
create policy "conversations_insert_participant"
  on public.conversations
  for insert
  to authenticated
  with check (auth.uid() = participant1_id or auth.uid() = participant2_id);

-- Solo puede leer mensajes quien participa en la conversación a la que pertenecen.
drop policy if exists "messages_select_participant" on public.messages;
create policy "messages_select_participant"
  on public.messages
  for select
  to authenticated
  using (
    exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id
        and (c.participant1_id = auth.uid() or c.participant2_id = auth.uid())
    )
  );

-- Solo puede insertar mensajes, como sí mismo, quien participa en la conversación.
drop policy if exists "messages_insert_participant" on public.messages;
create policy "messages_insert_participant"
  on public.messages
  for insert
  to authenticated
  with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id
        and (c.participant1_id = auth.uid() or c.participant2_id = auth.uid())
    )
  );

-- Habilita Realtime (postgres_changes) sobre `messages` para que ChatScreen
-- reciba mensajes nuevos al instante. `alter publication ... add table` no
-- admite "if not exists", así que el guard va en un DO block para poder
-- re-ejecutar este archivo sin error si ya se había habilitado.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

-- =========================================================
-- 15. WhatsApp público + Consent Audit Trail (LegalTech)
-- `show_whatsapp` deja que un músico opte por exponer su número
-- directamente en `MusicianCard` además del chat interno. Activarlo exige
-- aceptar una exención de responsabilidad — `user_consents` es la prueba
-- legal inmutable (append-only: solo hay policies de insert/select, nunca
-- de update/delete) de que ese consentimiento se dio, para defender a la
-- plataforma si un músico alega que "nunca aceptó" hacer público su
-- contacto o asumir la responsabilidad de tratos externos.
-- =========================================================
alter table public.profiles add column if not exists show_whatsapp boolean not null default false;

create table if not exists public.user_consents (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  consent_type     text not null,
  accepted_version text not null,
  created_at       timestamptz not null default timezone('utc'::text, now())
);

comment on table public.user_consents is 'Registro legal inmutable (append-only) de consentimientos aceptados, p. ej. la exención de responsabilidad al hacer público el WhatsApp (consent_type = ''whatsapp_public_liability_waiver''). Sin policies de update/delete a propósito: es prueba de auditoría, no debe poder editarse ni borrarse.';

create index if not exists user_consents_user_id_idx on public.user_consents (user_id);

alter table public.user_consents enable row level security;

drop policy if exists "Users can insert their own consent logs" on public.user_consents;
create policy "Users can insert their own consent logs"
  on public.user_consents
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can view their own consent logs" on public.user_consents;
create policy "Users can view their own consent logs"
  on public.user_consents
  for select
  to authenticated
  using (auth.uid() = user_id);

-- Inserta el consentimiento y activa `show_whatsapp` en una sola
-- transacción (el cuerpo de una función plpgsql es atómico): si cualquiera
-- de los dos pasos falla, Postgres revierte ambos, así nunca queda
-- `show_whatsapp = true` sin su prueba de consentimiento correspondiente.
-- Apagarlo de vuelta no requiere este RPC — es un `update` directo desde
-- el cliente, ya cubierto por la policy "profiles_update_own" de arriba.
create or replace function public.accept_whatsapp_public_consent()
returns void
language plpgsql
security invoker
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'No hay una sesión activa.';
  end if;

  insert into public.user_consents (user_id, consent_type, accepted_version)
  values (me, 'whatsapp_public_liability_waiver', '1.0');

  update public.profiles set show_whatsapp = true where id = me;
end;
$$;

grant execute on function public.accept_whatsapp_public_consent() to authenticated;

-- =========================================================
-- 16. Redes sociales (reemplaza YouTube)
-- YouTube se retiró por completo del proyecto (ver la columna
-- `youtube_channel` eliminada en la sección 1): el video ahora vive
-- exclusivamente en el bucket `musician-videos` de Supabase Storage. En su
-- lugar, un músico puede enlazar sus perfiles públicos de Facebook,
-- Instagram y TikTok, mostrados como íconos condicionales en su tarjeta de
-- perfil.
-- =========================================================
alter table public.profiles add column if not exists facebook_url text;
alter table public.profiles add column if not exists instagram_url text;
alter table public.profiles add column if not exists tiktok_url text;

comment on column public.profiles.facebook_url is 'Enlace público al perfil/página de Facebook del músico. Null/vacío = no se muestra el ícono en ProfileHeader.';
comment on column public.profiles.instagram_url is 'Enlace público al perfil de Instagram del músico. Null/vacío = no se muestra el ícono en ProfileHeader.';
comment on column public.profiles.tiktok_url is 'Enlace público al perfil de TikTok del músico. Null/vacío = no se muestra el ícono en ProfileHeader.';

-- =========================================================
-- 19. Calificación de `provider_services`
-- Mismo patrón (columna + default + CHECK) que `profiles.rating`/
-- `reviews_count` — ClientHomeScreen's "★ 4.9 (87)" necesita un valor real
-- de la base de datos, no un número inventado en el cliente. No hay todavía
-- flujo de reseñas que las escriba; ambas quedan en su default hasta que
-- exista uno, momento en el que se actualizarían vía RPC (mismo motivo que
-- `profiles.rating` nunca se edita con un `update()` directo).
-- =========================================================
alter table public.provider_services
  add column if not exists rating numeric(2, 1) not null default 5.0 check (rating >= 0 and rating <= 5);

alter table public.provider_services
  add column if not exists reviews_count integer not null default 0 check (reviews_count >= 0);

-- =========================================================
-- 17. `provider_services` — el "Puente" entre Backstage y Tarima
-- Un músico ya tiene su perfil social en `profiles`; esta tabla es su
-- perfil COMERCIAL por separado (una agrupación, un solista, sonido, DJ,
-- ensayadero...), pensado para lo que ve un cliente final en la Tarima.
-- Nace en `pending_review`: un admin lo aprueba antes de listarlo público.
-- No hay tabla puente hacia `musician_videos` — se unen por `user_id` /
-- `musician_id` (ambos apuntan a `profiles.id`), así el portafolio de
-- video que el músico ya sube al Feed Comunitario aparece automáticamente
-- en su perfil comercial sin duplicar filas ni sincronizar nada.
-- =========================================================
create table if not exists public.provider_services (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  category        text not null check (category in ('Agrupación', 'Solista', 'DJ', 'Sonido', 'Ensayadero')),
  business_name   text not null check (char_length(btrim(business_name)) > 0),
  description     text not null default '',
  price_per_hour  numeric(10, 2) check (price_per_hour is null or price_per_hour >= 0),
  status          text not null default 'pending_review'
                    check (status in ('pending_review', 'approved', 'rejected')),
  cover_photos    text[] not null default '{}',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.provider_services is 'Perfil de servicio comercial de un músico/agrupación, visible en la Tarima (marketplace) una vez aprobado. Su portafolio de video se lee por join contra `musician_videos.musician_id = provider_services.user_id`, no por FK propia.';

-- Insignia de verificado, mostrada en la Tarima una vez el panel de
-- moderación aprueba el servicio — ver sección 18. Separada de `status`
-- porque un admin podría en teoría aprobar sin verificar (badge manual),
-- aunque hoy `updateServiceStatus` siempre los pone en el mismo paso.
alter table public.provider_services add column if not exists is_verified boolean not null default false;

create index if not exists provider_services_user_id_idx on public.provider_services (user_id);
create index if not exists provider_services_status_idx on public.provider_services (status);

drop trigger if exists provider_services_set_updated_at on public.provider_services;
create trigger provider_services_set_updated_at
  before update on public.provider_services
  for each row
  execute function public.set_updated_at();

alter table public.provider_services enable row level security;

-- La Tarima es pública: cualquier autenticado puede ver servicios ya
-- aprobados; el dueño además puede ver los suyos en cualquier estado
-- (para revisar su propio `pending_review`/`rejected` en "Mis servicios").
drop policy if exists "provider_services_select" on public.provider_services;
create policy "provider_services_select"
  on public.provider_services
  for select
  to authenticated
  using (status = 'approved' or auth.uid() = user_id);

drop policy if exists "provider_services_insert_own" on public.provider_services;
create policy "provider_services_insert_own"
  on public.provider_services
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "provider_services_update_own" on public.provider_services;
create policy "provider_services_update_own"
  on public.provider_services
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "provider_services_delete_own" on public.provider_services;
create policy "provider_services_delete_own"
  on public.provider_services
  for delete
  to authenticated
  using (auth.uid() = user_id);

-- Vista de lectura para la Tarima: un servicio aprobado junto con el
-- portafolio de video que su dueño ya subió al Feed Comunitario. El join es
-- por `user_id = musician_id` — el mismo `profiles.id` en ambos mundos —,
-- así que un video nuevo en `musician_videos` aparece aquí sin tocar esta
-- vista ni `provider_services` para nada.
-- Columnas listadas explícitamente (nunca `ps.*`): `create or replace view`
-- solo permite AÑADIR columnas al final, nunca insertar una en medio — y
-- `ps.*` desplaza automáticamente todo lo que venga después cada vez que
-- `provider_services` gane una columna nueva por `alter table ... add
-- column` (como `is_verified`, más arriba en esta misma sección), rompiendo el reemplazo con
-- "cannot change name of view column". Enumerar columnas hace ese reemplazo
-- estable para siempre, sin importar cuántas columnas se agreguen después.
drop view if exists public.provider_service_portfolios;
create view public.provider_service_portfolios as
select
  ps.id,
  ps.user_id,
  ps.category,
  ps.business_name,
  ps.description,
  ps.price_per_hour,
  ps.status,
  ps.cover_photos,
  ps.is_verified,
  ps.created_at,
  ps.updated_at,
  coalesce(
    array_agg(mv.video_url order by mv.created_at desc) filter (where mv.id is not null),
    '{}'
  ) as portfolio_video_urls
from public.provider_services ps
left join public.musician_videos mv on mv.musician_id = ps.user_id
group by ps.id;

-- Storage: bucket `service_covers`, mismo patrón que `musician-photos`/
-- `musician-videos` (lectura pública, escritura restringida al propio
-- dueño vía el prefijo de carpeta `{uid}/...`) — usado por
-- `ProviderServiceRepository.uploadCoverPhotos` para las fotos de portada
-- de `provider_services.cover_photos`.
insert into storage.buckets (id, name, public)
values ('service_covers', 'service_covers', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "service_covers_storage_select" on storage.objects;
create policy "service_covers_storage_select"
  on storage.objects
  for select
  to public
  using (bucket_id = 'service_covers');

drop policy if exists "service_covers_storage_insert" on storage.objects;
create policy "service_covers_storage_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'service_covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "service_covers_storage_delete" on storage.objects;
create policy "service_covers_storage_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'service_covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- =========================================================
-- 18. Panel de Moderación (Admin Dashboard)
-- `profiles.is_admin` es el único rol de la app: sin fila propia en una
-- tabla `admins` separada, un simple flag basta porque solo controla la
-- moderación de `provider_services`. Las policies "_own" de la sección 17
-- ya cubren al dueño del servicio; las de abajo son ADICIONALES (RLS
-- combina políticas permisivas del mismo comando con OR), así que un admin
-- ve/edita CUALQUIER fila sin quitarle nada a esas policies existentes.
-- =========================================================
alter table public.profiles add column if not exists is_admin boolean not null default false;

comment on column public.profiles.is_admin is 'Flag manual (activado directamente en la base de datos) para el panel de moderación de provider_services. No hay UI en la app para otorgarlo.';

drop policy if exists "provider_services_select_admin" on public.provider_services;
create policy "provider_services_select_admin"
  on public.provider_services
  for select
  to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );

drop policy if exists "provider_services_update_admin" on public.provider_services;
create policy "provider_services_update_admin"
  on public.provider_services
  for update
  to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  )
  with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );

-- =========================================================
-- 20. KYC / Habeas Data (Ley 1581 de 2012) para `provider_services`
-- `identity_doc_url` guarda la RUTA privada del documento (nunca una URL
-- pública: el bucket `identity_documents` es privado) — el admin la resuelve
-- a una signed URL de corta duración vía
-- `ProviderServiceRepository.getIdentityDocumentSignedUrl`, igual que
-- cualquier objeto de un bucket sin lectura pública.
--
-- Ambas columnas quedan NULLABLE a propósito: son `alter table add column`
-- sobre una tabla que ya puede tener filas de antes de que este flujo KYC
-- existiera (no hay un valor por defecto razonable para "documento" o
-- "fecha de consentimiento" de esas filas viejas), así que un NOT NULL aquí
-- rompería la migración. Lo obligatorio pasa a nivel de aplicación:
-- `CreateServiceModal` bloquea el envío del formulario sin foto de
-- portada, sin documento subido y sin la casilla de Habeas Data marcada.
-- =========================================================
alter table public.provider_services add column if not exists identity_doc_url text;
alter table public.provider_services add column if not exists habeas_data_accepted_at timestamptz;

comment on column public.provider_services.identity_doc_url is 'Ruta privada (no URL pública) del documento de identidad en el bucket `identity_documents`. Solo el dueño y un admin pueden leerlo (RLS de storage.objects abajo).';
comment on column public.provider_services.habeas_data_accepted_at is 'Momento en que el músico aceptó la autorización de tratamiento de datos (Ley 1581 de 2012) al crear ESTE servicio. Ver también el registro de auditoría inmutable en `user_consents` (sección 15), escrito atómicamente junto a esta columna por `create_provider_service_with_consent`.';

-- Storage: bucket PRIVADO `identity_documents` — a diferencia de
-- `service_covers`/`musician-photos`/`musician-videos` (todos públicos en
-- lectura), este nunca expone `to public`. Solo el propio dueño (prefijo de
-- carpeta `{uid}/...`, mismo patrón que los buckets públicos) y un admin
-- (`profiles.is_admin`) pueden leer un objeto.
insert into storage.buckets (id, name, public)
values ('identity_documents', 'identity_documents', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "identity_documents_storage_select_own" on storage.objects;
create policy "identity_documents_storage_select_own"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'identity_documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "identity_documents_storage_select_admin" on storage.objects;
create policy "identity_documents_storage_select_admin"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'identity_documents'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );

drop policy if exists "identity_documents_storage_insert" on storage.objects;
create policy "identity_documents_storage_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'identity_documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "identity_documents_storage_delete_own" on storage.objects;
create policy "identity_documents_storage_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'identity_documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Crea el servicio y su registro de auditoría de Habeas Data en una sola
-- transacción — mismo motivo que `accept_whatsapp_public_consent` (sección
-- 15): si cualquiera de los dos inserts falla, Postgres revierte ambos, así
-- nunca queda un `provider_services.habeas_data_accepted_at` sin su prueba
-- de consentimiento correspondiente en `user_consents`, ni viceversa.
-- `security invoker` basta (a diferencia de esa función): ambos inserts ya
-- están permitidos por las policies "insert_own" existentes de cada tabla
-- para `auth.uid() = user_id`.
create or replace function public.create_provider_service_with_consent(
  category text,
  business_name text,
  description text,
  price_per_hour numeric,
  cover_photos text[],
  identity_doc_url text
)
returns uuid
language plpgsql
security invoker
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then
    raise exception 'No hay una sesión activa.';
  end if;

  insert into public.provider_services (
    user_id, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, habeas_data_accepted_at
  )
  values (
    me, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, now()
  )
  returning id into new_id;

  insert into public.user_consents (user_id, consent_type, accepted_version)
  values (me, 'identity_document_habeas_data', '1.0');

  return new_id;
end;
$$;

grant execute on function public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text
) to authenticated;

-- =========================================================
-- 21. Rol de onboarding ("Soy Cliente" / "Soy Músico / Proveedor")
-- Reemplaza el `selectedRole` session-only que vivía solo en memoria del
-- cliente Flutter (se perdía en cada reinicio de la app, obligando a
-- re-elegir cada vez): ahora es una columna real, así que
-- `RoleSelectionModal` solo se muestra la primera vez (`role is null`) y
-- todo login posterior lee este valor y redirige directo, sin preguntar de
-- nuevo. No tiene relación con `is_admin` (sección 18): un admin salta
-- tanto la elección de rol como su valor, siempre va a
-- AdminDashboardScreen.
-- =========================================================
alter table public.profiles add column if not exists role text;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role is null or role in ('client', 'musician'));

comment on column public.profiles.role is 'Elegido una sola vez en RoleSelectionModal tras el primer login. Null = todavía no eligió (dispara el modal en AuthGate). No requiere policy nueva: profiles_update_own (sección 6) ya permite `auth.uid() = id` en UPDATE.';

-- =========================================================
-- 22. "Artistas Guardados" (favoritos) y "Mis Reservas" del cliente
-- No existe una tabla `services` en este proyecto — el marketplace ya
-- construido (sección 17) es `provider_services`, así que ambas FKs
-- apuntan ahí en vez de a una tabla nueva paralela.
-- =========================================================
create table if not exists public.saved_services (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.profiles (id) on delete cascade,
  service_id  uuid not null references public.provider_services (id) on delete cascade,
  created_at  timestamptz not null default now(),
  constraint saved_services_unique unique (client_id, service_id)
);

comment on table public.saved_services is 'Favoritos de un cliente en la Tarima. `saved_services_unique` evita guardar el mismo servicio dos veces (mismo patrón que `video_likes`, sección 12).';

create index if not exists saved_services_client_id_idx on public.saved_services (client_id, created_at desc);

alter table public.saved_services enable row level security;

drop policy if exists "saved_services_select_own" on public.saved_services;
create policy "saved_services_select_own"
  on public.saved_services
  for select
  to authenticated
  using (auth.uid() = client_id);

drop policy if exists "saved_services_insert_own" on public.saved_services;
create policy "saved_services_insert_own"
  on public.saved_services
  for insert
  to authenticated
  with check (auth.uid() = client_id);

drop policy if exists "saved_services_delete_own" on public.saved_services;
create policy "saved_services_delete_own"
  on public.saved_services
  for delete
  to authenticated
  using (auth.uid() = client_id);

-- =========================================================
-- Reservas — nace en `pending_advance` (esperando que el cliente pague el
-- adelanto); el flujo que la mueve a `confirmed`/`cancelled`/`completed`
-- todavía no existe, así que por ahora solo hay policies de lectura e
-- inserción para el cliente. Dejar listo pero sin construir de más:
-- - Falta una policy de UPDATE para que el cliente cancele su propia
--   reserva pendiente.
-- - Falta una policy de SELECT para que el músico dueño del
--   `provider_services` reservado vea las solicitudes contra su servicio.
-- Ninguna de las dos se agrega todavía porque no hay UI que las use — se
-- añaden en la vista de detalle mencionada en la tarea, junto con el RPC
-- que de verdad mueva el estado tras el pago del adelanto.
-- =========================================================
create table if not exists public.bookings (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.profiles (id) on delete cascade,
  service_id  uuid not null references public.provider_services (id) on delete cascade,
  event_date  timestamptz not null,
  status      text not null default 'pending_advance'
                check (status in ('pending_advance', 'confirmed', 'cancelled', 'completed')),
  created_at  timestamptz not null default now()
);

comment on table public.bookings is 'Solicitudes de contratación de un cliente contra un provider_services. status arranca en pending_advance hasta que el flujo de pago (no construido aún) lo mueva.';

create index if not exists bookings_client_id_idx on public.bookings (client_id, event_date desc);
create index if not exists bookings_service_id_idx on public.bookings (service_id);

alter table public.bookings enable row level security;

drop policy if exists "bookings_select_own" on public.bookings;
create policy "bookings_select_own"
  on public.bookings
  for select
  to authenticated
  using (auth.uid() = client_id);

drop policy if exists "bookings_insert_own" on public.bookings;
create policy "bookings_insert_own"
  on public.bookings
  for insert
  to authenticated
  with check (auth.uid() = client_id);

-- =========================================================
-- 23. Vertical "Ocio & Discotecas"
-- Añade 'Discoteca' a las categorías válidas — en español y capitalizado
-- para seguir la misma convención que el resto de la lista ('Agrupación',
-- 'Solista', 'DJ', 'Sonido', 'Ensayadero'), no el `'nightclub'` en inglés
-- de la tarea. El nombre de constraint (`provider_services_category_check`)
-- es el que Postgres autogenera para un CHECK de una sola columna sin
-- nombre explícito — el mismo que quedó fijado al crear la tabla en la
-- sección 17 — así que hay que reemplazarlo por nombre, no solo añadir uno
-- nuevo.
-- =========================================================
alter table public.provider_services drop constraint if exists provider_services_category_check;
alter table public.provider_services add constraint provider_services_category_check
  check (category in ('Agrupación', 'Solista', 'DJ', 'Sonido', 'Ensayadero', 'Discoteca'));

-- Texto libre y corto para "lo que pasa hoy" en una discoteca (ej. "DJ
-- invitado", "Noche de karaoke") — no existía ningún campo para esto.
-- Nullable: filas ya existentes (y toda categoría que no sea 'Discoteca')
-- simplemente no lo usan. `price_per_hour` (ya existente) se reutiliza como
-- el valor del cover — sigue siendo "un precio", solo que `NightclubCard`
-- lo rotula "Cover" en vez de "/h" para esta categoría.
alter table public.provider_services add column if not exists todays_event text;

comment on column public.provider_services.todays_event is 'Solo relevante para category = ''Discoteca'': breve texto del evento/programación de hoy, mostrado en NightclubCard. Null en cualquier otra categoría.';

-- =========================================================
-- 24. Selfie de verificación de identidad (KYC)
-- Complementa identity_doc_url (sección 20): el admin ahora puede comparar
-- la foto de la cédula contra una selfie tomada en vivo con la cámara para
-- confirmar que es la misma persona antes de aprobar. Reutiliza el bucket
-- privado `identity_documents` con el mismo prefijo de carpeta `{uid}/...`
-- que ya usa la cédula — las policies de esa sección (select_own/
-- select_admin/insert/delete_own) filtran solo por ese prefijo, no por
-- nombre de archivo, así que ya cubren la selfie sin ninguna policy nueva
-- de storage. Nullable por la misma razón que identity_doc_url: filas
-- existentes no tienen selfie y no hay valor por defecto razonable; lo
-- obligatorio (documento + selfie) se valida en CreateServiceModal.
-- =========================================================
alter table public.provider_services add column if not exists selfie_url text;

comment on column public.provider_services.selfie_url is 'Ruta privada (no URL pública) de la selfie tomada en vivo con la cámara, en el mismo bucket `identity_documents` que identity_doc_url. Se usa para comparar visualmente contra la cédula durante la moderación.';

-- Reemplaza create_provider_service_with_consent (sección 20) para que
-- también guarde selfie_url en la misma transacción que el resto del KYC.
-- El drop explícito es necesario porque Postgres distingue funciones por
-- firma: un `create or replace` con una lista de parámetros distinta crea
-- una función nueva en vez de reemplazar la de 6 argumentos.
drop function if exists public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text
);

create or replace function public.create_provider_service_with_consent(
  category text,
  business_name text,
  description text,
  price_per_hour numeric,
  cover_photos text[],
  identity_doc_url text,
  selfie_url text
)
returns uuid
language plpgsql
security invoker
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then
    raise exception 'No hay una sesión activa.';
  end if;

  insert into public.provider_services (
    user_id, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, habeas_data_accepted_at
  )
  values (
    me, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, now()
  )
  returning id into new_id;

  insert into public.user_consents (user_id, consent_type, accepted_version)
  values (me, 'identity_document_habeas_data', '1.0');

  return new_id;
end;
$$;

grant execute on function public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text
) to authenticated;

-- =========================================================
-- 25. Tarifas flexibles + detalles por categoría
--
-- El check de `category` (secciones 17/23) solo permitía 6 valores, pero
-- `kServiceCategories` en el formulario Flutter ya ofrecía 12 (Catering,
-- Fotografía, Estudio de grabación, Decoracion y ambientación, Transporte,
-- Otros nunca estuvieron en la lista permitida). Elegir cualquiera de esos
-- y guardar rompía el insert con una violación de constraint — se descubrió
-- al construir esta sección, no algo que introduzca. Los 12 valores de
-- abajo son una copia BYTE A BYTE de esa lista, incluyendo el typo real que
-- ya tiene ('Decoracion y ambientación', sin tilde en "Decoracion") — no se
-- corrige aquí porque filas ya insertadas con ese texto exacto dejarían de
-- pasar el constraint si solo se permitiera la ortografía correcta.
alter table public.provider_services drop constraint if exists provider_services_category_check;
alter table public.provider_services add constraint provider_services_category_check
  check (category in (
    'Agrupación', 'Solista', 'DJ', 'Sonido', 'Ensayadero', 'Discoteca',
    'Catering', 'Fotografía', 'Estudio de grabación',
    'Decoracion y ambientación', 'Transporte', 'Otros'
  ));

-- `pricing_type` decide cómo se rotula/interpreta `price_per_hour` — la
-- columna numérica no se renombra (ya la usan `NightclubCard` como "Cover",
-- el RPC de creación, y varios widgets de la Tarima); solo cambia qué
-- significa el número. Default 'per_hour' porque es el comportamiento que
-- ya tenía toda fila existente antes de esta sección.
alter table public.provider_services add column if not exists pricing_type text
  not null default 'per_hour'
  check (pricing_type in ('per_hour', 'fixed', 'per_night'));

comment on column public.provider_services.pricing_type is 'Cómo se cotiza price_per_hour: per_hour (por hora), fixed (tarifa fija de paquete/evento) o per_night (por noche completa). Sugerido por categoría en CreateServiceModal, editable por el proveedor.';

-- Backfill: las únicas categorías que ya existían y encajan naturalmente en
-- "por noche completa" son DJ y Discoteca (Discoteca ya usaba
-- price_per_hour como el valor del "Cover" nocturno, ver sección 23).
-- Cualquier fila nueva llega con el pricing_type que el formulario mande.
update public.provider_services
set pricing_type = 'per_night'
where category in ('DJ', 'Discoteca');

-- `details` guarda los campos opcionales que varían por categoría (género
-- musical, aforo, tipo de menú, zona de cobertura...) — jsonb en vez de una
-- columna por campo o una tabla separada: son ~15 atributos opcionales que
-- ninguna consulta necesita filtrar/indexar todavía, así que columnas
-- sueltas dejarían la mayoría en null por fila y una tabla normalizada
-- exigiría FKs y RLS duplicada por poco beneficio real hoy.
alter table public.provider_services add column if not exists details jsonb not null default '{}'::jsonb;

comment on column public.provider_services.details is 'Bolsa de atributos opcionales específicos de la categoría (género musical, aforo, tipo de menú, zona de cobertura, etc.), llenados dinámicamente por CreateServiceModal según `category`. Claves libres, sin esquema fijo — ver la constante _kCategoryDetailFields en el cliente Flutter para el mapeo vigente categoría → campos.';

-- Reemplaza create_provider_service_with_consent (secciones 20/24) para
-- que también guarde pricing_type y details en la misma transacción.
drop function if exists public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text
);

create or replace function public.create_provider_service_with_consent(
  category text,
  business_name text,
  description text,
  price_per_hour numeric,
  cover_photos text[],
  identity_doc_url text,
  selfie_url text,
  pricing_type text,
  details jsonb
)
returns uuid
language plpgsql
security invoker
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then
    raise exception 'No hay una sesión activa.';
  end if;

  insert into public.provider_services (
    user_id, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    habeas_data_accepted_at
  )
  values (
    me, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    now()
  )
  returning id into new_id;

  insert into public.user_consents (user_id, consent_type, accepted_version)
  values (me, 'identity_document_habeas_data', '1.0');

  return new_id;
end;
$$;

grant execute on function public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text, text, jsonb
) to authenticated;

-- =========================================================
-- 26. Zona de cobertura como columna indexable
--
-- Sale de `details` (jsonb, sección 25) a su propia columna: el objetivo
-- es que un cliente en Girón pueda encontrar proveedores con sede en
-- Bucaramanga que también cubran Girón, lo que exige poder filtrar por
-- ciudad de forma eficiente — algo que jsonb no ofrece sin desempacar cada
-- fila. Mismo patrón que `profiles.coverage_cities` (sección 1), que ya
-- resuelve el mismo problema para el radio de desplazamiento de un músico.
alter table public.provider_services add column if not exists coverage_areas text[] not null default '{}';

comment on column public.provider_services.coverage_areas is 'Ciudades/municipios adicionales que este servicio cubre, más allá de la ciudad base del proveedor (`profiles.city`). Alimentado por el input de chips en CreateServiceModal. Pensado para filtrar la Tarima por ciudad (aún no construido) — por eso vive en su propia columna indexable y no dentro de `details`.';

create index if not exists provider_services_coverage_areas_idx
  on public.provider_services using gin (coverage_areas);

-- Reemplaza create_provider_service_with_consent (secciones 20/24/25) para
-- que también guarde coverage_areas en la misma transacción.
drop function if exists public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text, text, jsonb
);

create or replace function public.create_provider_service_with_consent(
  category text,
  business_name text,
  description text,
  price_per_hour numeric,
  cover_photos text[],
  identity_doc_url text,
  selfie_url text,
  pricing_type text,
  details jsonb,
  coverage_areas text[]
)
returns uuid
language plpgsql
security invoker
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then
    raise exception 'No hay una sesión activa.';
  end if;

  insert into public.provider_services (
    user_id, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    coverage_areas, habeas_data_accepted_at
  )
  values (
    me, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    coverage_areas, now()
  )
  returning id into new_id;

  insert into public.user_consents (user_id, consent_type, accepted_version)
  values (me, 'identity_document_habeas_data', '1.0');

  return new_id;
end;
$$;

grant execute on function public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text, text, jsonb, text[]
) to authenticated;

-- =========================================================
-- 27. Porcentaje de anticipo económico (Sistema Anti-Fuga)
--
-- El estado `pending_advance` de `bookings` (más arriba) ya nombraba este
-- concepto, pero no existía ninguna columna, RPC ni UI que lo calculara o
-- guardara — terreno limpio, sin flujo de negociación con el que este
-- campo pueda entrar en conflicto. El proveedor fija su tasa estándar al
-- crear el servicio; el monto en pesos NUNCA se guarda (se recalcula
-- siempre como `price_per_hour * advance_percentage / 100`, ver
-- `advanceAmountFor` en `lib/core/utils/currency.dart`), así que cuando el
-- flujo real de cobro del adelanto se construya, reutiliza ese mismo
-- cálculo en vez de canonizar un número que se desincroniza si el precio
-- cambia.
alter table public.provider_services add column if not exists advance_percentage integer
  not null default 20
  check (advance_percentage in (10, 20, 30, 40, 50));

comment on column public.provider_services.advance_percentage is 'Porcentaje del precio que el cliente debe pagar como anticipo para asegurar la reserva (Sistema Anti-Fuga). El MONTO no se guarda aquí — se calcula siempre a partir de este porcentaje y price_per_hour vigente.';

-- Reemplaza create_provider_service_with_consent (secciones 20/24/25/26)
-- para que también guarde advance_percentage en la misma transacción.
drop function if exists public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text, text, jsonb, text[]
);

create or replace function public.create_provider_service_with_consent(
  category text,
  business_name text,
  description text,
  price_per_hour numeric,
  cover_photos text[],
  identity_doc_url text,
  selfie_url text,
  pricing_type text,
  details jsonb,
  coverage_areas text[],
  advance_percentage integer
)
returns uuid
language plpgsql
security invoker
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then
    raise exception 'No hay una sesión activa.';
  end if;

  insert into public.provider_services (
    user_id, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    coverage_areas, advance_percentage, habeas_data_accepted_at
  )
  values (
    me, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    coverage_areas, advance_percentage, now()
  )
  returning id into new_id;

  insert into public.user_consents (user_id, consent_type, accepted_version)
  values (me, 'identity_document_habeas_data', '1.0');

  return new_id;
end;
$$;

grant execute on function public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text, text, jsonb, text[], integer
) to authenticated;

-- =========================================================
-- 28. Precio a convenir (ocultar price_per_hour al cliente)
--
-- El precio SIGUE siendo obligatorio y se guarda igual que siempre —
-- `price_visible` solo decide si el cliente lo ve o ve "Precio a
-- convenir". El número real sigue disponible para el proveedor (preview
-- de anticipo en CreateServiceModal) y como ancla para las
-- contrapropuestas del motor de reservas, sin romper ningún filtro/orden
-- que ya dependa de price_per_hour.
alter table public.provider_services add column if not exists price_visible boolean not null default true;

comment on column public.provider_services.price_visible is 'Si es false, el cliente ve "Precio a convenir" en vez del monto real de price_per_hour (Tarima, ServiceDetailScreen, Condiciones de reserva). El precio sigue guardándose y usándose internamente (preview de anticipo, contrapropuestas) sin importar este flag.';

-- Reemplaza create_provider_service_with_consent (secciones 20/24/25/26/27)
-- para que también guarde price_visible en la misma transacción.
drop function if exists public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text, text, jsonb, text[], integer
);

create or replace function public.create_provider_service_with_consent(
  category text,
  business_name text,
  description text,
  price_per_hour numeric,
  cover_photos text[],
  identity_doc_url text,
  selfie_url text,
  pricing_type text,
  details jsonb,
  coverage_areas text[],
  advance_percentage integer,
  price_visible boolean
)
returns uuid
language plpgsql
security invoker
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then
    raise exception 'No hay una sesión activa.';
  end if;

  insert into public.provider_services (
    user_id, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    coverage_areas, advance_percentage, price_visible, habeas_data_accepted_at
  )
  values (
    me, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    coverage_areas, advance_percentage, price_visible, now()
  )
  returning id into new_id;

  insert into public.user_consents (user_id, consent_type, accepted_version)
  values (me, 'identity_document_habeas_data', '1.0');

  return new_id;
end;
$$;

grant execute on function public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text, text, jsonb, text[], integer, boolean
) to authenticated;

-- =========================================================
-- 29. Géneros musicales como columna indexable
--
-- Sale del campo `genre` que vivía suelto dentro de `details` (jsonb,
-- sección 25) a su propia columna — mismo motivo que `coverage_areas`
-- (sección 26): el objetivo es que un cliente pueda filtrar la Tarima por
-- género ("quiero una agrupación que toque vallenato"), algo que jsonb no
-- permite indexar/filtrar eficientemente. Solo aplica a 'Solista', 'DJ' y
-- 'Agrupación' — el resto de categorías nunca lo llenan.
alter table public.provider_services add column if not exists music_genres text[] not null default '{}';

comment on column public.provider_services.music_genres is 'Géneros musicales que este servicio toca (Vallenato, Salsa, etc.) — solo relevante para category en (''Solista'', ''DJ'', ''Agrupación''). Reemplaza el campo `genre` que antes vivía dentro de `details`; ahora es su propia columna indexable para poder filtrar la Tarima por género a futuro.';

create index if not exists provider_services_music_genres_idx
  on public.provider_services using gin (music_genres);

-- Reemplaza create_provider_service_with_consent (secciones 20/24/25/26/
-- 27/28) para que también guarde music_genres en la misma transacción.
drop function if exists public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text, text, jsonb, text[], integer, boolean
);

create or replace function public.create_provider_service_with_consent(
  category text,
  business_name text,
  description text,
  price_per_hour numeric,
  cover_photos text[],
  identity_doc_url text,
  selfie_url text,
  pricing_type text,
  details jsonb,
  coverage_areas text[],
  advance_percentage integer,
  price_visible boolean,
  music_genres text[]
)
returns uuid
language plpgsql
security invoker
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then
    raise exception 'No hay una sesión activa.';
  end if;

  insert into public.provider_services (
    user_id, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    coverage_areas, advance_percentage, price_visible, music_genres,
    habeas_data_accepted_at
  )
  values (
    me, category, business_name, description, price_per_hour,
    cover_photos, identity_doc_url, selfie_url, pricing_type, details,
    coverage_areas, advance_percentage, price_visible, music_genres,
    now()
  )
  returning id into new_id;

  insert into public.user_consents (user_id, consent_type, accepted_version)
  values (me, 'identity_document_habeas_data', '1.0');

  return new_id;
end;
$$;

grant execute on function public.create_provider_service_with_consent(
  text, text, text, numeric, text[], text, text, text, jsonb, text[], integer, boolean, text[]
) to authenticated;

-- =========================================================
-- 30. Control de visibilidad pública por video (`musician_videos`)
--
-- El músico ya sube sus videos como siempre (sección 11); esto añade un
-- interruptor explícito por video para decidir cuáles aparecen en la
-- pestaña "Portafolio" del cliente (`ServiceDetailScreen`) — antes esa
-- pestaña ni siquiera leía `musician_videos`. Default `true`: la copia
-- de "Mi Estado" ya le dice al músico que suba fotos/videos para publicar
-- su perfil, así que ocultar todo por defecto lo dejaría con un
-- portafolio vacío sin ninguna señal de por qué. El interruptor es para
-- que oculte un video puntual, no para exigirle opt-in en cada uno.
alter table public.musician_videos add column if not exists show_in_profile boolean not null default true;

comment on column public.musician_videos.show_in_profile is 'Si es false, el video no aparece en la pestaña "Portafolio" del cliente aunque sí sigue en la galería de gestión del propio proveedor. Editable en cualquier momento desde MediaManagerCard.';

drop policy if exists "musician_videos_update_own" on public.musician_videos;
create policy "musician_videos_update_own"
  on public.musician_videos
  for update
  to authenticated
  using (auth.uid() = musician_id)
  with check (auth.uid() = musician_id);

-- El grant de columna es lo que de verdad protege `views_count`: la
-- policy de arriba solo filtra QUÉ FILA se puede tocar, no qué columna,
-- así que sin esto el propio dueño podría inflar su contador con un
-- `.update()` directo — justo lo que la sección 11 dejó deliberadamente
-- bloqueado al no tener ninguna policy de update. `revoke` primero
-- porque el bootstrap de Supabase ya otorga `update` de tabla completa a
-- `authenticated` por defecto.
revoke update on public.musician_videos from authenticated;
grant update (show_in_profile) on public.musician_videos to authenticated;

-- =========================================================
-- 31. Video ↔ servicio específico (evita que un video de "Solista" se
-- mezcle con el portafolio de "Sonido" del mismo proveedor)
--
-- `musician_videos.musician_id` apunta a `profiles`, no a
-- `provider_services` — un mismo proveedor puede tener varias filas en
-- `provider_services` (categorías distintas), así que hasta ahora TODOS
-- sus videos aparecían mezclados en el portafolio público de CUALQUIERA
-- de sus servicios. `service_id` NULLABLE es el mecanismo, no un limbo:
-- null significa "se muestra en todos los servicios de este proveedor"
-- — exactamente el comportamiento heredado de antes de esta columna —
-- así que ningún video existente pierde visibilidad el día que se
-- aplique esta migración.
alter table public.musician_videos add column if not exists service_id uuid
  references public.provider_services (id) on delete set null;

comment on column public.musician_videos.service_id is 'A qué provider_services pertenece este video. Null = se muestra en el portafolio de TODOS los servicios de este proveedor (comportamiento heredado). Asignable/reasignable en cualquier momento desde MediaManagerCard.';

create index if not exists musician_videos_service_id_idx
  on public.musician_videos (service_id);

-- Backfill: solo para proveedores con exactamente un servicio, la única
-- asignación no ambigua posible — con 2+ servicios no hay forma correcta
-- de adivinar cuál, así que esos quedan en null (visibles en todos,
-- igual que hoy) hasta que el proveedor los categorice manualmente.
update public.musician_videos mv
set service_id = ps.id
from public.provider_services ps
where mv.musician_id = ps.user_id
  and mv.service_id is null
  and (
    select count(*) from public.provider_services ps2 where ps2.user_id = mv.musician_id
  ) = 1;

-- Mismo motivo que el grant de columna de la sección 30: la policy
-- `musician_videos_update_own` ya cubre la fila, este grant es lo que
-- permite tocar esta columna en particular sin reabrir `views_count`.
grant update (service_id) on public.musician_videos to authenticated;

-- =========================================================
-- 32. Calendario de disponibilidad por servicio
-- (`provider_unavailability`)
--
-- Un día bloqueado por el proveedor para UN `provider_services` puntual
-- (no para todos sus servicios a la vez) — un músico con "Solista" y
-- "Agrupación" puede estar libre para uno y ocupado para el otro el
-- mismo día. La sola presencia de una fila (service_id, date) significa
-- "ocupado"; no hay columna de estado que alternar.
-- =========================================================
create table if not exists public.provider_unavailability (
  id          uuid primary key default gen_random_uuid(),
  service_id  uuid not null references public.provider_services (id) on delete cascade,
  date        date not null,
  created_at  timestamptz not null default now(),
  constraint provider_unavailability_unique unique (service_id, date)
);

comment on table public.provider_unavailability is 'Días bloqueados por el proveedor para un provider_services específico. Cada fila = un día ocupado; borrar la fila = volver a disponible.';

create index if not exists provider_unavailability_service_id_idx
  on public.provider_unavailability (service_id, date);

alter table public.provider_unavailability enable row level security;

-- El propio proveedor administra el calendario de sus servicios: las
-- cuatro policies verifican dueño vía `provider_services.user_id`, la
-- misma FK que ya usa `provider_services_update_own` (sección 17).
drop policy if exists "provider_unavailability_select_own" on public.provider_unavailability;
create policy "provider_unavailability_select_own"
  on public.provider_unavailability
  for select
  to authenticated
  using (
    exists (
      select 1 from public.provider_services ps
      where ps.id = service_id and ps.user_id = auth.uid()
    )
  );

drop policy if exists "provider_unavailability_insert_own" on public.provider_unavailability;
create policy "provider_unavailability_insert_own"
  on public.provider_unavailability
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.provider_services ps
      where ps.id = service_id and ps.user_id = auth.uid()
    )
  );

drop policy if exists "provider_unavailability_delete_own" on public.provider_unavailability;
create policy "provider_unavailability_delete_own"
  on public.provider_unavailability
  for delete
  to authenticated
  using (
    exists (
      select 1 from public.provider_services ps
      where ps.id = service_id and ps.user_id = auth.uid()
    )
  );

-- =========================================================
-- 33. Franjas de horario dentro de un día (`provider_unavailability`)
--
-- Hasta ahora una fila = un día completo ocupado, con máximo una fila por
-- fecha (`provider_unavailability_unique`). Para bloquear solo un tramo
-- del día (ej. 7am-9am) sin ocupar el día entero, la tabla necesita poder
-- guardar VARIAS filas para la misma fecha. `start_time`/`end_time`
-- ambos null sigue significando "día completo", igual que antes; con
-- valores, la fila es una franja puntual. Mutua exclusión entre "día
-- completo" y "franjas" para la misma fecha se resuelve en la app (al
-- marcar día completo se borran las franjas existentes y viceversa), no
-- acá, para no encadenar constraints entre filas distintas.
-- =========================================================
alter table public.provider_unavailability
  drop constraint if exists provider_unavailability_unique;

alter table public.provider_unavailability
  add column if not exists start_time time,
  add column if not exists end_time time;

alter table public.provider_unavailability
  drop constraint if exists provider_unavailability_time_range_check;
alter table public.provider_unavailability
  add constraint provider_unavailability_time_range_check
  check (
    (start_time is null and end_time is null)
    or (start_time is not null and end_time is not null and end_time > start_time)
  );

comment on column public.provider_unavailability.start_time is 'Null junto con end_time = día completo bloqueado. Con valor = inicio de una franja horaria puntual dentro del día.';
comment on column public.provider_unavailability.end_time is 'Ver comentario de start_time.';

-- Como máximo UN bloqueo de "día completo" por fecha.
create unique index if not exists provider_unavailability_full_day_unique
  on public.provider_unavailability (service_id, date)
  where start_time is null and end_time is null;

-- Evita agregar la misma franja dos veces por accidente; no limita
-- cuántas franjas DISTINTAS puede tener una misma fecha.
create unique index if not exists provider_unavailability_slot_unique
  on public.provider_unavailability (service_id, date, start_time, end_time)
  where start_time is not null;