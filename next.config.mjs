/** @type {import('next').NextConfig} */
const nextConfig = { reactStrictMode: true, poweredByHeader: false,
  // Pages you just visited reopen instantly (back button, tabs). Mutations call revalidatePath, so data is not left stale.
  experimental: { staleTimes: { dynamic: 30, static: 180 } } };
export default nextConfig;
