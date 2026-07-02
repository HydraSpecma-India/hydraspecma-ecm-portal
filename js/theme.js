/**
 * theme.js — Shared theme management (light/dark modes).
 * Syncs with localStorage and system preferences.
 */
const THEME_KEY = 'ecm.theme';

export const themeService = {
  init() {
    const stored = globalThis.localStorage?.getItem(THEME_KEY);
    const darkPreferred = globalThis.matchMedia?.('(prefers-color-scheme: dark)').matches;
    
    const theme = stored || (darkPreferred ? 'dark' : 'light');
    this.apply(theme);
    
    // Listen for OS system theme changes
    globalThis.matchMedia?.('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
      if (!globalThis.localStorage?.getItem(THEME_KEY)) {
        this.apply(e.matches ? 'dark' : 'light');
      }
    });
  },

  get() {
    return document.documentElement.classList.contains('dark') ? 'dark' : 'light';
  },

  set(theme) {
    globalThis.localStorage?.setItem(THEME_KEY, theme);
    this.apply(theme);
  },

  toggle() {
    const current = this.get();
    const next = current === 'dark' ? 'light' : 'dark';
    this.set(next);
    return next;
  },

  apply(theme) {
    if (theme === 'dark') {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
    // Dispatch custom event for dynamic components (like charts) to react
    globalThis.dispatchEvent(new CustomEvent('ecm-theme-change', { detail: theme }));
  }
};

// Initialize theme immediately on import
themeService.init();
