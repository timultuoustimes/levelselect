import { getCollection } from 'astro:content';

/**
 * The changelog, as JSON, for the app to read.
 *
 * What's New used to be a row in Settings that opened Safari. Tim: *"Being
 * able to inform people ... all from within the app and not needing to go to
 * my website or their email is the best way to do it."* This is the half of
 * that which needs no new content: the same markdown that builds the page and
 * the RSS feed, in a shape a Swift `Codable` can read.
 *
 * The one thing done here rather than in the app is splitting each entry into
 * its `###` items. The parsing rule already exists — the page's filter chips
 * read the same `[new]` / `[improved]` / `[fixed]` suffix — and doing it on
 * the server means the app needs no markdown renderer at all, just a list.
 */

const KINDS = ['new', 'improved', 'fixed'] as const;
type Kind = (typeof KINDS)[number];

interface Item {
  title: string;
  kind: Kind;
  detail: string;
}

/** Enough markdown flattening for a heading and one paragraph of prose. */
function plain(text: string): string {
  return text
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // links keep their words
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    .trim();
}

/**
 * One item per `###`, with the first paragraph under it as the detail.
 *
 * Only the first paragraph: the entries run long by design — they are release
 * notes people read on a website — and a What's New screen that reprints them
 * whole is one nobody finishes. The link to the full entry rides along on the
 * release itself.
 */
function parseItems(body: string): Item[] {
  const items: Item[] = [];
  let current: Item | null = null;
  let detailDone = false;

  for (const raw of body.split('\n')) {
    const line = raw.trim();
    const heading = line.match(/^###\s+(.*)$/);

    if (heading) {
      if (current) items.push(current);
      let title = heading[1].trim();
      let kind: Kind = 'new';
      const tag = title.match(/\s*\[(\w+)\]$/);
      if (tag && (KINDS as readonly string[]).includes(tag[1].toLowerCase())) {
        kind = tag[1].toLowerCase() as Kind;
        title = title.slice(0, tag.index).trim();
      }
      current = { title: plain(title), kind, detail: '' };
      detailDone = false;
      continue;
    }

    if (!current || detailDone) continue;
    // A blank line after prose has started ends the paragraph. A blank line
    // before it has started is just the gap under the heading.
    if (!line) {
      if (current.detail) detailDone = true;
      continue;
    }
    // Lists and images belong to the page, not to a one-line summary.
    if (/^([-*>|]|!\[|<)/.test(line)) {
      if (current.detail) detailDone = true;
      continue;
    }
    current.detail = current.detail ? `${current.detail} ${plain(line)}` : plain(line);
  }

  if (current) items.push(current);
  return items;
}

/** `0.1.0-36` → 36, `0.1.0-beta` → null. Same derivation as the page anchor. */
function buildNumber(id: string): number | null {
  const last = id.split('-').pop() ?? '';
  const n = Number.parseInt(last, 10);
  return Number.isFinite(n) ? n : null;
}

export async function GET() {
  const entries = (await getCollection('changelog', ({ data }) => !data.draft))
    .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());

  const releases = entries.map((entry) => {
    const anchor = entry.id.split('-').pop();
    return {
      id: entry.id,
      version: entry.data.version,
      build: buildNumber(entry.id),
      date: entry.data.date.toISOString(),
      title: entry.data.title,
      summary: entry.data.summary,
      items: parseItems(entry.body ?? ''),
      url: `https://levelselect.app/changelog/#build-${anchor}`,
    };
  });

  return new Response(
    JSON.stringify({ generated: new Date().toISOString(), releases }, null, 2),
    {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        // Short enough that a build ships and testers see it; long enough that
        // an app launched ten times an hour doesn't re-fetch ten times.
        'Cache-Control': 'public, max-age=300',
      },
    },
  );
}
