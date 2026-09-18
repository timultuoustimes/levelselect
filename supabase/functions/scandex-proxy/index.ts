// Supabase Edge Function: ScanDex proxy
// A game's barcode → its IGDB id, from ScanDex (scandex.gamery.app, by the
// Gamery team). Deploy with: supabase functions deploy scandex-proxy
//
// Required secret (set via: supabase secrets set SCANDEX_TOKEN=value):
//   SCANDEX_TOKEN — the access token from a ScanDex developer account
//
// Why a proxy: ScanDex issues one token per account, and a token inside the
// app is a token anyone can lift. It also keeps ScanDex's terms in one place
// — the API is "free during the launch period", and if that changes, this is
// the one file that changes.
//
// What goes to ScanDex: the barcode number, and — only when someone picks the
// game by hand after ScanDex didn't know it — that barcode with the game they
// picked, to help the database grow. Nothing about the person.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';

const API = 'https://scandex.gamery.app/api/v2';
const BARCODE = /^[0-9]{8,14}$/;

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const { rejection, body } = await guard(req, {
    fn: 'scandex',
    maxBodyBytes: 2_000,
    quotas: [
      { scope: 'install', windowSeconds: 3_600, limit: 120 },
      { scope: 'global', windowSeconds: 86_400, limit: 20_000 },
    ],
    onQuotaError: 'allow',
  });
  if (rejection) return rejection;

  const token = Deno.env.get('SCANDEX_TOKEN');
  if (!token) {
    console.error('SCANDEX_TOKEN not configured');
    return jsonResponse({ error: 'Barcode lookups are not set up yet.' }, 503);
  }

  const mode = typeof body?.mode === 'string' ? body.mode : 'lookup';
  const value = typeof body?.value === 'string' ? body.value.trim() : '';
  if (!BARCODE.test(value)) {
    return jsonResponse({ error: 'value must be an 8–14 digit barcode.' }, 400);
  }

  try {
    // ── lookup: what game is this barcode?
    if (mode === 'lookup') {
      const res = await fetch(`${API}/lookup?value=${value}`, {
        headers: { Authorization: token, Accept: 'application/json' },
      });
      if (res.status === 404) return jsonResponse({ status: 'unknown' });
      if (!res.ok) {
        console.error('scandex lookup failed:', res.status);
        return jsonResponse({ error: 'ScanDex is unavailable right now.' }, 502);
      }
      const json = await res.json();
      const meta = json?.igdb_metadata;
      if (!meta || !Number.isInteger(meta.id)) return jsonResponse({ status: 'unmatched' });
      return jsonResponse({
        status: 'matched',
        igdbID: meta.id,
        name: typeof meta.name === 'string' ? meta.name : null,
        platform: typeof meta.platform?.name === 'string' ? meta.platform.name : null,
        platformID: Number.isInteger(meta.platform?.id) ? meta.platform.id : null,
      });
    }

    // ── suggest: the game someone picked for a barcode ScanDex didn't know.
    if (mode === 'suggest') {
      const igdbID = Number.isInteger(body?.igdbID) ? Number(body.igdbID) : 0;
      const platformID = Number.isInteger(body?.platformID) ? Number(body.platformID) : 0;
      const platform = typeof body?.platform === 'string' ? body.platform.slice(0, 120) : '';
      const name = typeof body?.name === 'string' ? body.name.slice(0, 200) : '';
      if (igdbID <= 0 || platformID <= 0 || !platform || !name) {
        return jsonResponse({ error: 'igdbID, platformID, platform and name are required.' }, 400);
      }
      const res = await fetch(`${API}/create`, {
        method: 'POST',
        headers: { Authorization: token, 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ igdb_id: igdbID, platform_id: platformID, platform, name, value: Number(value) }),
      });
      if (!res.ok) {
        console.error('scandex create failed:', res.status);
        return jsonResponse({ ok: false }, 502);
      }
      return jsonResponse({ ok: true });
    }

    return jsonResponse({ error: 'Unknown mode.' }, 400);
  } catch (err) {
    console.error('scandex error:', err);
    return jsonResponse({ error: 'ScanDex is unavailable right now.' }, 502);
  }
});
