/**
 * realtimeService.js — Supabase Realtime channels (notifications, live records).
 * @module services/realtime/realtimeService
 */
import { getSupabase } from '../../config/supabase.config.js';

export const realtimeService = {
  /**
   * Live in-app notifications for a user (drives the bell + unread counter).
   * @param {string} userId @param {(row:any)=>void} onInsert @returns {() => void} unsubscribe
   */
  subscribeToNotifications(userId, onInsert) {
    const channel = getSupabase()
      .channel(`notifications:${userId}`)
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `recipient_id=eq.${userId}` },
        (payload) => onInsert(payload.new))
      .subscribe();
    return () => getSupabase().removeChannel(channel);
  },

  /**
   * Live changes on any table, optionally filtered (e.g. a single ECM's tasks).
   * @param {{name:string, table:string, filter?:string, event?:string}} cfg
   * @param {(payload:any)=>void} handler @returns {() => void} unsubscribe
   */
  subscribe({ name, table, filter, event = '*' }, handler) {
    const channel = getSupabase()
      .channel(name)
      .on('postgres_changes', { event, schema: 'public', table, ...(filter ? { filter } : {}) }, handler)
      .subscribe();
    return () => getSupabase().removeChannel(channel);
  },
};
