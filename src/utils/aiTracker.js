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
  // Supabase free-tier Edge Functions have a 150s wall-clock limit.
  // Use AbortController to surface a clear error instead of a generic network failure.
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 140_000); // 140s — just under the 150s limit

  let res;
  try {
    res = await fetch(FUNCTION_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ gameName, igdbData, mode, payload }),
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(timeout);
    if (err.name === 'AbortError') {
      throw new Error(
        'Generation timed out — the AI took too long. Try "Paste text" mode instead of Auto, or try a simpler game.'
      );
    }
    throw new Error('Network error — check your connection and try again.');
  }
  clearTimeout(timeout);

  let data;
  try {
    data = await res.json();
  } catch {
    throw new Error(`Server returned an invalid response (${res.status}). Try again.`);
  }

  if (!res.ok) {
    // Surface the specific error from Supabase or the Edge Function
    const detail = data.detail || data.message || '';
    if (res.status === 546 || res.status === 504) {
      throw new Error(
        'Generation timed out on the server. Try "Paste text" mode for faster results.'
      );
    }
    throw new Error(data.error || `Generator failed (${res.status})${detail ? ': ' + detail : ''}`);
  }

  if (!data.structuredData) {
    throw new Error(data.error || 'No tracker data returned');
  }

  return data;
}
