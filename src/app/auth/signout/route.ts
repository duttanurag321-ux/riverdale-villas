import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  await createClient().auth.signOut();
  const reason = new URL(request.url).searchParams.get("reason");
  const msg = reason === "inactive" ? "?error=" + encodeURIComponent("Your account is not active. Contact the Director.") : "";
  return NextResponse.redirect(new URL("/login" + msg, request.url));
}
