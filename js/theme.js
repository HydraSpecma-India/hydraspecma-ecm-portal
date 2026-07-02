/**
 * theme.js — Shared theme management (light/dark modes).
 * Syncs with localStorage and system preferences.
 */
const THEME_KEY = 'ecm.theme';

export const themeService = {
  init() {
    // Inject custom app stylesheet override dynamically to override hardcoded styles
    if (!document.getElementById('injected-app-styles')) {
      const link = document.createElement('link');
      link.id = 'injected-app-styles';
      link.rel = 'stylesheet';
      link.href = '/css/app.css';
      document.head.appendChild(link);
    }
    this.apply('light');
  },

  get() {
    return 'light';
  },

  set(theme) {
    this.apply('light');
  },

  toggle() {
    this.apply('light');
    return 'light';
  },

  apply(theme) {
    document.documentElement.classList.remove('dark');
    document.documentElement.classList.add('light');
    globalThis.dispatchEvent(new CustomEvent('ecm-theme-change', { detail: 'light' }));
  }
};

// Initialize theme immediately on import
themeService.init();
