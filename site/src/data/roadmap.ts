/**
 * The roadmap's contents, lifted out of the page so two things can read them.
 *
 * The page renders these; `/roadmap/feed.json` serves the same arrays to the
 * app's What's Coming screen. One source, so a roadmap reviewed on the site is
 * a roadmap the app already agrees with — the alternative is two lists that
 * drift and a promise that quietly stops being true.
 */

/** Shown on both surfaces, so the app can say when this was last honest. */
export const reviewed = '18 September 2026';

export const shipped = [
  { t: 'Game news, in its own place', build: 39,
    d: 'A News tab of the sites you choose — all of it, your games first, by topic — plus every game coming out and what just did. Save stories for later, read them in Reader.' },
  { t: 'One search for everything', build: 39,
    d: 'Your games, tracker items, notes, news and releases, then games you do not have — from the search circle beside the tab bar.' },
  { t: 'Your consoles\' libraries, brought in', build: 39,
    d: 'Steam, PlayStation, Xbox and RetroAchievements: what you played comes in for review, matched to the right game on the console you played it on.' },
  { t: 'Scan the box', build: 39,
    d: 'Point the camera at a game box\'s barcode and it opens ready to add, on the right console, marked physical.' },
  { t: 'Games you might like', build: 39,
    d: 'Suggestions built from the games you play and rate, with the studios, publishers and series you follow first.' },
  { t: 'Parties, runs and focus', build: 39,
    d: 'A roster for an RPG party, runs you can compare, lists a playthrough chases — and a list that counts, does not, or counts partly.' },
  { t: 'The consoles themselves', build: 38,
    d: 'A console is something you own in its own right: how you have it, when you got it, a photograph of the actual machine — and which model the app draws, from the Funtastic N64 to a coral Switch Lite.' },
  { t: 'A color for light and another for dark', build: 38,
    d: 'Pick a pair for each appearance and the app changes with the system — accent, ground and widgets together.' },
  { t: 'Choose many games at once', build: 38,
    d: 'Select games in Library or on a console page and set the console you own them on, or their status, for all of them together.' },
  { t: 'Home is yours to arrange', build: 38,
    d: 'Your consoles in a case under your name, every shelf a choice, a collection as its own shelf — in the order you drag, following you to every device.' },
  { t: 'Maps, with pins that mean something', build: 38,
    d: 'Your own pictures of a game world, with pins you drop. Link a pin to a tracker item and ticking either one ticks the other.' },
  { t: 'A collection that fills itself', build: 38,
    d: "Save Library's filters as a collection and it keeps itself current — add a game that fits and it's in." },
  { t: 'Your words for your library', build: 37,
    d: 'Call a console whatever you call it — Mega Drive or Genesis, Super Nintendo or SNES — and it changes every shelf, chip and widget that names it. Rename statuses and stars too.' },
  { t: 'Nine ways a game can be yours', build: 37,
    d: 'Physical, digital, emulated and former; subscription, rented, borrowed, shared, and played standing up in an arcade. Choose which your library uses and what order they sit in.' },
  { t: 'One place to choose a color', build: 37,
    d: 'Accent and background in a single editor, light and dark previewed side by side with the contrast on each, and swatches that only offer colors that stay readable.' },
  { t: 'Browse by genre', build: 37,
    d: 'The genres and themes every game already carried are a way into the library now, not just a label on a page you were already looking at.' },
  { t: 'Who made it', build: 37,
    d: 'Director, designer, writer and composer on the game page, from Wikidata — the person-level credits the games database does not have.' },
  { t: 'Feedback without leaving', build: 37,
    d: "Send feedback goes straight to Tim from inside the app, and What's New and What's Coming read the site rather than opening it." },
  { t: 'The Journal', build: 36,
    d: 'Everything you have written down, in order. A day of a game is one entry, not three, and it asks what happened while it is still what you were just doing.' },
  { t: 'The part that happened before the app', build: 36,
    d: 'Memories, dated as vaguely as you actually remember them — an exact day, a month, a year, or "Christmas 1995 or 1996" in your own words. Pictures included.' },
  { t: 'A year of play in one screen', build: 36,
    d: 'Twelve small months and a heat map, and any month opens into full box art on every day you played.' },
  { t: 'Light mode, in your color', build: 36,
    d: 'The whole app light or dark, with a background you choose and the contrast the app keeps for you.' },
  { t: 'Ten statuses that say what they mean', build: 36,
    d: 'Old Favorite for the ones you replay forever, a line of explanation where you pick each one, and rename any of them.' },
  { t: 'A game you are waiting for tells you when', build: 35,
    d: 'A countdown on the card, two widgets, a release calendar, and a reminder the morning before.' },
  { t: 'The release date for the platform you picked', build: 35,
    d: 'Out on PC and months away on Switch 2 is two true answers, and you get yours.' },
  { t: 'Stats says what it is', build: 35,
    d: 'Your history in three questions — Time, Finishes, Library — with the totals standing above them.' },
  { t: 'Enough to decide when adding a game', build: 35,
    d: 'The trailer, the screenshots, the description, and the date your platform actually gets.' },
  { t: 'Your itch.io library', build: 35,
    d: 'Connect the account and the games you bought or claimed come in, with their art.' },
  { t: 'Library and Wishlist, with an identity of their own', build: 34,
    d: 'Status, system and ownership all on screen, and a wishlist that knows what is out.' },
  { t: 'Every platform a game came out on', build: 34,
    d: 'Mark the ones you own it on, rather than the app knowing only the one you typed.' },
  { t: 'Your own cover art', build: 31,
    d: 'The cover can be the one your copy had.' },
  { t: 'A safety net for deletions', build: 28,
    d: 'Recently Deleted and a restore path, so nothing is ever one tap from gone.' },
  { t: 'Deeper stats', build: 27,
    d: 'Your habits by year, by genre, by system — and cards you can rearrange.' },
  { t: 'Build a tracker piece by piece', build: 25,
    d: 'Fill one category at a time instead of waiting on one generation that can fail entirely.' },
];

export const horizons = [
  {
    key: 'now',
    name: 'Now',
    note: 'being worked on',
    color: '#30D158',
    items: [
      { t: 'Settling the beta', d: 'Making the things people use every day dependable before adding more.' },
      { t: 'Trackers you can trust', d: "Generating a tracker should never be a gamble with progress you've already made." },
      { t: 'Mac polish', d: "Underway. The Mac app has the new design and reachable settings now; the details still lag the iPhone." },
    ],
  },
  {
    key: 'next',
    name: 'Next',
    note: 'planned',
    color: '#0A84FF',
    items: [
      { t: 'Moments worth celebrating', d: 'Finishing a game or hitting a milestone should feel like something.' },
      { t: 'Trackers that fit the game', d: 'A checklist suits a Metroidvania. Other games need a count, a time, a rank or a score. Trackers will learn the shape of the game they are for.' },
      { t: 'Replays', d: 'A look back at a month, a quarter or a year, built from your own library on your own device.' },
    ],
  },
  {
    key: 'exploring',
    name: 'Exploring',
    note: 'no commitment',
    color: '#BF5AF2',
    items: [
      { t: 'Badges', d: "Recognition for what you've actually done, earned once and kept." },
      { t: 'Commissioned artwork', d: 'The console icons and the genie are placeholders today. We would like them drawn by an artist.' },
      { t: 'Scanning a written list', d: 'Point a camera at a checklist you wrote by hand and turn it into a tracker.' },
      { t: 'More of your own notebook', d: 'Light and dark and your own background color landed in 36. Icons, covers, and the rest of the personality a paper journal has.' },
    ],
  },
];

export const notPlanned = [
  { t: 'Accounts', d: "Your library lives in your own iCloud. There's nothing to sign up for." },
  { t: 'Ads, analytics or tracking', d: 'Not now, not later.' },
  { t: 'A social network', d: 'Sharing something you choose to share is one thing; a feed is another.' },
];
