// Supabase Edge Function: IGDB API proxy
// Handles Twitch OAuth token management and forwards queries to IGDB.
// Deploy with: supabase functions deploy igdb-proxy
//
// Required secrets (set via: supabase secrets set KEY=value):
//   IGDB_CLIENT_ID     — from dev.twitch.tv
//   IGDB_CLIENT_SECRET — from dev.twitch.tv

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Token cache (in-memory, reused across warm invocations)
let cachedToken: string | null = null;
let tokenExpiry = 0;

async function getTwitchToken(): Promise<string> {
  if (cachedToken && Date.now() < tokenExpiry) return cachedToken;

  const clientId = Deno.env.get('IGDB_CLIENT_ID');
  const clientSecret = Deno.env.get('IGDB_CLIENT_SECRET');

  if (!clientId || !clientSecret) {
    throw new Error('IGDB credentials not configured. Set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET secrets.');
  }

  const res = await fetch(
    `https://id.twitch.tv/oauth2/token?client_id=${clientId}&client_secret=${clientSecret}&grant_type=client_credentials`,
    { method: 'POST' }
  );

  if (!res.ok) throw new Error(`Twitch auth failed: ${res.status}`);
  const json = await res.json();

  cachedToken = json.access_token;
  tokenExpiry = Date.now() + (json.expires_in - 300) * 1000; // 5 min buffer
  return cachedToken!;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  try {
    const { endpoint, query } = await req.json();

    if (!endpoint || !query) {
      return new Response(JSON.stringify({ error: 'endpoint and query required' }), {
        status: 400,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const clientId = Deno.env.get('IGDB_CLIENT_ID');
    const token = await getTwitchToken();

    const igdbRes = await fetch(`https://api.igdb.com/v4/${endpoint}`, {
      method: 'POST',
      headers: {
        'Client-ID': clientId!,
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'text/plain',
      },
      body: query,
    });

    if (!igdbRes.ok) {
      const text = await igdbRes.text();
      return new Response(JSON.stringify({ error: text }), {
        status: igdbRes.status,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const data = await igdbRes.json();
    return new Response(JSON.stringify(data), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }
});
