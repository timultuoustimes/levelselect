// scripts/log-invite-submissions.mjs
//
// Pull new invite-form submissions from the Netlify API and append them to
// the Obsidian testers ledger, so the running log of beta users fills itself.
// Runs on this Mac (launchd, every 15 minutes) — the vault is local, so the
// logging has to be. The push notification half lives in
// site/netlify/functions/submission-created.mjs; this is the half with the
// email address in it, which is why it stays on the machine.
//
// Append-only by design: the ledger is a hand-edited note, so the script
// never rewrites anything — it adds "inbox" entries at the end, and
// promoting one to the roster table stays a human (or Claude) edit.
//
// Setup (once):
//   1. Personal access token: app.netlify.com/user/settings → Applications
//      → New access token. Save it:
//        mkdir -p ~/.config/levelselect
//        pbpaste > ~/.config/levelselect/netlify-token
//        chmod 600 ~/.config/levelselect/netlify-token
//   2. The launchd agent (com.levelselect.invite-poller) is installed by the
//      repo's setup; without the token this script exits quietly, so it is
//      safe to install first and provision later.
//
// No secrets live in this file — the repo is public.

import { readFileSync, writeFileSync, existsSync, appendFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

const SITE_NAME = process.env.LS_NETLIFY_SITE || 'levelselect-app';
const FORM_NAME = 'invite';
const TOKEN_PATH = join(homedir(), '.config/levelselect/netlify-token');
const SEEN_PATH = join(homedir(), '.config/levelselect/invite-seen.json');
const LEDGER = join(homedir(),
  'Obsidian Vault/MILWAP/dev/projects/LevelSelect/LevelSelect testers ledger.md');
const TALLY = join(homedir(),
  'Obsidian Vault/MILWAP/dev/projects/LevelSelect/LevelSelect invite tally.md');

if (!existsSync(TOKEN_PATH)) {
  console.log('[invite-poller] no token at ~/.config/levelselect/netlify-token — nothing to do.');
  process.exit(0);
}
const token = readFileSync(TOKEN_PATH, 'utf8').trim();
const auth = { headers: { Authorization: `Bearer ${token}` } };

const api = async (path) => {
  const resp = await fetch(`https://api.netlify.com/api/v1${path}`, auth);
  if (!resp.ok) throw new Error(`${path} → ${resp.status}`);
  return resp.json();
};

/** Checkbox groups arrive as string or array depending on Netlify's mood. */
const many = (v) => Array.isArray(v) ? v.filter(Boolean).join(', ') : (v || '');

const sites = await api('/sites');
const site = sites.find((s) => s.name === SITE_NAME);
if (!site) throw new Error(`site "${SITE_NAME}" not found for this token`);

const forms = await api(`/sites/${site.id}/forms`);
const form = forms.find((f) => f.name === FORM_NAME);
if (!form) {
  console.log(`[invite-poller] form "${FORM_NAME}" not registered yet — no submissions ever.`);
  process.exit(0);
}

const seen = existsSync(SEEN_PATH) ? JSON.parse(readFileSync(SEEN_PATH, 'utf8')) : [];
const submissions = await api(`/forms/${form.id}/submissions`);

// The tally regenerates from the COMPLETE submission list on every run —
// computed counts can't drift the way hand-maintained ones do. This note is
// machine-owned and overwritten wholesale; the ledger stays append-only.
writeTally(submissions);

const fresh = submissions.filter((s) => !seen.includes(s.id));
if (fresh.length === 0) {
  console.log('[invite-poller] nothing new (tally refreshed).');
  process.exit(0);
}

for (const s of fresh.reverse()) {  // oldest first, so the ledger reads in order
  const d = s.data || {};
  const date = (s.created_at || '').slice(0, 10);
  const block = [
    '',
    `### 📥 ${d.email || s.email || 'no email?!'} — requested ${date} *(auto-logged, promote to roster)*`,
    `- **Devices:** ${many(d.devices) || '—'}`,
    `- **Plays:** ${many(d.platforms) || '—'}`,
    `- **Tracks today:** ${d.tracking || '—'}`,
    `- **Leaving:** ${d.tool || '—'}`,
    `- **Wants:** ${d.wants ? String(d.wants).trim() : '—'}`,
    `- **Updates ok:** ${d.updates === 'yes' ? 'yes' : 'no'}`,
    `- **To do:** add to Player 1 in TestFlight, then move into the roster above.`,
    '',
  ].join('\n');
  appendFileSync(LEDGER, block);
  console.log(`[invite-poller] logged ${d.email || s.id}`);
}

writeFileSync(SEEN_PATH, JSON.stringify([...seen, ...fresh.map((s) => s.id)], null, 2));

// A local nudge on the Mac as well — the phone push comes from the Netlify
// function; this catches the case where you're sitting right here.
try {
  execFileSync('osascript', ['-e',
    `display notification "${fresh.length} new invite request${fresh.length === 1 ? '' : 's'} logged to the ledger" with title "LevelSelect"`]);
} catch { /* notification is a nicety, never a failure */ }

function writeTally(submissions) {
  const asList = (v) => Array.isArray(v) ? v.filter(Boolean)
    : (v ? String(v).split(',').map((x) => x.trim()).filter(Boolean) : []);
  const bump = (map, key) => { if (key) map.set(key, (map.get(key) || 0) + 1); };

  const devices = new Map(), platforms = new Map(), tracking = new Map(),
        leaving = new Map(), updates = new Map();
  let wantsAnswered = 0;

  for (const s of submissions) {
    const d = s.data || {};
    for (const v of asList(d.devices)) bump(devices, v);
    for (const v of asList(d.platforms)) bump(platforms, v);
    bump(tracking, (d.tracking || '(blank)').trim() || '(blank)');
    bump(leaving, (d.tool || '').trim() || '(blank)');
    bump(updates, d.updates === 'yes' ? 'yes' : 'no');
    if (d.wants && String(d.wants).trim()) wantsAnswered += 1;
  }

  const table = (map) => [...map.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([k, n]) => `| ${k} | ${n} |`).join('\n');

  const md = `# LevelSelect — invite tally

*Machine-owned: regenerated by \`scripts/log-invite-submissions.mjs\` on every
poll from the complete Netlify submission list. Hand edits will be overwritten
— annotate in [[LevelSelect testers ledger]] instead.*

**Total requests: ${submissions.length}** · wants answered: ${wantsAnswered}/${submissions.length}

## Plays on
| Platform | # |
|---|---|
${table(platforms) || '| — | 0 |'}

## Devices
| Device | # |
|---|---|
${table(devices) || '| — | 0 |'}

## Tracks today
| Answer | # |
|---|---|
${table(tracking) || '| — | 0 |'}

## Leaving (named tools — the competitor list)
| Tool | # |
|---|---|
${table(leaving) || '| — | 0 |'}

## Update-email consent
| Consent | # |
|---|---|
${table(updates) || '| — | 0 |'}

*Updated ${new Date().toISOString().slice(0, 16).replace('T', ' ')}*
`;
  writeFileSync(TALLY, md);
  console.log(`[invite-poller] tally refreshed (${submissions.length} total).`);
}
