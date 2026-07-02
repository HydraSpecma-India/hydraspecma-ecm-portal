/**
 * services/index.js — Barrel export for the service & repository layer.
 * Import the whole API surface from one place:
 *   import { authService, ecmRepository, workflowService } from './services/index.js';
 * @module services
 */
export { getSupabase, resetSupabase } from '../config/supabase.config.js';
export { AppError, fromSupabase, unwrap } from './core/errors.js';
export { BaseRepository } from './core/BaseRepository.js';
export { authService } from './auth/authService.js';
export { realtimeService } from './realtime/realtimeService.js';
export { storageService, BUCKETS } from './storage/storageService.js';
export { workflowService } from './workflow/workflowService.js';
export { ecmRepository } from './ecm/ecmRepository.js';
