import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });
  const supabase = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (list: { name: string; value: string; options: any }[]) => {
        list.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        list.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });
  const { data: claims } = await supabase.auth.getClaims();   // also refreshes an expiring session
  const user = claims?.claims?.sub ? claims.claims : null;
  const p = request.nextUrl.pathname;
  const isPublic = p.startsWith("/login") || p.startsWith("/forgot-password") || p.startsWith("/auth") || p === "/manifest.webmanifest";
  if (!user && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login"; url.search = "";
    return NextResponse.redirect(url);
  }
  return response;
}
