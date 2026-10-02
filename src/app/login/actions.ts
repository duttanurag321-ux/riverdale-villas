"use server";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { back, str } from "@/lib/forms";

export async function login(fd: FormData) {
  const sb = createClient();
  const { error } = await sb.auth.signInWithPassword({ email: str(fd, "email"), password: String(fd.get("password") ?? "") });
  if (error) back("/login", "error", "Invalid email or password.");
  redirect("/dashboard");
}
