import type { Metadata, Viewport } from "next";
import { Suspense } from "react";
import "./globals.css";
import TopProgress from "@/components/TopProgress";

export const metadata: Metadata = { title: "Riverdale Villas — Construction & Payment Management System" };
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#0f1f3d" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (<html lang="en-IN"><body><Suspense fallback={null}><TopProgress /></Suspense>{children}</body></html>);
}
