/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        hades: {
          bg: '#0f0a1a',
          card: 'rgba(0,0,0,0.5)',
          purple: '#9333ea',
          red: '#dc2626',
          gold: '#f59e0b',
        },
      },
    },
  },
  plugins: [],
};
