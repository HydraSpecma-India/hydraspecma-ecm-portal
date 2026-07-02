/**
 * storageService.js — Supabase Storage helpers for documents & attachments.
 * Buckets are created in migration 0021_storage_buckets.sql.
 * @module services/storage/storageService
 */
import { getSupabase } from '../../config/supabase.config.js';
import { unwrap } from '../core/errors.js';

export const BUCKETS = Object.freeze({
  documents: 'ecm-documents',
  attachments: 'ecm-attachments',
  exports: 'ecm-exports',
  avatars: 'ecm-avatars',
});

export const storageService = {
  /** Upload a File/Blob. Returns the storage path. */
  async upload(bucket, path, file, { upsert = false, contentType } = {}) {
    const data = unwrap(await getSupabase().storage.from(bucket).upload(path, file, {
      upsert, contentType: contentType ?? file.type, cacheControl: '3600',
    }), 'storage.upload');
    return data.path;
  },

  async download(bucket, path) {
    return unwrap(await getSupabase().storage.from(bucket).download(path), 'storage.download');
  },

  /** Time-limited signed URL for a private object (e.g. preview/download). */
  async signedUrl(bucket, path, expiresIn = 3600) {
    const data = unwrap(await getSupabase().storage.from(bucket).createSignedUrl(path, expiresIn), 'storage.signedUrl');
    return data.signedUrl;
  },

  publicUrl(bucket, path) {
    return getSupabase().storage.from(bucket).getPublicUrl(path).data.publicUrl;
  },

  async remove(bucket, paths) {
    return unwrap(await getSupabase().storage.from(bucket).remove(Array.isArray(paths) ? paths : [paths]), 'storage.remove');
  },
};
