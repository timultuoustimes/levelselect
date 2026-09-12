# LevelSelect

A game library, session timer, and progress tracker for people with more games than time.

Native SwiftUI app for iPhone, iPad, Mac, and Apple Watch. Your library syncs privately through your own iCloud — there is no account to make, no ads, no analytics, and no tracking of any kind.

**Status: private beta.** [Join on TestFlight](https://testflight.apple.com/join/7pwdQEMq) · [levelselect.app](https://levelselect.app) · [changelog](https://levelselect.app/changelog/)

## What it does

- **Library** — what you own, on what, and what state it's in. Metadata and cover art from IGDB.
- **Sessions** — time what you play, with Live Activities, Home Screen widgets, and a Watch app. Two devices can't double-count the same hour.
- **Trackers** — checklists, collectibles, ranked upgrades and ordered sequences, per playthrough. Import the real RetroAchievements set, paste a checklist you already have, or generate just the parts you care about: ask what a game should be divided into, then fill one category at a time and leave the rest alone.
- **Runs** — roguelike runs logged separately from play time.
- **Collections** — group games around a question rather than a folder name.
- **Wishlist** — games you want, alongside your Deku Deals list.

## Repository layout

| Path | What it is |
|---|---|
| `native/LevelSelect/` | The app. SwiftUI + SwiftData, synced with CloudKit. This is the live code. |
| `site/` | levelselect.app — Astro, deployed by Netlify. |
| `supabase/functions/` | Edge functions: IGDB proxy, RetroAchievements proxy, AI tracker generation, map finder. |
| `src/`, `index.html`, `vite.config.js` | **Retired.** The original React web app, kept as a feature reference — some things exist here that the native app hasn't caught up to yet. Not deployed, not maintained. See `docs/legacy-web-parity.md`. |

The Xcode project is generated: `project.yml` is the source of truth, and `.xcodeproj` is gitignored. Run `xcodegen generate` in `native/LevelSelect/` after adding files.

## Building it

You will need Xcode 26 and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
cd native/LevelSelect
cp Secrets.example.xcconfig Secrets.xcconfig   # then fill in LS_APP_KEY
xcodegen generate
open LevelSelect.xcodeproj
```

`Secrets.xcconfig` is gitignored. It carries the key the app sends to the edge functions; without it the app builds and runs, but the IGDB, RetroAchievements and AI features have nothing to talk to. The edge functions are deployed against a Supabase project that isn't public, so a fresh clone gets a working app with those features inert rather than a working backend.

Debug builds use the CloudKit **Development** environment and Release builds use **Production**. They never see each other's data, which is deliberate — but it means a TestFlight build and a locally-built one on the same device hold two separate libraries.

## Privacy

There is no server that holds your library. Games, sessions, progress and notes live on your device and sync through your own iCloud private database, which the developer cannot read.

The edge functions exist so that third-party API keys aren't shipped inside the app binary. They see the text of what you ask for — a game name to look up, a category to generate — and nothing about who you are. Your RetroAchievements API key is a deliberate exception in the other direction: it goes from your device straight to RetroAchievements and never passes through our infrastructure at all, because request bodies land in server logs.

Full policy: [levelselect.app/privacy](https://levelselect.app/privacy/).

## Contributing

This is a solo project and isn't looking for pull requests. Bug reports and blunt opinions are genuinely welcome — open an issue, or use the feedback link in TestFlight.

## License

Not open source. The source is public so that the privacy claims above can be checked rather than taken on faith. See [LICENSE](LICENSE).
