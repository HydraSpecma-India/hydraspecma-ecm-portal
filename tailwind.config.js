/** Tailwind config — Modern Professional Dashboard Brand. @type {import('tailwindcss').Config} */
export default {
  content: ['./pages/**/*.html', './components/**/*.{js,html}', './js/**/*.js', './index.html'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        brand: {
          primary: '#1E3A5F',
          secondary: '#2563EB',
          accent: '#F59E0B',
          bg: '#F1F5F9',
        },
      },
      fontFamily: { sans: ['Inter', 'system-ui', 'Segoe UI', 'sans-serif'] },
      borderRadius: { card: '16px' },
      boxShadow: { card: '0 1px 3px rgba(16,24,40,.1), 0 1px 2px rgba(16,24,40,.06)' },
    },
  },
  plugins: [],
};
