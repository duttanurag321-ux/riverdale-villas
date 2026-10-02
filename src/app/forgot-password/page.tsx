import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Card, Field, Flash, btnCls, inputCls } from "@/components/ui";
import { back, str } from "@/lib/forms";

async function requestReset(fd: FormData) {
  "use server";
  const sb = createClient();
  const base = process.env.APP_BASE_URL ?? "http://localhost:3000";
  await sb.auth.resetPasswordForEmail(str(fd, "email"), { redirectTo: `${base}/auth/callback?next=/reset-password` });
  // Same message whether or not the email exists, so accounts cannot be probed.
  back("/forgot-password", "ok", "If that email has an account, a reset link has been sent.");
}

export default function ForgotPage({ searchParams }: { searchParams: { error?: string; ok?: string } }) {
  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-sm"><Card>
        <h1 className="mb-4 text-lg font-semibold">Reset your password</h1>
        <Flash error={searchParams.error} ok={searchParams.ok} />
        <form action={requestReset} className="space-y-4">
          <Field label="Email"><input name="email" type="email" required className={inputCls} /></Field>
          <button className={`${btnCls} w-full`}>Send reset link</button>
        </form>
        <div className="mt-4 text-center text-sm"><Link href="/login" className="text-brand underline">Back to login</Link></div>
      </Card></div>
    </main>
  );
}
