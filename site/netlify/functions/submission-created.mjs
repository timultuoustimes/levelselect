// site/netlify/functions/submission-created.mjs
//
// Fires automatically on every verified Netlify Forms submission (the name
// is reserved — Netlify wires it up by existing). Sends a push through an
// ntfy topic so an invite request reaches the phone the moment it arrives,
// with a reminder of the one manual step: add them to the Player 1 group.
//
// Mirrors the pattern proven on stonewall-project-planner's
// consultation-intake: env-driven, best-effort, and PII-minimal — an ntfy
// topic URL is a shared secret, not an account, so the push carries the
// answers but NOT the email address. The email lives in the Netlify Forms
// dashboard (one tap away via the Click action) and in the local ledger
// poller, both of which are actually private.
//
// Env (set in the Netlify UI, not in the repo — the repo is public):
//   INVITE_PUSH_WEBHOOK_URL   ntfy topic URL (e.g. https://ntfy.sh/<topic>).
//                             Unset → function logs and does nothing.

const FORMS_DASHBOARD = 'https://app.netlify.com/projects/levelselect-app/forms';

/** Netlify stores repeated checkbox fields as string or array by era. */
function many(value) {
  if (Array.isArray(value)) return value.filter(Boolean).join(', ');
  return value || '';
}

export default async (req) => {
  const { payload } = await req.json();
  if (payload?.form_name !== 'invite') return new Response('ignored', { status: 200 });

  const url = Netlify.env.get('INVITE_PUSH_WEBHOOK_URL');
  if (!url) {
    console.warn('[submission-created] INVITE_PUSH_WEBHOOK_URL not set — push skipped.');
    return new Response('no push target', { status: 200 });
  }

  const d = payload.data || {};
  const lines = [
    many(d.platforms) && `Plays: ${many(d.platforms)}`,
    many(d.devices) && `Devices: ${many(d.devices)}`,
    d.tracking && `Tracks today: ${d.tracking}`,
    d.tool && `Leaving: ${d.tool}`,
    d.wants && `Wants: ${String(d.wants).slice(0, 140)}`,
    '→ Add them to Player 1 in TestFlight',
  ].filter(Boolean);

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      Title: 'LevelSelect: new invite request',
      Tags: 'video_game',
      Priority: 'high',
      Click: FORMS_DASHBOARD,
    },
    body: lines.join('\n'),
  });
  if (!resp.ok) {
    console.error(`[submission-created] ntfy ${resp.status}: ${await resp.text()}`);
    return new Response('push failed', { status: 200 });
  }
  console.log('[submission-created] push sent.');
  return new Response('ok', { status: 200 });
};
