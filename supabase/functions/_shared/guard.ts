// Shared request guard for LevelSelect's public edge functions.
//
// These functions run with `verify_jwt = false` (the app has no Supabase auth
// session), so without this they are open endpoints on the public internet.
// The guard adds, in order: a kill switch, an app-key check, a body-size cap,
// and per-install + global quotas backed by Postgres.
//
// NOTE ON THE APP KEY: `LS_APP_SECRET` is shipped inside the iOS binary, so it
// is obfuscation, not authentication — it stops drive-by and scripted abuse,
// not someone who pulls strings out of the app. The quotas below are the real
// spend ceiling. Treat the key as a filter, the quotas as the limit.
//
// Required secrets (supabase secrets set KEY=value):
//   LS_APP_SECRET  — shared with the app; when UNSET the key check is skipped
//                    (lets a hardened function deploy before the app ships the
//                    header — set it only once a build sending it is live).
//   LS_KILL_<FN>   — set to "off" to disable one function (e.g. LS_KILL_AI=off).
// Auto-injected by Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

export const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-ls-app-key, x-ls-install',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

export interface QuotaRule {
  /** Bucket scope: per-install, or shared across every caller. */
  scope: 'install' | 'global';
  /** Window length in seconds. */
  windowSeconds: number;
  /** Max requests allowed inside the window. */
  limit: number;
}

export interface GuardOptions {
  /** Short function name — used in bucket keys and the kill-switch env var. */
  fn: string;
  /** Kill-switch env var (defaults to `LS_KILL_<FN uppercased>`). */
  killSwitchEnv?: string;
  /** Reject bodies larger than this many bytes. */
  maxBodyBytes: number;
  /** Quota rules, checked in order. */
  quotas: QuotaRule[];
  /**
   * What to do when the quota store itself is unreachable. Expensive functions
   * (anything calling a paid API) should `deny`; cheap proxies may `allow`.
   */
  onQuotaError: 'allow' | 'deny';
}

export interface GuardResult {
  /** Set when the request must be rejected — return this verbatim. */
  rejection?: Response;
  /** Parsed JSON body, available when the request passed. */
  body?: Record<string, unknown>;
  /** Opaque per-install identifier, for logging. */
  installID: string;
}

/** Stable-ish caller identity: the app's install UUID, else the client IP. */
function callerID(req: Request): string {
  const install = req.headers.get('x-ls-install');
  if (install && /^[A-Za-z0-9-]{8,64}$/.test(install)) return install;
  const forwarded = req.headers.get('x-forwarded-for') ?? '';
  return `ip:${forwarded.split(',')[0].trim() || 'unknown'}`;
}

async function checkQuotas(
  fn: string,
  installID: string,
  quotas: QuotaRule[],
): Promise<{ ok: boolean; detail?: string; errored?: boolean }> {
  if (quotas.length === 0) return { ok: true };

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return { ok: false, errored: true };

  // Bucket key pins the window so a new window starts a fresh counter.
  const now = Math.floor(Date.now() / 1000);
  const buckets = quotas.map((q) => {
    const scope = q.scope === 'install' ? installID : 'all';
    const window = Math.floor(now / q.windowSeconds) * q.windowSeconds;
    return `${fn}:${scope}:${q.windowSeconds}:${window}`;
  });

  try {
    const res = await fetch(`${url}/rest/v1/rpc/consume_quota`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: key,
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        p_buckets: buckets,
        p_limits: quotas.map((q) => q.limit),
        p_ttls: quotas.map((q) => q.windowSeconds),
      }),
    });

    if (!res.ok) {
      console.error(`quota rpc failed: ${res.status} ${await res.text()}`);
      return { ok: false, errored: true };
    }

    const result = await res.json();
    if (result?.allowed === true) return { ok: true };
    return {
      ok: false,
      detail: `${result?.count}/${result?.limit} in bucket ${result?.bucket}`,
    };
  } catch (err) {
    console.error('quota rpc threw:', String(err));
    return { ok: false, errored: true };
  }
}

/**
 * Run every check for one request. Returns `{ rejection }` to stop, or
 * `{ body }` to proceed. Callers must handle OPTIONS before calling this.
 */
export async function guard(req: Request, opts: GuardOptions): Promise<GuardResult> {
  const installID = callerID(req);

  // 1. Kill switch — flip a secret to take a function offline without a deploy.
  const killEnv = opts.killSwitchEnv ?? `LS_KILL_${opts.fn.toUpperCase()}`;
  if ((Deno.env.get(killEnv) ?? '').toLowerCase() === 'off') {
    return {
      installID,
      rejection: jsonResponse(
        { error: 'This feature is temporarily unavailable. Try again later.' },
        503,
      ),
    };
  }

  // 2. App key. Skipped while LS_APP_SECRET is unset (rollout escape hatch).
  const expected = Deno.env.get('LS_APP_SECRET');
  if (expected) {
    const provided = req.headers.get('x-ls-app-key') ?? '';
    // Length-independent compare is overkill here (the secret ships in the
    // binary), but constant-ish comparison costs nothing.
    if (provided.length !== expected.length || provided !== expected) {
      console.warn(`rejected: bad app key (fn=${opts.fn} caller=${installID})`);
      return {
        installID,
        rejection: jsonResponse({ error: 'Not available.' }, 401),
      };
    }
  }

  // 3. Body size — read as text so we cap before parsing.
  const raw = await req.text();
  if (raw.length > opts.maxBodyBytes) {
    console.warn(
      `rejected: body ${raw.length}B > ${opts.maxBodyBytes}B (fn=${opts.fn} caller=${installID})`,
    );
    return {
      installID,
      rejection: jsonResponse({ error: 'Request too large.' }, 413),
    };
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw || '{}');
  } catch {
    return { installID, rejection: jsonResponse({ error: 'Invalid JSON body.' }, 400) };
  }

  // 4. Quotas.
  const quota = await checkQuotas(opts.fn, installID, opts.quotas);
  if (!quota.ok) {
    if (quota.errored && opts.onQuotaError === 'allow') {
      console.warn(`quota unavailable, allowing (fn=${opts.fn})`);
    } else if (quota.errored) {
      return {
        installID,
        rejection: jsonResponse(
          { error: 'This feature is temporarily unavailable. Try again later.' },
          503,
        ),
      };
    } else {
      console.warn(`rejected: quota (fn=${opts.fn} caller=${installID} ${quota.detail})`);
      return {
        installID,
        rejection: jsonResponse(
          { error: "You've hit the usage limit for now. Try again a bit later." },
          429,
        ),
      };
    }
  }

  return { installID, body };
}
