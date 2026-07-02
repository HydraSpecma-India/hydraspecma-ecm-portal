/**
 * ecmRepository.js — Data access for change records (extends BaseRepository).
 * Reads use the enriched vw_ecm_overview; the dashboard reads vw_dashboard_kpis.
 * @module services/ecm/ecmRepository
 */
import { getSupabase } from '../../config/supabase.config.js';
import { BaseRepository } from '../core/BaseRepository.js';
import { unwrap } from '../core/errors.js';

class EcmRepository extends BaseRepository {
  constructor() { super('ecm_requests'); }

  /** Paginated, filtered list from the label-resolved overview view. */
  async listOverview({ filters, search, order = { column: 'created_date', ascending: false }, page = 1, pageSize = 25 } = {}) {
    let q = getSupabase().from('vw_ecm_overview').select('*', { count: 'exact' });
    q = this._applyFilters(q, filters);
    if (search?.term) q = q.or(`ecm_number.ilike.%${search.term}%,title.ilike.%${search.term}%`);
    q = q.order(order.column, { ascending: order.ascending }).range((page - 1) * pageSize, page * pageSize - 1);
    const { data, error, count } = await q;
    if (error) throw (await import('../core/errors.js')).fromSupabase(error, 'ecm.listOverview');
    return { data: data ?? [], count: count ?? 0, page, pageSize };
  }

  /** Create a pre-request. Numbering + initial workflow state are set by DB triggers. */
  async create({ title, description, reason, priority = 'medium', risk_level = 'low', department_id, plant_id, customer_id, supplier_id, affected_part_number, cost_impact }) {
    return this.insert({ title, description, reason, priority, risk_level, department_id, plant_id, customer_id, supplier_id, affected_part_number, cost_impact });
  }

  /** Executive KPI card values (single row). */
  async dashboardKpis() {
    return unwrap(await getSupabase().from('vw_dashboard_kpis').select('*').single(), 'ecm.dashboardKpis');
  }

  /** Soft-delete (RLS restricts to admins). */
  async softDelete(id) { return this.update(id, { is_deleted: true }); }
}

export const ecmRepository = new EcmRepository();
