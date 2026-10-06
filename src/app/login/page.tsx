import { SubmitButton } from "@/components/SubmitButton";
import Link from "next/link";
import { login } from "./actions";
import { Card, Field, Flash, btnCls, inputCls } from "@/components/ui";

export default function LoginPage({ searchParams }: { searchParams: { error?: string } }) {
  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <div className="mb-6 text-center"><h1 className="text-2xl font-semibold">Riverdale Villas</h1><p className="text-sm text-slate-500">Construction &amp; Payment Management System</p></div>
        <Card>
          <Flash error={searchParams.error} />
          <form action={login} className="space-y-4">
            <Field label="Email"><input name="email" type="email" required autoComplete="username" className={inputCls} /></Field>
            <Field label="Password"><input name="password" type="password" required autoComplete="current-password" className={inputCls} /></Field>
            <SubmitButton className={`${btnCls} w-full`}>Log in</SubmitButton>
          </form>
          <div className="mt-4 text-center text-sm"><Link href="/forgot-password" className="text-brand underline">Forgot password?</Link></div>
        </Card>
        <p className="mt-4 text-center text-xs text-slate-500">Accounts are created by the Director. There is no public sign-up.</p>
      </div>
    </main>
  );
}
