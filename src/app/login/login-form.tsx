"use client";

import { useActionState, useState, useSyncExternalStore } from "react";
import { requestLink } from "./actions";
import { readRememberedEmail, saveRememberedEmail } from "@/lib/remembered-email";

const CHANGE_EVENT = "remembered-email-change";
function subscribe(callback: () => void) {
  window.addEventListener("storage", callback);
  window.addEventListener(CHANGE_EVENT, callback);
  return () => {
    window.removeEventListener("storage", callback);
    window.removeEventListener(CHANGE_EVENT, callback);
  };
}
function snapshot() {
  try { return readRememberedEmail(window.localStorage); } catch { return ""; }
}

export function LoginForm({ initialMessage }: { initialMessage: string }) {
  const [state, action, pending] = useActionState(requestLink, { message: initialMessage });
  const rememberedEmail = useSyncExternalStore(subscribe, snapshot, () => "");
  const [email, setEmail] = useState<string | null>(null);
  const [rememberChoice, setRememberChoice] = useState<boolean | null>(null);
  const remember = rememberChoice ?? Boolean(rememberedEmail);
  function save(email: string, selected: boolean) {
    try { saveRememberedEmail(window.localStorage, email, selected); } catch { /* Storage may be disabled. */ }
    window.dispatchEvent(new Event(CHANGE_EVENT));
  }
  return (
    <form action={action} onSubmit={(event) => {
      const form = new FormData(event.currentTarget);
      save(String(form.get("email") ?? ""), remember);
    }} className="space-y-5">
      <div>
        <label htmlFor="email" className="mb-2 block font-medium">Email address</label>
        <input id="email" name="email" type="email" autoComplete="email" required maxLength={254}
          value={email ?? rememberedEmail} onChange={(event) => setEmail(event.target.value)} className="w-full rounded-lg border border-slate-400 bg-white px-3 py-3 text-slate-950 focus:outline-2 focus:outline-offset-2 focus:outline-slate-700" />
      </div>
      <label className="flex items-start gap-3 text-sm">
        <input type="checkbox" className="mt-1" checked={remember} onChange={(event) => {
          setRememberChoice(event.target.checked);
          if (!event.target.checked) {
            setEmail((current) => current ?? rememberedEmail);
            save("", false);
          }
        }} />
        Remember my email on this device
      </label>
      <button type="button" className="text-sm underline underline-offset-4" onClick={() => {
        setRememberChoice(false); setEmail(""); save("", false);
      }}>Clear remembered email</button>
      <button type="submit" disabled={pending} className="block w-full rounded-lg bg-slate-900 px-4 py-3 font-semibold text-white disabled:opacity-60">
        {pending ? "Requesting link…" : "Email me a sign-in link"}
      </button>
      <p role="status" aria-live="polite" className="text-sm leading-6">{state.message}</p>
    </form>
  );
}
