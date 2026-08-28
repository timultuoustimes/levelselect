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

## What to Test — the standing header

**Paste this at the top of EVERY build's "What to Test", before anything
build-specific.** Reason it exists: five testers arrived through the public
TestFlight link and not one is sharing diagnostics, so Sessions and crashes
read as "—" in App Store Connect. The app ships no analytics by design and
never will, which means Apple's own channel is the *only* way a crash on
someone else's device can ever reach us — and it has to be asked for,
because it's off by default and nothing in the app can turn it on.

Say the privacy part first. A tester who has read "no tracking, no
analytics" and then hits "please enable analytics" needs the distinction
made for them, or the ask reads as a contradiction.

Plain text — App Store Connect renders no markdown (no `**`, no `-` bullets
that need styling; hyphens are fine as literal characters).

> FIRST, A SMALL ASK (about 30 seconds)
>
> LevelSelect has no accounts, no ads, and no analytics of its own. That
> isn't changing. It also means that if the app crashes on your device, I
> have no way of ever knowing it happened.
>
> Apple has a channel for exactly this, and it doesn't involve the app
> collecting anything:
>
> Settings > Privacy & Security > Analytics & Improvements
> 1. Turn on "Share iPhone Analytics"
> 2. Then turn on "Share With App Developers"
>
> The second switch only appears once the first one is on.
>
> That sends Apple's anonymous crash reports my way — no personal data,
> nothing tied to you, nothing the app itself can see, and you can switch it
> back off whenever you like. If you hit a crash and this is off, the report
> simply doesn't exist, so this is genuinely the only way I can fix it.
>
> Thank you — it makes a real difference to a beta this small.

## What to Test — build 31 (0.1.0)

> (standing header above, then:)
>
> New in this build, roughly in order of how much I'd like eyes on it:
>
> - Beaten records can now carry a START date as well as a finish. Mark a
>   game beaten (or tap an existing record to edit it) and set "Started" —
>   day, month, or just a year. It should read like "Dec 2025 - Jan 2026".
>   Tell me if a span ever reads wrong or the Record button won't enable.
> - Settings > Appearance > Star names. Rename any of the five ratings to
>   whatever you actually mean. Blank one and the built-in word returns.
>   They should sync to your other devices.
> - Game page ... menu > Arrange Sections. Reorder the sections, switch off
>   ones you never use. Hidden sections keep their contents - switch Notes
>   back on and every note should still be there.
> - Collapsing a section should now only affect THAT game. It used to apply
>   to your whole library, which was a bug.
> - Game page ... menu > Change Cover. Pick a different official cover or
>   artwork, or paste an image URL. "Use fetched cover" undoes it. Worth
>   checking the cover you chose also shows in widgets and on Home.
> - A Media section on the game page with screenshots.
> - A fourth ownership chip: Previously Owned, for a copy you no longer have.
> - Tags: start typing one and your existing tags are suggested underneath.
>   Settings > Manage Tags to rename, merge (rename one onto another), or
>   remove a tag everywhere.
> - Two new game page backgrounds (accent colour, plain) in Appearance.
>
> If you have two devices, the star names and the start dates are the two
> things most worth checking sync.
>
> Known limitations: no Steam/PSN/Xbox import (CSV works); your own photos
> can't be added to a game yet - that's next; game maps aren't in yet; AI
> tracker generation has a fair-use hourly limit.
>
> Feedback through TestFlight (screenshot, then Share Beta Feedback) is
> ideal because it attaches device context automatically.

## What to Test — build 26 (the first external beta, for reference)

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
