// Fallback path for account deletion, in case `public.delete_own_account()`
// (see supabase/schema.sql, section 10) hits a permission wall on this
// project's specific Supabase Postgres grants — some managed instances lock
// direct writes to `auth.users` down tighter than others, even for a
// `security definer` function owned by `postgres`. This Edge Function
// sidesteps that entirely by using the Auth Admin API (`service_role`),
// which always has full rights regardless of table-level grants.
//
// Deploy with:
//   supabase functions deploy delete-account
// The client calls it via `supabase.functions.invoke('delete-account')`,
// which automatically forwards the caller's JWT in the Authorization
// header — the function *never* trusts a client-supplied user id, it always
// resolves the id from that JWT server-side.
//
// Required secrets (set once via `supabase secrets set`):
//   SUPABASE_URL               — auto-provided by the Supabase runtime
//   SUPABASE_SERVICE_ROLE_KEY  — auto-provided by the Supabase runtime
// Neither needs to be set manually on most projects; both are injected by
// default into every Edge Function's environment.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Falta el header Authorization.' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // A client bound to the caller's own JWT — used only to resolve *who* is
  // asking, never to perform the deletion itself.
  const callerClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: userError,
  } = await callerClient.auth.getUser();

  if (userError || !user) {
    return new Response(JSON.stringify({ error: 'Sesión inválida o expirada.' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // The actual admin client — service_role, only ever used server-side,
  // never shipped to the app.
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id);

  if (deleteError) {
    return new Response(JSON.stringify({ error: deleteError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Deleting the auth.users row cascades to `profiles`, `contact_events`
  // and `musician_photos` via the `on delete cascade` foreign keys already
  // set up in supabase/schema.sql — nothing else to clean up here.
  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
