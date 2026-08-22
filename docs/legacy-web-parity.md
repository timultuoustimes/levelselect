# What the retired web app still does that the native app doesn't

The original React web app (`src/`) is not deployed and not maintained, but it is kept in the repo because it is currently the only record of a few things the native app hasn't caught up to. This file exists so that stops being true — when the list is empty, the web app can go.

Compiled 2026-08-22 by reading `src/components/Library.jsx` (`LibraryStats`) against `native/LevelSelect/LevelSelect/UI/StatsView.swift`.

## Stats

The native Stats tab has: library size, completions, most played, recent play (this week / this month), session counts.

The web app's Stats view has all of the following, and the native one has none of them:

| Web app | What it showed |
|---|---|
| Completion rate | Completed as a percentage of the library, as a headline number |
| Average rating | With the count of games actually rated, so one 5-star game doesn't read as "5.0 average" |
| Rating distribution | How many games at each star, as bars |
| Status breakdown | Every status as a proportion of the library, not just a count |
| By platform | Games per system, ranked, as bars |
| By franchise | Top 10 franchises by count |
| Games played by year | Distribution across release years |
| Top tags | The 20 most-used tags |

Two notes on porting these rather than copying them:

**Some are now navigation rather than statistics.** The native app has facet browsing — tapping a developer, publisher, genre or year opens everything in the library matching it. "By platform" and "by franchise" as *stats* would be a second way to see the same relationships, so they may want to be entry points into that rather than bars for their own sake.

**Average rating needs its denominator.** The web version showed the rated count beside it for a reason: most libraries have a minority of games rated, and an average without that context is misleading.

## Per-game bespoke trackers

The web app carries hand-written trackers for specific games — Hades, Dead Cells, Mina the Hollower, The Messenger, Lone Ruin, Citizen Sleeper, Cursed to Golf, GONNER — each with its own components and, in Lone Ruin's case, its own analytics view (`LoneRuinAnalytics.jsx`).

These are **deliberately not ported**. The native app replaced the whole idea with generated and pasted trackers plus the built-in tracker set, which is the reason it works for any game rather than eight. They are listed here only so nobody mistakes their absence for an oversight.

The one thing worth mining from them is shape: they are evidence of what a really good tracker for a specific game looks like, which is a useful test for whether a generated one is good enough.
