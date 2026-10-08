"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, opt, str } from "@/lib/forms";
import { normalizePhone } from "@/lib/format";

export async function createCustomer(fd: FormData) {
  await requireMe(["director"]);
  const sb = createClient(); const P = "/customers/new";
  const name = str(fd, "full_name"); if (!name) back(P, "error", "Name is required.");
  const phone = normalizePhone(str(fd, "phone")); if (!phone) back(P, "error", "Enter a valid mobile number (10 digits, or +country code).");
  const altRaw = str(fd, "alt_phone"); const alt = altRaw ? normalizePhone(altRaw) : null;
  if (altRaw && !alt) back(P, "error", "Alternate number is not valid.");
  const email = opt(fd, "email"); if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) back(P, "error", "Email address is not valid.");
  const pan = str(fd, "pan").toUpperCase(); if (pan && !/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(pan)) back(P, "error", "PAN must look like ABCDE1234F.");
  const optIn = fd.get("whatsapp_opt_in") === "on";

  const { data, error } = await sb.from("customers").insert({
    full_name: name, phone, alt_phone: alt, email, address: opt(fd, "address"), notes: opt(fd, "notes"),
    salesperson_id: opt(fd, "salesperson_id"), whatsapp_opt_in: optIn, whatsapp_opt_in_at: optIn ? new Date().toISOString() : null,
  }).select("id").single();
  if (error) back(P, "error", friendly(error));
  if (pan) {
    const { error: e2 } = await sb.from("customer_sensitive").insert({ customer_id: data!.id, pan });
    if (e2) { await sb.from("customers").delete().eq("id", data!.id); back(P, "error", friendly(e2)); }
  }
  back("/customers", "ok", `Customer ${name} added.`);
}

export async function updateCustomer(fd: FormData) {
  await requireMe(["director"]);
  const sb = createClient(); const id = str(fd, "id"); const P = `/customers/${id}/edit`;
  const name = str(fd, "full_name"); if (!name) back(P, "error", "Name is required.");
  const phone = normalizePhone(str(fd, "phone")); if (!phone) back(P, "error", "Enter a valid mobile number.");
  const altRaw = str(fd, "alt_phone"); const alt = altRaw ? normalizePhone(altRaw) : null; if (altRaw && !alt) back(P, "error", "Alternate number is not valid.");
  const email = opt(fd, "email"); if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) back(P, "error", "Email address is not valid.");
  const pan = str(fd, "pan").toUpperCase(); if (pan && !/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(pan)) back(P, "error", "PAN must look like ABCDE1234F.");
  const { data: cur } = await sb.from("customers").select("whatsapp_opt_in, whatsapp_opt_in_at").eq("id", id).maybeSingle();
  const optIn = fd.get("whatsapp_opt_in") === "on";
  const patch = { full_name: name, phone, alt_phone: alt, email, address: opt(fd, "address"), notes: opt(fd, "notes"), salesperson_id: opt(fd, "salesperson_id"), is_archived: fd.get("is_archived") === "on",
    whatsapp_opt_in: optIn, whatsapp_opt_in_at: optIn ? (cur?.whatsapp_opt_in ? cur.whatsapp_opt_in_at : new Date().toISOString()) : cur?.whatsapp_opt_in_at ?? null };
  const { error } = await sb.from("customers").update(patch).eq("id", id);
  if (error) back(P, "error", error.code === "23505" ? "Another customer already has that number." : friendly(error));
  if (fd.get("remove_pan") === "on") await sb.from("customer_sensitive").delete().eq("customer_id", id);
  else if (pan) { const { error: e2 } = await sb.from("customer_sensitive").upsert({ customer_id: id, pan }); if (e2) back(P, "error", friendly(e2)); }
  back("/customers", "ok", "Customer updated.");
}
