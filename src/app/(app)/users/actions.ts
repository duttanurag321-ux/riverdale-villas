"use server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { requireMe } from "@/lib/auth";
import { back, friendly, opt, str } from "@/lib/forms";

const ROLES = ["site_manager", "salesperson", "director"];

export async function createEmployee(fd: FormData) {
  await requireMe(["director"]);                      // authorisation checked on the server, from the profiles table
  const P = "/users";
  const email = str(fd, "email").toLowerCase(), name = str(fd, "full_name"), role = str(fd, "role"), pw = String(fd.get("password") ?? "");
  if (!name || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) back(P, "error", "Enter a name and a valid email.");
  if (!ROLES.includes(role)) back(P, "error", "Choose a role.");
  if (pw.length < 10) back(P, "error", "Temporary password must be at least 10 characters.");

  const admin = createAdminClient();
  const { data, error } = await admin.auth.admin.createUser({ email, password: pw, email_confirm: true });
  if (error || !data.user) back(P, "error", error?.message?.includes("already") ? "That email already has an account." : "Could not create the login.");
  const { error: pErr } = await admin.from("profiles").insert({ id: data.user!.id, full_name: name, phone: opt(fd, "phone"), role });
  if (pErr) { await admin.auth.admin.deleteUser(data.user!.id); back(P, "error", friendly(pErr)); }
  back(P, "ok", `${name} can now log in. Share the temporary password privately and ask them to use “Forgot password” to choose their own.`);
}

export async function setActive(fd: FormData) {
  const me = await requireMe(["director"]);
  const id = str(fd, "id"), active = str(fd, "active") === "true";
  if (id === me.id && !active) back("/users", "error", "You cannot deactivate your own account.");
  const { error } = await createClient().from("profiles").update({ is_active: active }).eq("id", id);
  if (error) back("/users", "error", friendly(error));
  back("/users", "ok", active ? "Account reactivated." : "Account deactivated. They can no longer use the app.");
}
