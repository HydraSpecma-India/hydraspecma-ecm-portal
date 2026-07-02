/**
 * BaseRepository.js — Generic data-access base (Repository pattern).
 * Concrete repositories (EcmRepository, TaskRepository, …) extend this.
 * All access goes through Supabase; RLS enforces authorization server-side.
 * @module services/core/BaseRepository
 */
import { getSupabase } from '../../config/supabase.config.js';
import { unwrap } from './errors.js';
import { PAGINATION } from '../../config/app.config.js';

export class BaseRepository {
  /** @param {string} table @param {{ defaultColumns?: string }} [opts] */
  constructor(table, { defaultColumns = '*' } = {}) {
    this.table = table;
    this.defaultColumns = defaultColumns;
  }

  /** @protected */ _from() { return getSupabase().from(this.table); }

  /** Apply a filters object to a query. Supports {eq,neq,in,gte,lte,ilike,is}. */
  _applyFilters(query, filters = {}) {
    for (const [key, spec] of Object.entries(filters)) {
      if (spec == null) continue;
      if (typeof spec === 'object' && !Array.isArray(spec)) {
        for (const [op, val] of Object.entries(spec)) {
          if (val == null) continue;
          query = query[op](key, val);
        }
      } else if (Array.isArray(spec)) {
        query = query.in(key, spec);
      } else {
        query = query.eq(key, spec);
      }
    }
    return query;
  }

  async getById(id, columns = this.defaultColumns) {
    return unwrap(await this._from().select(columns).eq('id', id).single(), `${this.table}.getById`);
  }

  /**
   * Paginated, filtered, sorted list.
   * @param {{filters?:object, search?:{column:string,term:string}, order?:{column:string,ascending?:boolean},
   *          page?:number, pageSize?:number, columns?:string}} [opts]
   * @returns {Promise<{data:any[], count:number, page:number, pageSize:number}>}
   */
  async list({ filters, search, order, page = 1, pageSize = PAGINATION.defaultPageSize, columns = this.defaultColumns } = {}) {
    let query = this._from().select(columns, { count: 'exact' });
    query = this._applyFilters(query, filters);
    if (search?.term) query = query.ilike(search.column, `%${search.term}%`);
    if (order?.column) query = query.order(order.column, { ascending: order.ascending ?? true });
    const from = (page - 1) * pageSize;
    query = query.range(from, from + pageSize - 1);
    const { data, error, count } = await query;
    if (error) throw (await import('./errors.js')).fromSupabase(error, `${this.table}.list`);
    return { data: data ?? [], count: count ?? 0, page, pageSize };
  }

  async insert(values) {
    return unwrap(await this._from().insert(values).select().single(), `${this.table}.insert`);
  }

  async update(id, values) {
    return unwrap(await this._from().update(values).eq('id', id).select().single(), `${this.table}.update`);
  }

  async remove(id) {
    return unwrap(await this._from().delete().eq('id', id), `${this.table}.remove`);
  }

  /** Call a Postgres RPC (SECURITY DEFINER function). */
  async rpc(fn, args = {}) {
    return unwrap(await getSupabase().rpc(fn, args), `rpc.${fn}`);
  }
}
