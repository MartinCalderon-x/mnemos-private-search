/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        surface: '#0f1117',
        panel: '#1a1d27',
        border: '#2a2d3a',
        accent: '#7c6aff',
        'accent-hover': '#9580ff',
        rag: '#22c55e',
        web: '#3b82f6',
        muted: '#6b7280',
      },
      animation: {
        'pulse-dot': 'pulse 1.2s cubic-bezier(0.4,0,0.6,1) infinite',
      },
    },
  },
  plugins: [],
};
