/**
 * security.config.js — Client-side security posture reference.
 * The authoritative headers live in vercel.json; this mirrors CSP for local dev
 * and documents the app's XSS/CSRF stance for reviewers.
 * @module config/security
 */
export const CSP = Object.freeze({
  'default-src': ["'self'"],
  'script-src': ["'self'", 'https://cdn.tailwindcss.com', 'https://cdnjs.cloudflare.com', 'https://cdn.jsdelivr.net'],
  'style-src': ["'self'", "'unsafe-inline'", 'https://cdnjs.cloudflare.com', 'https://cdn.jsdelivr.net', 'https://fonts.googleapis.com'],
  'font-src': ["'self'", 'https://fonts.gstatic.com'],
  'img-src': ["'self'", 'data:', 'blob:', 'https:'],
  'connect-src': ["'self'", 'https://*.supabase.co', 'wss://*.supabase.co', 'https://login.microsoftonline.com', 'https://graph.microsoft.com'],
  'frame-src': ["'self'", 'https://app.powerbi.com', 'https://login.microsoftonline.com'],
  'object-src': ["'none'"],
  'base-uri': ["'self'"],
  'form-action': ["'self'"],
});

/** Escapes untrusted text before injection into HTML (XSS guard used app-wide). */
export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}
