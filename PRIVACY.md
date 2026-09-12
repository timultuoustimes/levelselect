# LevelSelect Privacy Policy

*Last updated: August 23, 2026*

LevelSelect is a game library and progress tracker for iPhone, iPad, Mac, and Apple Watch. It is built so that your data stays yours: there are no accounts, no ads, no analytics SDKs, and no tracking.

## The short version

- Your library lives **on your device** and, if you're signed in to iCloud, in **your private iCloud database**. We can't read it.
- The app sends **game names you search for** (and optionally guide text you paste) to our backend to look up game data and generate trackers.
- A **random install identifier** accompanies those requests purely for rate limiting. It is not tied to you, your iCloud account, or your device's hardware identifiers.
- If you connect a **RetroAchievements account**, its key lives in your device's Keychain and talks to RetroAchievements **directly** — it never reaches our backend, on purpose.
- Nothing is sold, shared for advertising, or used to track you.

## Data stored on your device and in your iCloud

Everything you create in LevelSelect — your game library, play sessions, tracker progress, playthroughs, runs, collections, ratings, notes, and videos you've linked — is stored locally on your device using Apple's SwiftData, and synced through **CloudKit to your private iCloud database** when iCloud is available. This data is under your Apple account's control; the developer has no access to it. Deleting the app and its iCloud data removes it.

## Data that leaves your device

LevelSelect talks to a small backend (Supabase Edge Functions) for four features. In each case, only what's listed is sent:

| Feature | What is sent | Where it goes |
|---|---|---|
| **Game search & metadata** | The search text or game id you look up | Our proxy → [IGDB](https://www.igdb.com) (a Twitch service) to fetch titles, cover art, release dates, and genres |
| **AI tracker generation** | The game's name, its public IGDB metadata, and (optionally) guide text or a guide URL you provide | Our generator → [Anthropic](https://www.anthropic.com)'s Claude API, which may also perform a web search for a game guide |
| **RetroAchievements lookup** | A game name and system, or a RetroAchievements game id | Our proxy → [RetroAchievements](https://retroachievements.org) to find a game and fetch its published achievement list. These requests use **our** API key, not yours, and say nothing about who you are |
| **Artwork lookup** | The game's name, then a SteamGridDB game id | Our proxy → [SteamGridDB](https://www.steamgriddb.com) to fetch covers, backdrops and logos. These requests use **our** API key, not yours, and say nothing about who you are |
| **Map search** *(future feature)* | The game's name and optionally a wiki page URL | Our finder → Anthropic's Claude API with web search |

Additionally, entirely from your device:

- **Your RetroAchievements account** *(optional)*: if you connect one, your RetroAchievements username and Web API key are stored in your device's **Keychain** and are sent **directly from your device to retroachievements.org** to read what you've earned. They never pass through our backend, and they are deliberately not synced between your devices — you enter them on each device, or not at all. Removing them in Settings deletes them from the Keychain. See "Why your RetroAchievements key skips our servers" below.
- **Deku Deals wishlist**: if you configure a wishlist, the app fetches your **public** Deku Deals wishlist JSON directly from dekudeals.com. Nothing about you is sent beyond that public URL request.
- **Cover art and video metadata**: images load directly from IGDB's and SteamGridDB's image CDNs, and YouTube video titles/thumbnails load via YouTube's public oEmbed endpoint for links you add.

Requests to our backend include a **random per-install identifier** (a UUID the app generates on first launch) used only to enforce fair-use rate limits. It is not derived from your device's hardware, not connected to your identity or iCloud account, and resets if you delete and reinstall the app.

We don't run analytics and we don't build profiles. We should be precise about logging, though: our hosting platform's function logs capture request and response data, including bodies and headers, for a short retention window used for errors and abuse detection. So anything you send to our backend — a game name, guide text you paste — passes through those logs in transit.

### Why your RetroAchievements key skips our servers

Because of that logging. A RetroAchievements Web API key is password-equivalent, and routing one through our backend would write it into platform logs on every sync — readable by anyone with dashboard access, and no amount of care in our own code would change that. Moving the key to a header would not have helped, because headers are logged too.

So the app doesn't send it to us at all. Your device talks to RetroAchievements directly, using an ephemeral connection with caching disabled so a copy of the key isn't written to disk in a URL cache. We keep the catalogue lookups (searching for a game, fetching its published achievement list) on our own key, because those say nothing about who you are.

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

Questions or concerns: [privacy@levelselect.app](mailto:privacy@levelselect.app), or use TestFlight's built-in feedback during the beta.

The canonical version of this policy lives at [levelselect.app/privacy](https://levelselect.app/privacy).
