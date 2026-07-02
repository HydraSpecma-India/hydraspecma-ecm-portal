/**
 * auth-guard.js — Lightweight client-side route guard.
 * Checks session status and redirects unauthenticated users to `/login.html`.
 */
import { authService } from '../services/auth/authService.js';

async function checkAuth() {
  const path = globalThis.location.pathname;
  const isAuthPage = path.includes('/login') || path.includes('/auth/callback') || path.includes('/auth/reset');

  try {
    const session = await authService.getSession();
    if (!session) {
      if (!isAuthPage) {
        console.log('[auth-guard] Unauthenticated user, redirecting to login...');
        globalThis.location.href = '/login.html';
      }
    } else {
      if (isAuthPage) {
        console.log('[auth-guard] Authenticated user on auth page, redirecting to dashboard...');
        globalThis.location.href = '/';
      }
    }
  } catch (error) {
    console.error('[auth-guard] Session check failed:', error);
    if (!isAuthPage) {
      globalThis.location.href = '/login.html';
    }
  }
}

// Execute route check immediately
checkAuth();
