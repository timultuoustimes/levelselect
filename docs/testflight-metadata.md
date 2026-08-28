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

## Framing screenshots (the `frames` CLI)

The site's screenshots are device-framed. Apple Frames (the Shortcut) is
installed on Tim's Mac and **cannot run there**: its frame images live in
iCloud Drive, iCloud Drive is not syncing to that machine, and the shortcut
fails with a bare "The file doesn't exist". `shortcuts run "Apple Frames"`
hits the same wall.

MacStories publishes a CLI that does not depend on the Shortcut or on iCloud
Drive — it downloads its own assets. Installed 2026-08-28:

```
git clone https://github.com/viticci/frames-cli.git ~/Dev/tools/frames-cli
ln -sf ~/Dev/tools/frames-cli/frames ~/.local/bin/frames
curl -L -o /tmp/f.zip https://cdn.macstories.net/AppleFrames401.zip
unzip -d ~/.local/share/apple-frames /tmp/f.zip
frames setup ~/.local/share/apple-frames/Frames
```

`frames setup` with no path does a guided download, but it refuses to run
non-interactively — hence fetching the zip directly and pointing at it.

Usage:

```
frames info shot.png                       # which device did this come from
frames frame -c "Cosmic Orange" *.PNG      # writes shot_framed.png beside each
frames list                                # 55 devices, 252 frames
frames doctor                              # when it stops working
```

Output is **1470x3000** for a 6.9" iPhone and matches the Shortcut's output
exactly, so it is a drop-in for how the existing site shots were made. Resize
to the site's sizes afterwards: 686x1400 iPhone, 1600x1226 iPad, webp.

Video framing needs `brew install ffmpeg`; not installed, not needed yet.

## What to Test — build 32 (0.1.0)

> (standing header above, then:)
>
> This is a big one - the game page has been rebuilt. Roughly in order of
> how much I'd like eyes on it:
>
> - THE GAME PAGE HEADER. Open a few games, ideally ones with very
>   different art. The background should fill the top of the screen, run
>   under the buttons, and scroll away with the header. The game's name
>   sits under the cover, and hands over to the title bar once you scroll
>   past it. Tell me about any game where the art sits oddly, gets cut off,
>   or leaves an empty band - and please say which game, because this
>   depends on what art exists for it.
> - THE STATS ROW, under the ownership chips: played, sessions, beaten, and
>   runs on games that log them. These are LIFETIME totals across every
>   playthrough, so if you have more than one playthrough on a game, check
>   the number matches what you'd expect. If you don't time your play,
>   switch the whole row off: Settings > Game pages & trackers > Arrange
>   game pages > Header.
> - LOGOS. Game page ... menu > Artwork > Choose Logo. Logos now come from
>   IGDB and SteamGridDB automatically - no hunting for a PNG. Not every
>   game has one, and it says so when it doesn't. You can still add your
>   own or paste a link. Also worth trying Choose Cover and Choose
>   Backdrop, which have a lot more to choose from now.
> - THE ... MENU IS SHORTER. It went from fifteen items to seven, and
>   several things moved to the section they actually affect: run logging
>   is in the Runs section, tracker layout and hints are in the Tracker
>   section (the sliders button), and arranging game pages moved to
>   Settings. If you go looking for something and can't find it, that is
>   exactly the bug I want to hear about - please tell me what you were
>   trying to do.
> - Status names are now the same everywhere. The game menu used to say
>   "Playing" and "Queued" while everything else said "Now Playing" and
>   "Up Next". If you spot any surface still using the old words, shout.
> - Deleting a game asks first, wherever you do it from - the ... menu or
>   pressing and holding a cover. It goes to Recently Deleted in Settings
>   either way.
> - Settings has been reorganised, and the reset buttons are now separate
>   (colours, background, and rating labels reset independently, under
>   "Reset"). They only appear when you have actually changed something.
> - ON IPAD: please try a game page in landscape, especially if your
>   tracker layout is set to Compact. The art at the top was sitting in the
>   wrong place there and was fixed very late - I would like a second pair
>   of eyes on it.
> - A note on the Mac app: it is the least developed of the four and it
>   shows - it has not caught up with the new system look, and Settings is
>   rougher there. Bug reports are still welcome, but you are not imagining
>   it, and it is on the list.

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
