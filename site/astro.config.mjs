// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// The site was hand-written static HTML before this. Two things are
// load-bearing and must not drift:
//
//  1. URLs. `/privacy/` is registered in App Store Connect in TWO places
//     (App Privacy → Privacy Policy URL, and TestFlight → Test Information),
//     so changing it breaks submission metadata. `trailingSlash: 'always'`
//     plus directory-style output keeps every existing URL byte-identical.
//  2. Zero client JS by default. Astro ships none unless a component asks
//     for it, which suits a site whose interactivity is a few CSS effects.
export default defineConfig({
  site: 'https://levelselect.app',
  trailingSlash: 'always',
  build: { format: 'directory' },
  integrations: [sitemap()],
});
