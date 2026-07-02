/**
 * errors.js — Uniform error handling for the service layer.
 * Translates Supabase/PostgREST/PostgreSQL errors into user-friendly AppErrors.
 * @module services/core/errors
 */

export class AppError extends Error {
  /** @param {string} message @param {{code?:string, cause?:unknown, context?:string, status?:number}} [opts] */
  constructor(message, { code, cause, context, status } = {}) {
    super(message);
    this.name = 'AppError';
    this.code = code ?? 'app_error';
    this.cause = cause;
    this.context = context;
    this.status = status;
  }
}

/** Postgres SQLSTATE / PostgREST → friendly messages. */
const PG_MESSAGES = {
  '42501': 'You do not have permission to perform this action.',
  '23505': 'That record already exists.',
  '23503': 'A related record is missing or still referenced.',
  '23514': 'A value failed a validation rule.',
  '23502': 'A required field is missing.',
  'P0001': null, // RAISE EXCEPTION from our functions — pass the message through
  'PGRST301': 'Your session has expired. Please sign in again.',
};

/**
 * Normalizes any thrown/returned Supabase error into an AppError.
 * @param {any} error @param {string} [context]
 * @returns {AppError}
 */
export function fromSupabase(error, context) {
  if (!error) return new AppError('Unknown error', { context });
  const code = error.code || error.status?.toString();
  const mapped = Object.prototype.hasOwnProperty.call(PG_MESSAGES, code) ? PG_MESSAGES[code] : undefined;
  const message = mapped ?? error.message ?? 'Request failed';
  return new AppError(message, { code: code ?? 'app_error', cause: error, context, status: error.status });
}

/** Throws if a Supabase `{ data, error }` result carries an error; otherwise returns data. */
export function unwrap({ data, error }, context) {
  if (error) throw fromSupabase(error, context);
  return data;
}
