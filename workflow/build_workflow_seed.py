#!/usr/bin/env python3
"""Emit supabase/seed/30_workflow.sql from workflow/ecm-flow.json.
Idempotent (ON CONFLICT upserts). Column contracts must match migration 0004."""
import json

cfg = json.load(open("workflow/ecm-flow.json"))
wf, stages, states = cfg["workflow"], cfg["stages"], cfg["states"]
trans, tasks = cfg["transitions"], cfg["task_templates"]
stage_id = {s["code"]: s["id"] for s in stages}
state_id = {s["code"]: s["id"] for s in states}

def q(v):
    if v is None: return "NULL"
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return str(v)
    return "'" + str(v).replace("'", "''") + "'"

L = []
w = L.append
w("-- =============================================================================")
w("-- 30_workflow.sql  —  Workflow import (GENERATED from workflow/ecm-flow.json)")
w("-- Source: ECM Flow.xlsx  |  DO NOT EDIT BY HAND — re-run workflow/build_workflow_seed.py")
w("-- Idempotent: safe to run repeatedly (ON CONFLICT upserts).")
w("-- =============================================================================")
w("BEGIN;")
w("")
w("-- 1) Workflow definition -----------------------------------------------------")
w("INSERT INTO wf_workflows (id, code, name, version, description, source_document, is_active, effective_from)")
w(f"VALUES ({q(wf['id'])}, {q(wf['code'])}, {q(wf['name'])}, {wf['version']}, {q(wf['description'])}, {q(wf['source_document'])}, true, CURRENT_DATE)")
w("ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description,")
w("  source_document=EXCLUDED.source_document, is_active=EXCLUDED.is_active, updated_at=now();")
w("")
w("-- 2) Stages ------------------------------------------------------------------")
w("INSERT INTO wf_stages (id, workflow_id, code, name, sequence, entity_type, color, description) VALUES")
rows = [f"  ({q(s['id'])}, {q(wf['id'])}, {q(s['code'])}, {q(s['name'])}, {s['sequence']}, {q(s['entity_type'])}, {q(s['color'])}, {q(s['description'])})" for s in stages]
w(",\n".join(rows) + "")
w("ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, sequence=EXCLUDED.sequence,")
w("  entity_type=EXCLUDED.entity_type, color=EXCLUDED.color, description=EXCLUDED.description;")
w("")
w("-- 3) States ------------------------------------------------------------------")
w("INSERT INTO wf_states (id, workflow_id, stage_id, code, name, sequence, category, is_initial, is_terminal, sla_hours, color, description) VALUES")
rows = []
for s in states:
    rows.append(f"  ({q(s['id'])}, {q(wf['id'])}, {q(stage_id[s['stage_code']])}, {q(s['code'])}, {q(s['name'])}, "
                f"{s['sequence']}, {q(s['category'])}, {q(s['is_initial'])}, {q(s['is_terminal'])}, "
                f"{q(s['sla_hours'])}, {q(s['color'])}, {q(s['description'])})")
w(",\n".join(rows))
w("ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, sequence=EXCLUDED.sequence, category=EXCLUDED.category,")
w("  is_initial=EXCLUDED.is_initial, is_terminal=EXCLUDED.is_terminal, sla_hours=EXCLUDED.sla_hours,")
w("  color=EXCLUDED.color, description=EXCLUDED.description;")
w("")
w("-- 4) Transitions -------------------------------------------------------------")
w("INSERT INTO wf_transitions (id, workflow_id, from_state_id, to_state_id, action_code, action_label, required_permission, requires_comment, requires_approval, side_effect, sort_order) VALUES")
rows = []
for t in trans:
    rows.append(f"  ({q(t['id'])}, {q(wf['id'])}, {q(state_id[t['from_code']])}, {q(state_id[t['to_code']])}, "
                f"{q(t['action_code'])}, {q(t['action_label'])}, {q(t['required_permission'])}, "
                f"{q(t['requires_comment'])}, {q(t['requires_approval'])}, {q(t['side_effect'])}, {t['sort_order']})")
w(",\n".join(rows))
w("ON CONFLICT (id) DO UPDATE SET action_label=EXCLUDED.action_label, required_permission=EXCLUDED.required_permission,")
w("  requires_comment=EXCLUDED.requires_comment, requires_approval=EXCLUDED.requires_approval,")
w("  side_effect=EXCLUDED.side_effect, sort_order=EXCLUDED.sort_order;")
w("")
w("-- 5) Task templates (default role resolved by code) --------------------------")
w("INSERT INTO wf_task_templates (id, workflow_id, stage_id, state_id, seq_number, title, description, task_type, is_mandatory, default_assignee_role_id, sla_hours) VALUES")
rows = []
for t in tasks:
    role = f"(SELECT id FROM roles WHERE code={q(t['default_role_code'])})" if t.get("default_role_code") else "NULL"
    rows.append(f"  ({q(t['id'])}, {q(wf['id'])}, {q(stage_id[t['stage_code']])}, {q(state_id[t['state_code']])}, "
                f"{t['seq']}, {q(t['title'])}, {q(t['description'])}, {q(t['task_type'])}, {q(t['is_mandatory'])}, "
                f"{role}, {q(t['sla_hours'])})")
w(",\n".join(rows))
w("ON CONFLICT (id) DO UPDATE SET title=EXCLUDED.title, task_type=EXCLUDED.task_type,")
w("  is_mandatory=EXCLUDED.is_mandatory, default_assignee_role_id=EXCLUDED.default_assignee_role_id,")
w("  seq_number=EXCLUDED.seq_number, sla_hours=EXCLUDED.sla_hours;")
w("")
w("COMMIT;")
open("supabase/seed/30_workflow.sql", "w").write("\n".join(L) + "\n")
print("wrote supabase/seed/30_workflow.sql", len(L), "lines")
