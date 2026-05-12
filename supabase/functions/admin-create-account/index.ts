import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

type CreateAccountBody = {
  fullName?: string
  username?: string
  phoneNumber?: string
  password?: string
  role?: string
}

/** Mirror of `lib/utils/philippine_phone.dart` — E.164 `+639XXXXXXXXX` or null. */
function normalizePhilippineMobile(raw: string): string | null {
  const clean = raw.trim().replace(/\D/g, '')
  if (!clean) return null

  if (clean.startsWith('63') && clean.length === 12) {
    const rest = clean.slice(2)
    if (rest.length === 10 && rest.startsWith('9')) return `+63${rest}`
    return null
  }

  if (clean.length === 11 && clean.startsWith('09')) {
    const rest = clean.slice(1)
    if (rest.length === 10 && rest.startsWith('9')) return `+63${rest}`
    return null
  }

  if (clean.length === 10 && clean.startsWith('9')) return `+63${clean}`

  return null
}

const PH_E164_RE = /^\+639\d{9}$/

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

/** Public error payload: stable codes only (no DB / Auth internals). */
const err = (status: number, code: string) =>
  new Response(JSON.stringify({ code }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

const ok = (payload: Record<string, unknown>) =>
  new Response(JSON.stringify(payload), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return err(405, 'METHOD_NOT_ALLOWED')
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return err(500, 'SERVICE_UNAVAILABLE')
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return err(401, 'NOT_AUTHENTICATED')
    }
    const jwt = authHeader.replace('Bearer ', '').trim()

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false },
    })

    const {
      data: { user: caller },
      error: callerErr,
    } = await callerClient.auth.getUser()
    if (callerErr || !caller) {
      return err(401, 'INVALID_SESSION')
    }

    const { data: callerProfile, error: callerProfileErr } = await callerClient
      .from('profiles')
      .select('role')
      .eq('id', caller.id)
      .maybeSingle()
    if (callerProfileErr) {
      return err(500, 'SERVICE_UNAVAILABLE')
    }
    const callerRole = String(callerProfile?.role ?? '').toLowerCase()
    if (callerRole !== 'admin') {
      return err(403, 'FORBIDDEN_NOT_ADMIN')
    }

    let body: CreateAccountBody
    try {
      body = (await req.json()) as CreateAccountBody
    } catch {
      return err(400, 'MALFORMED_REQUEST')
    }

    const fullName = body.fullName?.trim() ?? ''
    const username = body.username?.trim().toLowerCase() ?? ''
    const password = body.password ?? ''
    const role = (body.role ?? '').trim().toLowerCase()
    const phoneRaw = body.phoneNumber?.trim() ?? ''
    const phoneE164 = normalizePhilippineMobile(phoneRaw)

    const usernameRule = /^[a-z0-9._-]{3,32}$/

    if (!fullName || !username || !password || !role) {
      return err(400, 'MISSING_FIELDS')
    }
    if (role !== 'rescuer' && role !== 'admin') {
      return err(400, 'INVALID_ROLE')
    }
    if (!usernameRule.test(username)) {
      return err(400, 'INVALID_USERNAME')
    }
    if (role === 'rescuer' && !phoneRaw) {
      return err(400, 'MISSING_FIELDS')
    }
    if (phoneRaw && (!phoneE164 || !PH_E164_RE.test(phoneE164))) {
      return err(400, 'INVALID_PHONE')
    }
    if (password.length < 6) {
      return err(400, 'INVALID_PASSWORD')
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    })

    const { data: duplicateUser, error: dupUserErr } = await adminClient
      .from('profiles')
      .select('id')
      .eq('username', username)
      .maybeSingle()
    if (dupUserErr) {
      console.error('[admin-create-account] duplicate username check', dupUserErr)
      return err(500, 'SERVICE_UNAVAILABLE')
    }
    if (duplicateUser != null) {
      return err(409, 'DUPLICATE_USERNAME')
    }

    if (phoneE164) {
      const { data: duplicatePhone, error: dupPhoneErr } = await adminClient
        .from('profiles')
        .select('id')
        .eq('phone_number', phoneE164)
        .maybeSingle()
      if (dupPhoneErr) {
        console.error('[admin-create-account] duplicate phone check', dupPhoneErr)
        return err(500, 'SERVICE_UNAVAILABLE')
      }
      if (duplicatePhone != null) {
        return err(409, 'DUPLICATE_PHONE')
      }
    }

    const pseudoEmail = `${username}@cebu161.local`
    const { data: createData, error: createErr } =
      await adminClient.auth.admin.createUser({
        email: pseudoEmail,
        password,
        email_confirm: true,
        user_metadata: {
          admin_bootstrap: true,
          username,
          name: fullName,
          role,
          phone_number: phoneE164,
        },
      })

    if (createErr || !createData.user?.id) {
      console.error('[admin-create-account] auth.admin.createUser', createErr)
      return err(500, 'ACCOUNT_CREATE_UNAVAILABLE')
    }

    const newAuthUserId = createData.user.id
    const { error: upsertErr } = await adminClient.from('profiles').upsert({
      id: newAuthUserId,
      username,
      email: pseudoEmail,
      phone_number: phoneE164,
      role,
      is_on_duty: false,
    })

    if (upsertErr) {
      console.error('[admin-create-account] profiles upsert', upsertErr)
      await adminClient.auth.admin.deleteUser(newAuthUserId)
      return err(500, 'PROFILE_SYNC_FAILED')
    }

    return ok({
      success: true,
      authUserId: newAuthUserId,
      username,
      role,
    })
  } catch (e) {
    console.error('[admin-create-account] unhandled', e)
    return err(500, 'SERVICE_UNAVAILABLE')
  }
})
