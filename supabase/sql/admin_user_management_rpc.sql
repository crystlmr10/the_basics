-- Admin user management read + status toggle RPCs.
-- Run in Supabase SQL editor (full file). Safe to re-run.

-- App + RPCs expect profiles.status. Older DBs may lack it; fix before CREATE FUNCTION.
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
  'Account status for admin user management: active | inactive (soft deactivate).';

-- Help PostgREST see the column without waiting for cache TTL.
select pg_notify('pgrst', 'reload schema');

create or replace function public.admin_user_management_list()
returns table (
  user_id uuid,
  full_name text,
  username text,
  email text,
  role text,
  status text,
  joined_at timestamptz,
  flood_reports bigint,
  sos_reports bigint
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and lower(coalesce(p.role, '')) = 'admin'
  ) then
    raise exception 'forbidden';
  end if;

  return query
  with flood as (
    select ur.user_id, count(*)::bigint as cnt
    from public.user_reports ur
    group by ur.user_id
  ),
  sos as (
    select sd.user_id, count(*)::bigint as cnt
    from public.sos_dispatches sd
    group by sd.user_id
  )
  select
    p.id as user_id,
    p.full_name,
    p.username,
    p.email,
    coalesce(p.role, 'user') as role,
    case
      when lower(coalesce(p.status, 'inactive')) = 'active' then 'active'
      else 'inactive'
    end as status,
    au.created_at as joined_at,
    coalesce(flood.cnt, 0::bigint) as flood_reports,
    coalesce(sos.cnt, 0::bigint) as sos_reports
  from public.profiles p
  left join auth.users au on au.id = p.id
  left join flood on flood.user_id = p.id
  left join sos on sos.user_id = p.id
  order by lower(coalesce(p.full_name, p.username, p.email, p.id::text));
end;
$$;

revoke all on function public.admin_user_management_list() from public;
grant execute on function public.admin_user_management_list() to authenticated;

comment on function public.admin_user_management_list() is
  'Admin-only list for web user management with joined_at from auth.users and report counts.';

create or replace function public.admin_user_management_set_status(
  p_user_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_status text := lower(trim(coalesce(p_status, '')));
  v_target uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and lower(coalesce(p.role, '')) = 'admin'
  ) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  if v_status not in ('active', 'inactive') then
    return jsonb_build_object('ok', false, 'error', 'invalid_status');
  end if;

  if p_user_id = v_uid then
    return jsonb_build_object('ok', false, 'error', 'cannot_change_self');
  end if;

  update public.profiles p
  set status = v_status
  where p.id = p_user_id
  returning p.id into v_target;

  if v_target is null then
    return jsonb_build_object('ok', false, 'error', 'user_not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'user_id', v_target,
    'status', v_status
  );
end;
$$;

revoke all on function public.admin_user_management_set_status(uuid, text) from public;
grant execute on function public.admin_user_management_set_status(uuid, text) to authenticated;

comment on function public.admin_user_management_set_status(uuid, text) is
  'Admin-only soft account status toggle for user management.';
