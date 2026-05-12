-- Optional schema helpers for public.profiles (username uniqueness).
-- Access Control / Edge Function staff accounts use username only (no separate User ID).
--
-- Run once in Supabase SQL editor if you want the extra username index here.
-- Your project may already define username uniqueness in another migration
-- (e.g. profiles_username_lower_uidx); in that case duplicate CREATE INDEX IF NOT EXISTS is safe.

alter table public.profiles
  add column if not exists admin_user_id text;

-- Case-insensitive uniqueness for username (when provided).
create unique index if not exists profiles_username_ci_unique_idx
  on public.profiles (lower(username))
  where username is not null and btrim(username) <> '';

-- Legacy: optional operator label column (unused by current admin-create-account flow).
create unique index if not exists profiles_admin_user_id_ci_unique_idx
  on public.profiles (lower(admin_user_id))
  where admin_user_id is not null and btrim(admin_user_id) <> '';

-- Optional cleanup (run only if you want to drop legacy admin_user_id):
-- drop index if exists public.profiles_admin_user_id_ci_unique_idx;
-- alter table public.profiles drop column if exists admin_user_id;
