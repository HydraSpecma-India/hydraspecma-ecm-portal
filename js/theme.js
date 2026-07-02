/**
 * theme.js — Shared theme management (light/dark modes).
 * Syncs with localStorage and system preferences.
 */
const THEME_KEY = 'ecm.theme';

export const themeService = {
  init() {
    this.apply('dark');
  },

  get() {
    return 'dark';
  },

  set(theme) {
    this.apply('dark');
  },

  toggle() {
    this.apply('dark');
    return 'dark';
  },

  apply(theme) {
    document.documentElement.classList.add('dark');
    globalThis.dispatchEvent(new CustomEvent('ecm-theme-change', { detail: 'dark' }));
  }
};

// Initialize theme immediately on import
themeService.init();
