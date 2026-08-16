# TestFlight & App Store Connect metadata (paste-ready drafts)

Drafted 2026-08-13 for the first external beta. Everything here goes into App
Store Connect by hand (Tim's account) — nothing is applied automatically.

## App Privacy answers (App Store Connect → App Privacy)

These must match `PrivacyInfo.xcprivacy` (they do, as written):

- **Do you collect data from this app?** → **Yes** (the per-install rate-limit id counts)
- **Identifiers → Device ID** → Collected
  - Linked to the user's identity? **No**
  - Used for tracking? **No**
  - Purposes: **App Functionality**
- Everything else: **Not collected**. Game names sent to search/AI are user-initiated
  content requests, not collected data retained about the user; if review pushes back,
  the fallback is adding "Other User Content / App Functionality / not linked".
- **Privacy Policy URL:** `https://levelselect.app/privacy`
  (Live since 2026-08-15. Replaces the GitHub blob URL used while the site was
  being built — update it in BOTH places: Distribution → App Privacy, and
  TestFlight → Test Information.)

## Beta App Description

> LevelSelect is your game library, progress tracker, and play journal in one.
> Track what you're playing, time your sessions (with Live Activities, widgets,
> and an Apple Watch app), check off bosses and collectibles with per-game
> trackers — including AI-generated ones — log roguelike runs, organize
> collections, follow your Deku Deals wishlist, and see your play stats. Your
> library syncs privately through your own iCloud. No accounts, no ads, no
> tracking.
>
> Built solo with AI assistance (Claude) — the code, and the review of it,
> are both real; more at levelselect.app/about.

## What to Test

> This is the first external beta — the core loop is what matters:
>
> - Add games from search (and by hand when search can't find one)
> - Start, pause, and stop play sessions — from the app, the Live Activity,
>   a widget, or the watch — and confirm the time recorded looks right
> - Try a tracker: check off objectives, generate one with AI for a game you
>   know, and tell us where the generated content is wrong
> - Create a collection, rate a game, log a roguelike run
> - If you have two devices: confirm changes appear on the other one
> - Check Settings → iCloud shows the sync state you'd expect
>
> Known limitations: game maps and screenshots aren't in yet; AI generation
> has a fair-use hourly limit. Feedback via TestFlight (screenshot → Share
> Beta Feedback) is ideal because it attaches device context.

## Review notes (Beta App Review contact section)

> No account is required; all features work immediately. AI tracker
> generation calls our backend (Supabase + Anthropic) and takes 1–2 minutes (longer for large games).
> The app's data is stored in the user's private iCloud database via
> CloudKit. Contact: [Tim's email + phone go here].

## Export compliance

Already answered in the build: `ITSAppUsesNonExemptEncryption = false`
(standard HTTPS only).

## Pre-submission checklist (the manual half of P0)

- [ ] Merge (or adjust the privacy URL) so the policy link resolves
- [ ] Fill in review contact email/phone in App Store Connect
- [ ] Confirm App Privacy answers per above
- [ ] Deploy CloudKit schema to Production (CloudKit Console → Deploy Schema
      Changes) before any external tester launches the app
- [ ] Fresh-Apple-ID test per the beta test script in the roadmap note
- [ ] After the next build ships: set `LS_APP_SECRET` (see roadmap)

## Build 21 follow-up

- [ ] TestFlight → Test Information → **Beta App Description** was already
      saved for build 19/20 without the AI-disclosure line above — re-paste
      the updated version (added 2026-08-15) so the External group and public
      link see it, since that's the review-facing moment where candor matters
      most.
