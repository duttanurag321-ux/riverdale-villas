import { createBrowserClient } from "@supabase/ssr";
// Browser client: uses only the public anon key and the logged-in user's session. Storage rules (RLS) decide what it may do.
export const createBrowserSupabase = () => createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
