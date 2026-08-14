# LevelSelect Privacy Policy

*Last updated: August 13, 2026*

LevelSelect is a game library and progress tracker for iPhone, iPad, Mac, and Apple Watch. It is built so that your data stays yours: there are no accounts, no ads, no analytics SDKs, and no tracking.

## The short version

- Your library lives **on your device** and, if you're signed in to iCloud, in **your private iCloud database**. We can't read it.
- The app sends **game names you search for** (and optionally guide text you paste) to our backend to look up game data and generate trackers.
- A **random install identifier** accompanies those requests purely for rate limiting. It is not tied to you, your iCloud account, or your device's hardware identifiers.
- Nothing is sold, shared for advertising, or used to track you.

## Data stored on your device and in your iCloud

Everything you create in LevelSelect — your game library, play sessions, tracker progress, playthroughs, runs, collections, ratings, notes, and videos you've linked — is stored locally on your device using Apple's SwiftData, and synced through **CloudKit to your private iCloud database** when iCloud is available. This data is under your Apple account's control; the developer has no access to it. Deleting the app and its iCloud data removes it.

## Data that leaves your device

LevelSelect talks to a small backend (Supabase Edge Functions) for three features. In each case, only what's listed is sent:

| Feature | What is sent | Where it goes |
|---|---|---|
| **Game search & metadata** | The search text or game id you look up | Our proxy → [IGDB](https://www.igdb.com) (a Twitch service) to fetch titles, cover art, release dates, and genres |
| **AI tracker generation** | The game's name, its public IGDB metadata, and (optionally) guide text or a guide URL you provide | Our generator → [Anthropic](https://www.anthropic.com)'s Claude API, which may also perform a web search for a game guide |
| **Map search** *(future feature)* | The game's name and optionally a wiki page URL | Our finder → Anthropic's Claude API with web search |

Additionally, entirely from your device:

- **Deku Deals wishlist**: if you configure a wishlist, the app fetches your **public** Deku Deals wishlist JSON directly from dekudeals.com. Nothing about you is sent beyond that public URL request.
- **Cover art and video metadata**: images load directly from IGDB's image CDN, and YouTube video titles/thumbnails load via YouTube's public oEmbed endpoint for links you add.

Requests to our backend include a **random per-install identifier** (a UUID the app generates on first launch) used only to enforce fair-use rate limits. It is not derived from your device's hardware, not connected to your identity or iCloud account, and resets if you delete and reinstall the app.

We do not log request contents beyond transient operational logs (errors and abuse detection), and we never build profiles from them.

## What we don't do

- No user accounts, sign-ins, or passwords
- No advertising, and no data sold or shared with data brokers
- No analytics or telemetry SDKs
- No tracking across apps or websites (see our privacy manifest: tracking = false)
- No access to your contacts, photos, location, microphone, or camera

## Crash reports and TestFlight

During the beta, Apple's TestFlight may share crash logs and feedback you choose to submit with the developer, governed by [Apple's privacy policy](https://www.apple.com/legal/privacy/). These arrive anonymized unless you've opted to share them with identifiers.

## Children

LevelSelect is not directed at children under 13 and collects no personal information from anyone.

## Changes

If this policy changes, the updated version will be posted at this address with a new date. Material changes will be noted in release notes.

## Contact

Questions or concerns: open an issue at [github.com/timultuoustimes/levelselect](https://github.com/timultuoustimes/levelselect/issues), or use TestFlight's built-in feedback during the beta.
