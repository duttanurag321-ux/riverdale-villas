"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, opt, str } from "@/lib/forms";
import { rupeesToPaise } from "@/lib/format";

export async function createVilla(fd: FormData) {
  await requireMe(["director"]);
  const sb = createClient();
  const P = "/villas/new";
  let projectId = str(fd, "project_id");
  const newProject = str(fd, "new_project");
  const villaNumber = str(fd, "villa_number");
  if (!villaNumber) back(P, "error", "Villa number is required.");
  const price = rupeesToPaise(str(fd, "price"));
  if (!price) back(P, "error", "Enter a valid list price in rupees, for example 6000000 or 60,00,000.");
  const area = opt(fd, "land_area");
  if (area && !(Number(area) > 0)) back(P, "error", "Land area must be a positive number.");

  if (newProject) {
    const { data, error } = await sb.from("projects").insert({ name: newProject, city: opt(fd, "city") }).select("id").single();
    if (error) back(P, "error", friendly(error));
    projectId = data!.id;
  }
  if (!projectId) back(P, "error", "Choose a project or enter a new project name.");

  const { data: villa, error } = await sb.from("villas").insert({
    project_id: projectId, villa_number: villaNumber, configuration: opt(fd, "configuration"), plot_details: opt(fd, "plot_details"),
    land_area: area ? Number(area) : null, land_unit: str(fd, "land_unit") || "katha",
    site_manager_id: opt(fd, "site_manager_id"), salesperson_id: opt(fd, "salesperson_id"), expected_completion: opt(fd, "expected_completion"),
  }).select("id").single();
  if (error) back(P, "error", error.code === "23505" ? "A villa with that number already exists in this project." : friendly(error));

  const { error: pErr } = await sb.from("villa_pricing").insert({ villa_id: villa!.id, list_price_paise: price });
  if (pErr) { await sb.from("villas").delete().eq("id", villa!.id); back(P, "error", friendly(pErr)); }
  back("/villas", "ok", `Villa ${villaNumber} created.`);
}

export async function updateVilla(fd: FormData) {
  await requireMe(["director"]);
  const sb = createClient(); const id = str(fd, "id"); const P = `/villas/${id}/edit`;
  const price = rupeesToPaise(str(fd, "price")); if (!price) back(P, "error", "Enter a valid list price in rupees.");
  const area = opt(fd, "land_area"); if (area && !(Number(area) > 0)) back(P, "error", "Land area must be a positive number.");
  const patch: Record<string, unknown> = { configuration: opt(fd, "configuration"), plot_details: opt(fd, "plot_details"), land_area: area ? Number(area) : null,
    land_unit: str(fd, "land_unit") || "katha", site_manager_id: opt(fd, "site_manager_id"), salesperson_id: opt(fd, "salesperson_id"), expected_completion: opt(fd, "expected_completion"), remarks: opt(fd, "remarks") };
  const status = str(fd, "status"); if (["available", "reserved", "inactive"].includes(status)) patch.status = status;   // other statuses follow bookings and construction automatically
  const { error } = await sb.from("villas").update(patch).eq("id", id);
  if (error) back(P, "error", friendly(error));
  const { error: pErr } = await sb.from("villa_pricing").upsert({ villa_id: id, list_price_paise: price });
  if (pErr) back(P, "error", friendly(pErr));
  back("/villas", "ok", "Villa updated.");
}
