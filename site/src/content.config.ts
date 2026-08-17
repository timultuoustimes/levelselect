import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

/**
 * Changelog entries are markdown files, one per build. This is the main
 * reason for moving to Astro: adding a release becomes "write a file", the
 * ordering and the RSS feed come for free, and nobody has to hand-edit a
 * growing HTML page (or remember to update it in two places).
 */
const changelog = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/changelog' }),
  schema: z.object({
    version: z.string(),
    date: z.coerce.date(),
    title: z.string(),
    summary: z.string(),
    /** Hidden until a build is actually available to testers. */
    draft: z.boolean().default(false),
  }),
});

export const collections = { changelog };
