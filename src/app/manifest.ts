import type { MetadataRoute } from "next";
export default function manifest(): MetadataRoute.Manifest {
  return { name: "Riverdale Villas", short_name: "Riverdale", start_url: "/dashboard", display: "standalone", background_color: "#f8fafc", theme_color: "#0f1f3d" };
}
