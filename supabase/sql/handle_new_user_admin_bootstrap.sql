-- Allow admin-provisioned accounts (Access Control / Edge Function) without
-- full citizen registration metadata. Citizen sign-ups still use the strict path.
--
-- Staff login identifier is profiles.username (no separate operator User ID).
-- Optional: if you added public.profiles.admin_user_id for legacy data, it may
-- remain NULL for new staff rows; you do not need to re-run anything for that.
-- Run once in Supabase → SQL Editor (or re-run after edits to keep trigger current).

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_boot boolean := coalesce(new.raw_user_meta_data->>'admin_bootstrap', '') = 'true';
  uname text;
  phone text;
  gname text;
  mname text;
  lname text;
  fname text;
  sex_val text;
  dob_raw text;
  dob_val date;
  v_role text;
  v_staff_phone text;
  v_staff_full text;
  v_gname text;
  v_lname text;
begin
  -- ── Admin / staff provisioning (Edge Function sets admin_bootstrap = true)
  if admin_boot then
    v_role := lower(trim(coalesce(new.raw_user_meta_data->>'role', 'rescuer')));
    if v_role not in ('rescuer', 'admin') then
      v_role := 'rescuer';
    end if;

    v_staff_full := nullif(trim(coalesce(new.raw_user_meta_data->>'name', '')), '');
    if v_staff_full is null or v_staff_full = '' then
      v_staff_full := 'Staff User';
    end if;

    v_gname := split_part(v_staff_full, ' ', 1);
    v_lname := nullif(trim(substring(v_staff_full from length(v_gname) + 2)), '');
    if v_lname is null or v_lname = '' then
      v_lname := 'Account';
    end if;

    -- Prefer E.164 from Edge Function metadata.
    -- Rescuer keeps synthetic fallback (existing behavior).
    -- Admin can start with NULL phone_number during initial setup.
    v_staff_phone := nullif(trim(coalesce(new.raw_user_meta_data->>'phone_number', '')), '');
    if v_role = 'rescuer' then
      if v_staff_phone is null or v_staff_phone !~ '^\+639[0-9]{9}$' then
        v_staff_phone := '+639' || lpad((abs(hashtext(new.id::text)) % 1000000000)::text, 9, '0');
      end if;
    elsif v_staff_phone is not null and v_staff_phone !~ '^\+639[0-9]{9}$' then
      v_staff_phone := null;
    end if;

    insert into public.profiles (
      id,
      email,
      username,
      phone_number,
      role,
      given_name,
      middle_name,
      last_name,
      full_name,
      date_of_birth,
      sex
    )
    values (
      new.id,
      lower(trim(new.email)),
      nullif(lower(trim(coalesce(new.raw_user_meta_data->>'username', ''))), ''),
      v_staff_phone,
      v_role,
      v_gname,
      null,
      v_lname,
      v_staff_full,
      null,
      null
    )
    on conflict (id) do update set
      email = excluded.email,
      username = coalesce(nullif(excluded.username, ''), public.profiles.username),
      phone_number = coalesce(excluded.phone_number, public.profiles.phone_number),
      role = excluded.role,
      given_name = coalesce(excluded.given_name, public.profiles.given_name),
      middle_name = coalesce(excluded.middle_name, public.profiles.middle_name),
      last_name = coalesce(excluded.last_name, public.profiles.last_name),
      full_name = coalesce(excluded.full_name, public.profiles.full_name),
      date_of_birth = coalesce(excluded.date_of_birth, public.profiles.date_of_birth),
      sex = coalesce(excluded.sex, public.profiles.sex);

    return new;
  end if;

  -- ── Citizen registration (strict metadata)
  uname := lower(trim(coalesce(new.raw_user_meta_data->>'username', '')));
  phone := nullif(trim(coalesce(new.raw_user_meta_data->>'phone_number', '')), '');
  gname := nullif(trim(coalesce(new.raw_user_meta_data->>'given_name', '')), '');
  mname := nullif(trim(coalesce(new.raw_user_meta_data->>'middle_name', '')), '');
  lname := nullif(trim(coalesce(new.raw_user_meta_data->>'last_name', '')), '');
  fname := nullif(trim(coalesce(new.raw_user_meta_data->>'full_name', '')), '');
  sex_val := nullif(trim(coalesce(new.raw_user_meta_data->>'sex', '')), '');
  dob_raw := nullif(trim(coalesce(new.raw_user_meta_data->>'date_of_birth', '')), '');

  if uname = '' then
    uname := null;
  end if;

  if uname is null
     or gname is null
     or lname is null
     or phone is null
     or dob_raw is null
     or sex_val is null then
    raise exception using
      errcode = '22023',
      message = 'registration metadata invalid: missing required fields';
  end if;

  if phone !~ '^\+639\d{9}$' then
    raise exception using
      errcode = '22023',
      message = 'registration metadata invalid: phone must be +639XXXXXXXXX';
  end if;

  if sex_val not in ('Male', 'Female', 'Prefer not to say') then
    raise exception using
      errcode = '22023',
      message = 'registration metadata invalid: sex value is not allowed';
  end if;

  if dob_raw !~ '^\d{2}/\d{2}/\d{4}$' then
    raise exception using
      errcode = '22023',
      message = 'registration metadata invalid: date of birth must be MM/DD/YYYY';
  end if;

  dob_val := to_date(dob_raw, 'MM/DD/YYYY');
  if to_char(dob_val, 'MM/DD/YYYY') <> dob_raw then
    raise exception using
      errcode = '22023',
      message = 'registration metadata invalid: date of birth is not a real date';
  end if;

  if dob_val < (current_date - interval '120 years')::date
     or dob_val > (current_date - interval '13 years')::date then
    raise exception using
      errcode = '22023',
      message = 'registration metadata invalid: date of birth must be between 13 and 120 years old';
  end if;

  if fname is null then
    fname := concat_ws(' ', gname, mname, lname);
  end if;

  insert into public.profiles (
    id,
    email,
    username,
    phone_number,
    role,
    given_name,
    middle_name,
    last_name,
    full_name,
    date_of_birth,
    sex
  )
  values (
    new.id,
    lower(trim(new.email)),
    nullif(uname, ''),
    phone,
    'user',
    gname,
    mname,
    lname,
    fname,
    dob_val,
    sex_val
  )
  on conflict (id) do update set
    email = excluded.email,
    username = coalesce(nullif(excluded.username, ''), public.profiles.username),
    phone_number = coalesce(excluded.phone_number, public.profiles.phone_number),
    role = coalesce(public.profiles.role, excluded.role),
    given_name = coalesce(excluded.given_name, public.profiles.given_name),
    middle_name = coalesce(excluded.middle_name, public.profiles.middle_name),
    last_name = coalesce(excluded.last_name, public.profiles.last_name),
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    date_of_birth = coalesce(excluded.date_of_birth, public.profiles.date_of_birth),
    sex = coalesce(excluded.sex, public.profiles.sex);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute procedure public.handle_new_user();
