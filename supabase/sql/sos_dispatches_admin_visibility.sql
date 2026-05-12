-- Admin/Rescuer visibility + dispatch update policies for SOS rows.
-- Run this in Supabase SQL editor for project: ttsrktldvvqrgkfhsbbl

alter table public.sos_dispatches enable row level security;

drop policy if exists "sos_dispatches_select_own" on public.sos_dispatches;
drop policy if exists "sos_dispatches_select_admin_rescuer_or_own" on public.sos_dispatches;
create policy "sos_dispatches_select_admin_rescuer_or_own"
  on public.sos_dispatches
  for select
  using (
    auth.uid() = user_id
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin', 'rescuer')
    )
  );

drop policy if exists "sos_dispatches_update_admin_rescuer" on public.sos_dispatches;
create policy "sos_dispatches_update_admin_rescuer"
  on public.sos_dispatches
  for update
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin', 'rescuer')
    )
  )
  with check (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin', 'rescuer')
    )
  );
