# LevelSelect Privacy Policy

*Last updated: September 22, 2026*

LevelSelect is a game library and progress tracker for iPhone, iPad, Mac, and Apple Watch. It is built so that your data stays yours: there are no accounts, no ads, no analytics SDKs, and no tracking.

## The short version

- Your library lives **on your device** and, if you're signed in to iCloud, in **your private iCloud database**. We can't read it.
- The app sends **game names you search for** (and optionally guide text you paste) to our backend to look up game data and generate trackers.
- A **random install identifier** accompanies those requests purely for rate limiting. It is not tied to you, your iCloud account, or your device's hardware identifiers.
- If you connect a **RetroAchievements account**, its key lives in your device's Keychain and talks to RetroAchievements **directly** — it never reaches our backend, on purpose.
- If you connect **Steam**, the Web API key you registered on Steam lives in your device's Keychain and talks to Steam **directly**, the same way.
- If you connect **itch.io**, you approve it on itch.io's own page, and the token it gives back lives in your device's Keychain and talks to itch.io **directly**.
- If you connect **PlayStation** or **Xbox**, the sign-in LevelSelect keeps lives in your device's Keychain and talks to Sony or Microsoft **directly**.
- Nothing is sold, shared for advertising, or used to track you.

## Data stored on your device and in your iCloud

Everything you create in LevelSelect — your game library, play sessions, tracker progress, playthroughs, runs, collections, ratings, notes, and videos you've linked — is stored locally on your device using Apple's SwiftData, and synced through **CloudKit to your private iCloud database** when iCloud is available. This data is under your Apple account's control; the developer has no access to it. Deleting the app and its iCloud data removes it.

So that Spotlight and Siri can find your games, LevelSelect adds each game's name, platform, status, hours played and rating to your device's own **Spotlight index**. The index is kept by your device, is not sent to us, and is rebuilt whenever your library changes.

## Data that leaves your device

LevelSelect talks to a small backend (Supabase Edge Functions) for the features below. In each case, only what's listed is sent:

| Feature | What is sent | Where it goes |
|---|---|---|
| **Game search & metadata** | The search text or game id you look up | Our proxy → [IGDB](https://www.igdb.com) (a Twitch service) to fetch titles, cover art, release dates, and genres |
| **AI tracker generation** | The game's name, its public IGDB metadata, and (optionally) guide text or a guide URL you provide | Our generator → [Anthropic](https://www.anthropic.com)'s Claude API, which may also perform a web search for a game guide |
| **RetroAchievements lookup** | A game name and system, or a RetroAchievements game id | Our proxy → [RetroAchievements](https://retroachievements.org) to find a game and fetch its published achievement list. These requests use **our** API key, not yours, and say nothing about who you are |
| **Artwork lookup** | The game's name, then a SteamGridDB game id | Our proxy → [SteamGridDB](https://www.steamgriddb.com) to fetch covers, backdrops and logos. These requests use **our** API key, not yours, and say nothing about who you are |
| **Steam achievement lists** | A game name you search for, or a Steam app id | Our proxy → [Steam](https://store.steampowered.com), to find a game and fetch its published achievement list. These requests use **our** API key, not yours, and say nothing about who you are |
| **Steam game matching** | The Steam app ids of games you import from Steam or look up achievements for — numbers that identify games in Steam's store | Our proxy → IGDB, to find which game each one is. Sent with no Steam key and no SteamID, the same way a CSV import sends the titles in your file |
| **Import matching** | The names of games you import from Xbox, PlayStation, itch.io or a CSV file, and any title you search for while reviewing them | Our proxy → IGDB, to match each one to its game, cover and release date. Sent without your sign-in for any of those services and without saying where the names came from |
| **Suggestions & releases** | The IGDB ids of games in your library, their series and studio names, and any studios or publishers you follow; for upcoming releases, only the range of dates | Our proxy → IGDB, to find games like yours, more from a series or studio, and what is coming out. Nothing about who you are |
| **Game credits** | The IGDB id of a game whose page you open | Our proxy → [Wikidata](https://www.wikidata.org), to find the people credited on it and what else they made |
| **Barcode lookup** | The number on a game box you scan. If ScanDex didn't know it and you then choose the game yourself, that barcode with the game and console you chose | Our proxy → [ScanDex](https://scandex.gamery.app), to find which game the box is — and, in the second case, to add the match to ScanDex's database so the next scan works. The camera image never leaves your device; only the number does |
| **Map search** *(future feature)* | The game's name and optionally a wiki page URL | Our finder → Anthropic's Claude API with web search |

Additionally, entirely from your device:

- **Your RetroAchievements account** *(optional)*: if you connect one, your RetroAchievements username and Web API key are stored in your device's **Keychain** and are sent **directly from your device to retroachievements.org** to read what you've earned. They never pass through our backend, and they are deliberately not synced between your devices — you enter them on each device, or not at all. Removing them in Settings deletes them from the Keychain. See "Why your RetroAchievements key skips our servers" below.
- **Your Steam account** *(optional)*: if you connect one, the Web API key you registered on Steam is stored in your device's **Keychain**, and your SteamID and Steam display name are kept in the app's settings on that device. They are sent **directly from your device to api.steampowered.com** to read the games you own and the achievements you've earned. They never pass through our backend, for the same reason as the RetroAchievements key below, and are not synced between your devices. Steam only answers when your profile's game details are public on Steam. Disconnecting in Settings deletes the key from the Keychain.
- **Your itch.io account** *(optional)*: connecting opens itch.io's own sign-in page, where you approve LevelSelect reading your itch.io profile and the games you've bought or claimed. itch.io hands the access token back inside the web address; it passes through a page on levelselect.app that runs only in your browser and forwards it to the app, so the token is never sent to our servers. It is stored in your device's **Keychain**, not synced between your devices, and sent **directly from your device to api.itch.io** when you import. Imported games keep their itch.io cover image, which loads from itch.io's servers. Disconnecting in Settings deletes the token.
- **Your PlayStation account** *(optional)*: PlayStation has no public way for apps to read trophies, so LevelSelect uses the same sign-in as Sony's PlayStation App. You paste your NPSSO — a sign-in code from playstation.com that works like your password — and the app sends it **directly to Sony** once, to get a sign-in token, and does not keep it. The token is stored in your device's **Keychain**, not synced, and sent **directly from your device to Sony** (ca.account.sony.com and m.np.playstation.com) to read your trophy lists, the trophies you've earned, and the PS4 and PS5 games you've played with their playtime. It never passes through our backend. Disconnecting in Settings deletes it. Because this route isn't one Sony publishes for other apps, it could stop working at any time.
- **Your Xbox account** *(optional)*: you sign in on **Microsoft's own page**; LevelSelect never sees your password. Microsoft returns a sign-in token, stored in your device's **Keychain** and not synced, and your device uses it **directly with Microsoft and Xbox Live** (login.microsoftonline.com and xboxlive.com) to read the games you've played and the achievements you've earned. Your gamertag and Xbox user id are kept in the app's settings on that device to show who's connected. None of it passes through our backend. Disconnecting in Settings deletes the token.
- **News** *(the News tab)*: the app fetches each site's feed **directly from that site**, and for a story whose feed sends no picture, the story's own page, to read the picture it names. These are ordinary requests with nothing of ours attached — no install identifier, no LevelSelect key — so a site learns only that its feed was read. Opening a story is an ordinary visit in Safari's in-app view (or Reader), where the site sees what it would see from Safari. The list of feeds you follow and the stories you save sync through your own iCloud; the stories themselves are cached on your device and never stored with us.
- **Deku Deals wishlist**: if you configure a wishlist, the app fetches your **public** Deku Deals wishlist JSON directly from dekudeals.com. Nothing about you is sent beyond that public URL request.
- **Cover art, console logos and video metadata**: images load directly from IGDB's and SteamGridDB's image CDNs; console logos load directly from [Wikimedia Commons](https://commons.wikimedia.org), which is sent only the logo's file name; and YouTube video titles/thumbnails load via YouTube's public oEmbed endpoint for links you add.

Requests to our backend include a **random per-install identifier** (a UUID the app generates on first launch) used only to enforce fair-use rate limits. It is not derived from your device's hardware, not connected to your identity or iCloud account, and resets if you delete and reinstall the app.

We don't run analytics and we don't build profiles. We should be precise about logging, though: our hosting platform's function logs capture request and response data, including bodies and headers, for a short retention window used for errors and abuse detection. So anything you send to our backend — a game name, guide text you paste — passes through those logs in transit.

### Why your RetroAchievements key skips our servers

Because of that logging. A RetroAchievements Web API key is password-equivalent, and routing one through our backend would write it into platform logs on every sync — readable by anyone with dashboard access, and no amount of care in our own code would change that. Moving the key to a header would not have helped, because headers are logged too.

So the app doesn't send it to us at all. Your device talks to RetroAchievements directly, using an ephemeral connection with caching disabled so a copy of the key isn't written to disk in a URL cache. We keep the catalog lookups (searching for a game, fetching its published achievement list) on our own key, because those say nothing about who you are.

## What we don't do

- No LevelSelect account or password — the only sign-ins are the optional services above, and they stay on your device
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
