import { SubmitButton } from "@/components/SubmitButton";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Card, Field, Flash, btnCls, inputCls } from "@/components/ui";
import { back } from "@/lib/forms";

async function setPassword(fd: FormData) {
  "use server";
  const pw = String(fd.get("password") ?? "");
  if (pw.length < 10) back("/reset-password", "error", "Use at least 10 characters.");
  if (pw !== String(fd.get("confirm") ?? "")) back("/reset-password", "error", "The two passwords do not match.");
  const { error } = await createClient().auth.updateUser({ password: pw });
  if (error) back("/reset-password", "error", "Could not update the password. Request a new link.");
  redirect("/dashboard");
}

export default async function ResetPage({ searchParams }: { searchParams: { error?: string } }) {
  const { data: { user } } = await createClient().auth.getUser();
  if (!user) redirect("/login");
  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-sm"><Card>
        <h1 className="mb-4 text-lg font-semibold">Choose a new password</h1>
        <Flash error={searchParams.error} />
        <form action={setPassword} className="space-y-4">
          <Field label="New password" hint="At least 10 characters."><input name="password" type="password" required minLength={10} autoComplete="new-password" className={inputCls} /></Field>
          <Field label="Confirm password"><input name="confirm" type="password" required minLength={10} autoComplete="new-password" className={inputCls} /></Field>
          <SubmitButton className={`${btnCls} w-full`}>Save password</SubmitButton>
        </form>
      </Card></div>
    </main>
  );
}
