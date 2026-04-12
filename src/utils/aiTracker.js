// AI Tracker Generator — calls the Supabase Edge Function to generate
// structured tracker data via Claude API.

const FUNCTION_URL = 'https://sextftevxqrtodlmnyve.supabase.co/functions/v1/ai-tracker-generator';

/**
 * Generate structured tracker data for a game.
 *
 * @param {object} params
 * @param {string} params.gameName — the game's display name
 * @param {object} [params.igdbData] — IGDB metadata (genres, themes, etc.)
 * @param {'auto'|'url'|'paste'|'file'} [params.mode='auto'] — source mode
 * @param {string} [params.payload] — URL, pasted text, or base64 file content
 * @returns {Promise<{ structuredData: object, usage: object|null }>}
 * @throws {Error} on network/API failure
 */
export async function generateTrackerData({ gameName, igdbData, mode = 'auto', payload }) {
  const res = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ gameName, igdbData, mode, payload }),
  });

  const data = await res.json();

  if (!res.ok) {
    throw new Error(data.error || `Generator failed (${res.status})`);
  }

  if (!data.structuredData) {
    throw new Error(data.error || 'No tracker data returned');
  }

  return data;
}
