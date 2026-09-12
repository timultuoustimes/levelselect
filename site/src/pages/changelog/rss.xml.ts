import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';
import type { APIContext } from 'astro';

/**
 * A feed for the changelog — the concrete thing the content collection buys
 * that hand-written HTML couldn't. Beta testers can follow what changed
 * without opening TestFlight.
 */
export async function GET(context: APIContext) {
  const entries = (await getCollection('changelog', ({ data }) => !data.draft))
    .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());

  return rss({
    title: 'LevelSelect changelog',
    description: "What's actually shipped in the LevelSelect beta.",
    site: context.site!,
    items: entries.map((entry) => ({
      title: `${entry.data.version} — ${entry.data.title}`,
      description: entry.data.summary,
      pubDate: entry.data.date,
      link: '/changelog/',
    })),
  });
}
