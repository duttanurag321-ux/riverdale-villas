import type { Config } from "tailwindcss";
const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: { extend: { colors: { navy: { 900: "#0f1f3d", 700: "#1e3560" }, brand: { DEFAULT: "#2f5d8a", dark: "#244a6f" }, moss: "#3f7d5c" } } },
  plugins: [],
};
export default config;
