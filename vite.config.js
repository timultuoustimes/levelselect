import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Netlify serves from the site root, so `base` is '/'. For the legacy
// GitHub Pages deployment (project page at /levelselect/) build with
// `BASE_PATH=/levelselect/ npm run build`.
const base = process.env.BASE_PATH ?? '/';

export default defineConfig({
  plugins: [react()],
  base,
  server: {
    host: '0.0.0.0',
    port: 5173,
  },
});
