-- Admin assigns a specific dispatch to a specific rescuer.
-- Ensures rescuer queue reflects assignment by upserting an accepted offer row.
-- Also emits an event row used by sos-dispatch-notify for targeted admin-assignment push.

create or replace function public.admin_assign_sos_dispatch(
  p_dispatch_id uuid,
  p_rescuer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_actor_role text;
  v_dispatch record;
  v_rescuer_ok boolean := false;
  v_transitioned_to_assignment boolean := false;
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

  select exists (
    select 1
    from public.profiles p
    where p.id = p_rescuer_id
      and p.role = 'rescuer'
  )
  into v_rescuer_ok;

  if not v_rescuer_ok then
    return jsonb_build_object('ok', false, 'error', 'rescuer_not_found');
  end if;

  select
    d.id,
    d.ticket_number,
    d.status,
    d.assigned_rescuer_id
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
      'error', 'dispatch_closed',
      'ticket_number', v_dispatch.ticket_number
    );
  end if;

  if v_dispatch.assigned_rescuer_id is not null
     and v_dispatch.assigned_rescuer_id is distinct from p_rescuer_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'already_assigned',
      'ticket_number', v_dispatch.ticket_number
    );
  end if;

  if exists (
    select 1
    from public.sos_dispatch_offers o
    join public.sos_dispatches d on d.id = o.dispatch_id
    where o.rescuer_id = p_rescuer_id
      and o.status = 'accepted'
      and d.status is distinct from 'closed'
      and d.id <> p_dispatch_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'rescuer_busy',
      'ticket_number', v_dispatch.ticket_number
    );
  end if;

  if v_dispatch.assigned_rescuer_id is null then
    if v_dispatch.status not in ('submitted', 'received', 'dispatching', 'en_route') then
      return jsonb_build_object(
        'ok', false,
        'error', 'invalid_status',
        'status', v_dispatch.status,
        'ticket_number', v_dispatch.ticket_number
      );
    end if;

    update public.sos_dispatches d
    set
      assigned_rescuer_id = p_rescuer_id,
      status = case
        when d.status in ('submitted', 'received') then 'dispatching'
        else d.status
      end
    where d.id = p_dispatch_id;

    v_transitioned_to_assignment := true;
  else
    update public.sos_dispatches d
    set status = case
      when d.status in ('submitted', 'received') then 'dispatching'
      else d.status
    end
    where d.id = p_dispatch_id;
  end if;

  insert into public.sos_dispatch_offers (
    dispatch_id,
    rescuer_id,
    status,
    created_at,
    responded_at
  )
  values (
    p_dispatch_id,
    p_rescuer_id,
    'accepted',
    now(),
    now()
  )
  on conflict (dispatch_id, rescuer_id)
  do update
    set status = 'accepted',
        responded_at = now();

  update public.sos_dispatch_offers
  set status = 'expired',
      responded_at = coalesce(responded_at, now())
  where dispatch_id = p_dispatch_id
    and rescuer_id <> p_rescuer_id
    and status = 'pending';

  update public.sos_dispatch_offers
  set status = 'expired',
      responded_at = coalesce(responded_at, now())
  where rescuer_id = p_rescuer_id
    and dispatch_id <> p_dispatch_id
    and status = 'pending';

  if v_transitioned_to_assignment then
    insert into public.sos_dispatch_reoffer_events (dispatch_id)
    values (p_dispatch_id);
  end if;

  return jsonb_build_object(
    'ok', true,
    'assigned', true,
    'ticket_number', v_dispatch.ticket_number
  );
end;
$$;

revoke all on function public.admin_assign_sos_dispatch(uuid, uuid) from public;
grant execute on function public.admin_assign_sos_dispatch(uuid, uuid) to authenticated;

comment on function public.admin_assign_sos_dispatch(uuid, uuid) is
  'Admin-only assignment RPC that sets assigned_rescuer_id, ensures accepted offer visibility, expires competing pending offers, and emits assignment push event.';
