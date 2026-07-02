/** Tailwind config — HydraSpecma brand tokens (Fluent-inspired). @type {import('tailwindcss').Config} */
export default {
  content: ['./pages/**/*.html', './components/**/*.{js,html}', './js/**/*.js', './index.html'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        brand: {
          primary: '#003A70',
          secondary: '#00A3E0',
          accent: '#0EA5E9',
          bg: '#F8FAFC',
        },
      },
      fontFamily: { sans: ['Inter', 'system-ui', 'Segoe UI', 'sans-serif'] },
      borderRadius: { card: '16px' },
      boxShadow: { card: '0 1px 3px rgba(16,24,40,.1), 0 1px 2px rgba(16,24,40,.06)' },
    },
  },
  plugins: [],
};
