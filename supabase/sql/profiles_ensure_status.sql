-- One-shot fix when User Management RPC errors with: column p.status does not exist
-- Run this in Supabase SQL Editor on the SAME project as the Flutter app, then:
--   Dashboard → Settings → API → "Reload schema" (or wait ~1 min for cache).

alter table public.profiles
  add column if not exists status text;

update public.profiles
set status = 'active'
where status is null or trim(status) = '';

alter table public.profiles
  alter column status set default 'active';

alter table public.profiles
  alter column status set not null;

comment on column public.profiles.status is
  'active | inactive — soft account flag for admin user management.';

-- Ask PostgREST to pick up new columns (no-op if not permitted).
select pg_notify('pgrst', 'reload schema');
