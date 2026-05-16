-- Live Map moderation schema + RPCs
-- - Soft delete user_reports (with reason)
-- - Dismiss sensor alerts without deleting raw sensor logs
-- - Append immutable audit trail
-- Run this whole file in Supabase SQL Editor.

alter table public.user_reports
  add column if not exists deleted_at timestamptz;

alter table public.user_reports
  add column if not exists deleted_by uuid;

alter table public.user_reports
  add column if not exists delete_reason text;

comment on column public.user_reports.deleted_at is
  'Soft-delete timestamp set by admin moderation.';
comment on column public.user_reports.deleted_by is
  'Admin user id that performed soft-delete.';
comment on column public.user_reports.delete_reason is
  'Required moderation reason for report removal from active views.';

create table if not exists public.sensor_alert_dismissals (
  id bigint generated always as identity primary key,
  sensor_id text not null,
  sensor_status text not null,
  sensor_event_time timestamptz not null,
  dismissed_by uuid not null,
  dismiss_reason text not null,
  dismissed_at timestamptz not null default now(),
  unique (sensor_id, sensor_status, sensor_event_time)
);

comment on table public.sensor_alert_dismissals is
  'Admin dismissals for false positive sensor alerts. Does not delete sensor_logs.';

create table if not exists public.flood_moderation_audit (
  id bigint generated always as identity primary key,
  action_type text not null,
  entity_type text not null,
  entity_id uuid,
  sensor_id text,
  sensor_status text,
  sensor_event_time timestamptz,
  actor_id uuid not null,
  reason text not null,
  payload jsonb,
  created_at timestamptz not null default now()
);

comment on table public.flood_moderation_audit is
  'Immutable audit trail for flood moderation actions.';

create or replace function public.flood_moderation_audit_block_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'flood_moderation_audit is immutable';
end;
$$;

drop trigger if exists flood_moderation_audit_no_update_delete
  on public.flood_moderation_audit;
create trigger flood_moderation_audit_no_update_delete
before update or delete on public.flood_moderation_audit
for each row execute function public.flood_moderation_audit_block_mutation();

create or replace function public.admin_delete_user_report(
  p_report_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_payload jsonb;
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

  if v_reason = '' then
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;

  update public.user_reports ur
  set
    deleted_at = coalesce(ur.deleted_at, now()),
    deleted_by = v_uid,
    delete_reason = v_reason
  where ur.id = p_report_id
    and ur.deleted_at is null
  returning to_jsonb(ur.*) into v_payload;

  if v_payload is null then
    return jsonb_build_object('ok', false, 'error', 'report_not_found_or_deleted');
  end if;

  insert into public.flood_moderation_audit (
    action_type,
    entity_type,
    entity_id,
    actor_id,
    reason,
    payload
  )
  values (
    'delete_user_report',
    'user_report',
    p_report_id,
    v_uid,
    v_reason,
    v_payload
  );

  return jsonb_build_object('ok', true, 'report_id', p_report_id);
end;
$$;

revoke all on function public.admin_delete_user_report(uuid, text) from public;
grant execute on function public.admin_delete_user_report(uuid, text) to authenticated;

create or replace function public.admin_dismiss_sensor_alert(
  p_sensor_id text,
  p_status text,
  p_event_time timestamptz,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_sensor_id text := btrim(coalesce(p_sensor_id, ''));
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_reason text := btrim(coalesce(p_reason, ''));
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

  if v_sensor_id = '' or v_status = '' or p_event_time is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_sensor_event');
  end if;

  if v_reason = '' then
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;

  insert into public.sensor_alert_dismissals (
    sensor_id,
    sensor_status,
    sensor_event_time,
    dismissed_by,
    dismiss_reason
  )
  values (
    v_sensor_id,
    v_status,
    p_event_time,
    v_uid,
    v_reason
  )
  on conflict (sensor_id, sensor_status, sensor_event_time)
  do update
    set dismissed_by = excluded.dismissed_by,
        dismiss_reason = excluded.dismiss_reason,
        dismissed_at = now();

  insert into public.flood_moderation_audit (
    action_type,
    entity_type,
    sensor_id,
    sensor_status,
    sensor_event_time,
    actor_id,
    reason,
    payload
  )
  values (
    'dismiss_sensor_alert',
    'sensor_alert',
    v_sensor_id,
    v_status,
    p_event_time,
    v_uid,
    v_reason,
    jsonb_build_object(
      'sensor_id', v_sensor_id,
      'status', v_status,
      'event_time', p_event_time
    )
  );

  return jsonb_build_object(
    'ok', true,
    'sensor_id', v_sensor_id,
    'status', v_status,
    'event_time', p_event_time
  );
end;
$$;

revoke all on function public.admin_dismiss_sensor_alert(text, text, timestamptz, text) from public;
grant execute on function public.admin_dismiss_sensor_alert(text, text, timestamptz, text) to authenticated;

revoke all on table public.flood_moderation_audit from public;
revoke all on table public.sensor_alert_dismissals from public;
grant select on table public.flood_moderation_audit to authenticated;
grant select on table public.sensor_alert_dismissals to authenticated;

select pg_notify('pgrst', 'reload schema');
