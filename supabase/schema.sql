-- VallenatoConnect — esquema de base de datos
-- Ejecutar en el SQL Editor de Supabase (o vía `supabase db push`).
-- Requiere la extensión pgcrypto para gen_random_uuid() (habilitada por defecto en Supabase).

-- =========================================================
-- 1. Tabla `profiles`
-- =========================================================
create table if not exists public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  full_name          text not null default '',
  instrument         text not null default '',
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
  genre              text not null default 'Vallenato',
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
  add column if not exists genre text not null default 'Vallenato';

alter table public.profiles
  drop constraint if exists profiles_genre_check;
alter table public.profiles
  add constraint profiles_genre_check check (genre in ('Vallenato', 'Tropical'));

alter table public.profiles
  add column if not exists coverage_cities text[] not null default '{}';

alter table public.profiles
  add column if not exists busy_until timestamptz;

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
-- 3. Tabla `musician_photos`
-- Portafolio de fotos de presentaciones en vivo, mostrado en la galería de
-- "Mi Estado" y en la vista de detalle del músico dentro del dashboard.
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
-- 8. Búsqueda por nombre, ciudad base o cobertura geográfica
-- Usada por `MusicianRepository.fetchMusicians` cuando hay un término de
-- búsqueda: PostgREST permite seguir filtrando (instrumento, género, solo
-- libres) y ordenando sobre el resultado de esta función.
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
    );
$$;

grant execute on function public.search_musicians(text) to authenticated;

-- =========================================================
-- 9. Realtime
-- Habilita cambios en vivo sobre `profiles` para el contador de
-- "músicos disponibles" del dashboard.
-- =========================================================
alter publication supabase_realtime add table public.profiles;
