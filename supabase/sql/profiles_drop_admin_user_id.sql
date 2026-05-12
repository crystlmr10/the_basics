-- Remove legacy public.profiles.admin_user_id (no longer used by the_basics app).
-- Run once in Supabase → SQL Editor.

drop index if exists public.profiles_admin_user_id_ci_unique_idx;

alter table public.profiles
  drop column if exists admin_user_id;
