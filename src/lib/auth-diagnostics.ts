/** Server diagnostic fields only. Never pass raw errors or Auth responses to a logger. */
/** Redact before truncating so a cut-off secret cannot leave a visible prefix. */
export function redactAuthText(value: string, sensitiveValues: readonly string[] = []): string {
  let text = value;
  for (let pass = 0; pass < 3; pass++) {
    try {
      const decoded = decodeURIComponent(text);
      if (decoded === text) break;
      text = decoded;
    } catch { break; }
  }
  text = text.replace(/&#(?:x([0-9a-f]+)|(\d+));/gi, (_match, hex, decimal) => {
    const point = Number.parseInt(hex ?? decimal, hex ? 16 : 10);
    return point <= 0x10ffff ? String.fromCodePoint(point) : "";
  });
  for (const secret of [...sensitiveValues].filter(Boolean).sort((a, b) => b.length - a.length)) {
    text = text.split(secret).join("[REDACTED]");
  }
  text = text
    // Embedded credential-bearing objects/headers/bodies are never diagnostic text.
    .replace(/\{[^\n]*"(?:access_token|refresh_token|session|cookie|password|authorization)"\s*:[^\n]*\}/gi, "[REDACTED OBJECT]")
    .replace(/\b(?:authorization|cookie|set-cookie|request[ _-]?body|response[ _-]?body|session)\s*[:=][^\r\n]*/gi, "[REDACTED FIELD]")
    .replace(/\bBearer\s+[^\s,;]+/gi, "Bearer [REDACTED]")
    .replace(/\b[a-z][a-z0-9+.-]*:\/\/[^\s<>"']+/gi, "[REDACTED URL]")
    .replace(/(?:\/\/|www\.)[a-z0-9][^\s<>"']+/gi, "[REDACTED URL]")
    .replace(/[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9.-]+/gi, "[REDACTED EMAIL]")
    .replace(/(["']?(?:api[ _-]?key|access[ _-]?token|refresh[ _-]?token|token(?:[ _-]?hash)?|password|passwd|secret|smtp[ _-]?(?:user(?:name)?|pass(?:word)?)))["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;<>]+)/gi, "$1=[REDACTED]")
    .replace(/\b(?:sb_(?:secret|publishable)_[a-z0-9_-]+|re_[a-z0-9_-]+|eyJ[a-z0-9_-]+\.[a-z0-9_-]+\.[a-z0-9_-]+)\b/gi, "[REDACTED CREDENTIAL]")
    .replace(/[A-Za-z0-9_=-]{24,}/g, (word) => {
      // Preserve descriptive snake_case error codes, without a provider-code whitelist.
      return /^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$/i.test(word) || /^(?:[A-Z][a-z]+){2,}Error$/.test(word)
        ? word : "[REDACTED OPAQUE VALUE]";
    })
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ");
  return text.replace(/\s+/g, " ").trim().slice(0, 600);
}

function httpStatus(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 100 && value <= 599 ? value : null;
}

export interface AuthDiagnostic {
  method: "signInWithOtp";
  stage: "response" | "exception" | "setup";
  httpStatus: number | null;
  supabaseErrorCode: string | null;
  name: string | null;
  message: string;
}

export function sanitizedAuthDiagnostic(
  error: unknown,
  status: number | null,
  stage: AuthDiagnostic["stage"],
  sensitiveValues: readonly string[] = [],
): AuthDiagnostic {
  const fields = error !== null && typeof error === "object" ? error as Record<string, unknown> : {};
  const clean = (value: unknown): string | null => typeof value === "string" && value.trim()
    ? redactAuthText(value, sensitiveValues) : null;
  return {
    method: "signInWithOtp",
    stage,
    httpStatus: httpStatus(status) ?? httpStatus(fields.status),
    supabaseErrorCode: clean(fields.code),
    name: clean(fields.name),
    message: clean(fields.message) ?? (!error && stage === "response"
      ? "Supabase Auth accepted the request; email delivery is not confirmed."
      : "Auth request failed without a readable error message."),
  };
}

export function reportAuthDiagnostic(
  environment: string | undefined,
  error: unknown,
  status: number | null,
  stage: AuthDiagnostic["stage"],
  write: (diagnostic: AuthDiagnostic) => void,
  sensitiveValues: readonly string[] = [],
): void {
  if (environment !== "development") return;
  write(sanitizedAuthDiagnostic(error, status, stage, sensitiveValues));
}

/** Observe status only; never inspect/log URLs, headers, bodies, or response data. */
export function statusObservingFetch(fetcher: typeof fetch, observe: (status: number) => void): typeof fetch {
  return async (input, init) => {
    const response = await fetcher(input, { ...init, cache: "no-store" });
    observe(response.status);
    return response;
  };
}
