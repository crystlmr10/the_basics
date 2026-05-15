-- Admin cancels an open SOS: sets status closed + admin_cancelled for history display.
-- Run in Supabase SQL Editor after other sos_dispatches migrations.

alter table public.sos_dispatches
  add column if not exists admin_cancelled boolean not null default false;

alter table public.sos_dispatches
  add column if not exists closed_at timestamptz;

create or replace function public.admin_cancel_sos_dispatch(p_dispatch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_actor_role text;
  v_dispatch record;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_uid;

  if coalesce(v_actor_role, '') <> 'admin' then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select d.id, d.status, d.ticket_number
  into v_dispatch
  from public.sos_dispatches d
  where d.id = p_dispatch_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'dispatch_not_found');
  end if;

  if v_dispatch.status = 'closed' then
    return jsonb_build_object(
      'ok', false,
      'error', 'dispatch_already_closed',
      'ticket_number', v_dispatch.ticket_number
    );
  end if;

  update public.sos_dispatch_offers
  set
    status = 'expired',
    responded_at = coalesce(responded_at, now())
  where dispatch_id = p_dispatch_id
    and status in ('pending', 'accepted');

  update public.sos_dispatches d
  set
    status = 'closed',
    admin_cancelled = true,
    closed_at = coalesce(d.closed_at, now())
  where d.id = p_dispatch_id;

  return jsonb_build_object(
    'ok', true,
    'ticket_number', v_dispatch.ticket_number
  );
end;
$$;

revoke all on function public.admin_cancel_sos_dispatch(uuid) from public;
grant execute on function public.admin_cancel_sos_dispatch(uuid) to authenticated;

comment on function public.admin_cancel_sos_dispatch(uuid) is
  'Admin-only: closes dispatch with admin_cancelled=true; expires pending/accepted offers; sets closed_at.';
