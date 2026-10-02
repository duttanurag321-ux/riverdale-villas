import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = { title: "Riverdale Villas — Construction & Payment Management System" };
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#0f1f3d" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (<html lang="en-IN"><body>{children}</body></html>);
}
