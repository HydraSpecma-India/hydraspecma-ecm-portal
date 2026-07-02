/**
 * app.config.js — Central application configuration (client-safe).
 * No secrets here. Environment values are injected at build/deploy time.
 * @module config/app
 */

export const BRAND = Object.freeze({
  name: 'HydraSpecma ECM Portal',
  subtitle: 'Engineering Change Management System',
  colors: {
    primary: '#003A70',
    secondary: '#00A3E0',
    accent: '#0EA5E9',
    background: '#F8FAFC',
    card: '#FFFFFF',
  },
  radius: '16px',
  font: 'Inter, system-ui, -apple-system, Segoe UI, sans-serif',
});

/** Canonical role codes — MUST match the `roles.code` values seeded in the DB. */
export const ROLES = Object.freeze({
  SUPER_ADMIN: 'SUPER_ADMIN',
  ECM_ADMIN: 'ECM_ADMIN',
  ENG_MANAGER: 'ENG_MANAGER',
  CR_BOARD: 'CR_BOARD',
  QUALITY: 'QUALITY',
  PRODUCTION: 'PRODUCTION',
  PLANNING: 'PLANNING',
  PURCHASING: 'PURCHASING',
  WAREHOUSE: 'WAREHOUSE',
  FINANCE: 'FINANCE',
  DEPT_HEAD: 'DEPT_HEAD',
  ENGINEER: 'ENGINEER',
  VIEWER: 'VIEWER',
});

/** Feature flags — flip per environment; wired to modules as they ship. */
export const FEATURES = Object.freeze({
  azureAdSso: true,
  microsoft365: true,
  d365Integration: true,
  powerBi: true,
  aiAssistant: true,
  emailApproval: true,
  pwaOffline: true,
  realtime: true,
});

/** Approved CDN libraries (pinned). Loaded lazily per page — see js/loader.js (Module 4). */
export const CDN = Object.freeze({
  tailwind: 'https://cdn.tailwindcss.com',
  chartjs: 'https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.3/chart.umd.min.js',
  lucide: 'https://unpkg.com/lucide@0.462.0/dist/umd/lucide.min.js',
  gsap: 'https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/gsap.min.js',
  sortable: 'https://cdnjs.cloudflare.com/ajax/libs/Sortable/1.15.2/Sortable.min.js',
  fullcalendar: 'https://cdn.jsdelivr.net/npm/fullcalendar@6.1.15/index.global.min.js',
  qrcode: 'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js',
  pdfjs: 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.4.168/pdf.min.mjs',
  mermaid: 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js',
});

export const PAGINATION = Object.freeze({ defaultPageSize: 25, pageSizes: [10, 25, 50, 100] });

/** Runtime env accessor — resolves from injected globals or import.meta.env. */
export function env(key, fallback = '') {
  const g = (typeof globalThis !== 'undefined' && globalThis.__ENV__) || {};
  const im = (typeof import.meta !== 'undefined' && import.meta.env) || {};
  return g[key] ?? im[key] ?? fallback;
}
