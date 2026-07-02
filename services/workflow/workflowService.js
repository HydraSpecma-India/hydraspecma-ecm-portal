/**
 * workflowService.js — Client interface to the data-driven workflow engine.
 * Reads transitions/states from the wf_* tables and fires transitions via the
 * fn_execute_transition RPC (which enforces state/permission/comment rules in the DB).
 * @module services/workflow/workflowService
 */
import { getSupabase } from '../../config/supabase.config.js';
import { unwrap } from '../core/errors.js';

const ENTITY_TABLE = { ecm: 'ecm_requests', ecr: 'ecr_records', eco: 'eco_records' };

export const workflowService = {
  /** Actions currently available on an entity (outgoing transitions from its state). */
  async availableTransitions(entityType, entityId) {
    const table = ENTITY_TABLE[entityType];
    if (!table) throw new Error(`Unknown entity type: ${entityType}`);
    const row = unwrap(
      await getSupabase().from(table).select('current_state_id').eq('id', entityId).single(),
      'workflow.currentState');
    if (!row?.current_state_id) return [];
    return unwrap(await getSupabase()
      .from('wf_transitions')
      .select('id, action_code, action_label, required_permission, requires_comment, requires_approval, side_effect, to_state:to_state_id (code, name, category, color)')
      .eq('from_state_id', row.current_state_id)
      .eq('is_active', true)
      .order('sort_order', { ascending: true }), 'workflow.availableTransitions');
  },

  /** Fire a transition. The DB validates source-state, permission and comment rules. */
  async transition(entityType, entityId, transitionId, comment = null) {
    return unwrap(await getSupabase().rpc('fn_execute_transition', {
      p_entity_type: entityType, p_entity_id: entityId, p_transition_id: transitionId, p_comment: comment,
    }), 'workflow.transition');
  },

  /** Full timeline (append-only state history) for a change, newest last. */
  async history(ecmRequestId) {
    return unwrap(await getSupabase()
      .from('ecm_state_history')
      .select('id, action_code, comment, performed_at, dwell_seconds, from_state:from_state_id (code,name), to_state:to_state_id (code,name), performed_by:performed_by (full_name)')
      .eq('ecm_request_id', ecmRequestId)
      .order('performed_at', { ascending: true }), 'workflow.history');
  },

  /** Stages + states of the active workflow (for the Mermaid/visual map). */
  async definition(workflowCode = 'HYDRA-ECM-STD') {
    const wf = unwrap(await getSupabase().from('wf_workflows').select('id').eq('code', workflowCode).eq('is_active', true).order('version', { ascending: false }).limit(1).single(), 'workflow.definition');
    const [stages, states, transitions] = await Promise.all([
      getSupabase().from('wf_stages').select('*').eq('workflow_id', wf.id).order('sequence'),
      getSupabase().from('wf_states').select('*').eq('workflow_id', wf.id).order('sequence'),
      getSupabase().from('wf_transitions').select('*').eq('workflow_id', wf.id),
    ]);
    return {
      stages: unwrap(stages, 'workflow.stages'),
      states: unwrap(states, 'workflow.states'),
      transitions: unwrap(transitions, 'workflow.transitions'),
    };
  },
};
