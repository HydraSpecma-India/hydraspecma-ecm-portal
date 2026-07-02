/**
 * authService.js — Authentication & session (Supabase Auth + Azure AD SSO).
 * @module services/auth/authService
 */
import { getSupabase, resetSupabase } from '../../config/supabase.config.js';
import { unwrap, fromSupabase } from '../core/errors.js';
import { env } from '../../config/app.config.js';

const REMEMBER_KEY = 'ecm.rememberMe';

export const authService = {
  /** Email/password sign-in. `remember=false` clears the session when the tab closes. */
  async signIn(email, password, remember = true) {
    const data = unwrap(await getSupabase().auth.signInWithPassword({ email, password }), 'auth.signIn');
    try { globalThis.localStorage?.setItem(REMEMBER_KEY, remember ? '1' : '0'); } catch { /* no-op */ }
    await this.touchLastLogin();
    return data;
  },

  /** Microsoft Entra ID (Azure AD) / Microsoft 365 SSO via OAuth (PKCE). */
  async signInWithAzure() {
    return unwrap(await getSupabase().auth.signInWithOAuth({
      provider: 'azure',
      options: {
        scopes: env('MS_GRAPH_SCOPES', 'openid profile email offline_access User.Read'),
        redirectTo: `${globalThis.location?.origin ?? ''}/auth/callback`,
      },
    }), 'auth.signInWithAzure');
  },

  async signOut() {
    try { await getSupabase().auth.signOut(); } finally { resetSupabase(); }
  },

  /** Send a password-reset email. */
  async requestPasswordReset(email) {
    return unwrap(await getSupabase().auth.resetPasswordForEmail(email, {
      redirectTo: `${globalThis.location?.origin ?? ''}/auth/reset`,
    }), 'auth.requestPasswordReset');
  },

  /** Set a new password (after following the reset link). */
  async updatePassword(newPassword) {
    return unwrap(await getSupabase().auth.updateUser({ password: newPassword }), 'auth.updatePassword');
  },

  async getSession() {
    const { data, error } = await getSupabase().auth.getSession();
    if (error) throw fromSupabase(error, 'auth.getSession');
    return data.session;
  },

  /** Subscribe to auth changes. Returns an unsubscribe function. */
  onChange(callback) {
    const { data } = getSupabase().auth.onAuthStateChange((event, session) => callback(event, session));
    return () => data.subscription.unsubscribe();
  },

  /** Current profile + role codes + permission codes (via fn_me RPC). */
  async me() {
    return unwrap(await getSupabase().rpc('fn_me'), 'auth.me');
  },

  async touchLastLogin() {
    try { await getSupabase().rpc('fn_touch_last_login'); } catch { /* non-critical */ }
  },

  isRemembered() {
    try { return globalThis.localStorage?.getItem(REMEMBER_KEY) !== '0'; } catch { return true; }
  },
};
