import { shipped, horizons, notPlanned, reviewed } from '../../data/roadmap';

/**
 * The roadmap, as JSON, for the app's What's Coming screen.
 *
 * Same arrays the page renders — see `src/data/roadmap.ts` for why they live
 * apart from it. The field names are spelled out here rather than passed
 * through: the page's `t` and `d` are fine in a template three lines from
 * their definition, and unreadable in a Swift model.
 */
export async function GET() {
  const payload = {
    generated: new Date().toISOString(),
    reviewed,
    // A direction, not a set of promises — said on both surfaces, because it
    // is the sentence that makes publishing a roadmap at all defensible.
    disclaimer: 'A direction, not a set of promises.',
    horizons: horizons.map((h) => ({
      key: h.key,
      name: h.name,
      note: h.note,
      color: h.color,
      items: h.items.map((item) => ({ title: item.t, detail: item.d })),
    })),
    shipped: shipped.map((item) => ({
      title: item.t,
      detail: item.d,
      build: item.build,
      url: `https://levelselect.app/changelog/#build-${item.build}`,
    })),
    notPlanned: notPlanned.map((item) => ({ title: item.t, detail: item.d })),
  };

  return new Response(JSON.stringify(payload, null, 2), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
    },
  });
}
