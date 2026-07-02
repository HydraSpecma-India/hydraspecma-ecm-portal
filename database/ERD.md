# Entity-Relationship Diagram — Core Model

Curated view of the most important relationships. Full column detail is in
[`DATA-DICTIONARY.md`](./DATA-DICTIONARY.md). All 55 tables live in `public`.

```mermaid
erDiagram
    profiles ||--o{ user_roles : has
    roles ||--o{ user_roles : assigned
    roles ||--o{ role_permissions : grants
    permissions ||--o{ role_permissions : in
    plants ||--o{ departments : contains
    departments ||--o{ profiles : employs

    wf_workflows ||--o{ wf_stages : defines
    wf_stages ||--o{ wf_states : contains
    wf_states ||--o{ wf_transitions : "from/to"
    wf_states ||--o{ wf_task_templates : checklist
    wf_state_categories ||--o{ wf_states : classifies

    ecm_requests ||--o{ ecr_records : spawns
    ecr_records ||--o{ eco_records : spawns
    ecm_requests ||--o{ eco_records : owns
    wf_states ||--o{ ecm_requests : "current state"
    ecm_requests ||--o{ ecm_state_history : logs
    ecm_requests ||--o{ ecm_tasks : has
    ecm_requests ||--o{ ecm_affected_items : affects
    items ||--o{ ecm_affected_items : referenced
    items ||--o{ boms : "has BOM"
    boms ||--o{ bom_lines : contains

    ecm_tasks ||--o{ ecm_task_dependencies : depends
    ecm_tasks ||--o{ task_checklist_items : checklist
    wf_task_templates ||--o{ ecm_tasks : instantiates

    ecm_requests ||--o{ documents : attaches
    documents ||--o{ document_versions : versions
    document_versions ||--o{ document_signatures : signed

    ecm_requests ||--o{ approval_requests : gates
    approval_requests ||--o{ approval_assignments : to
    approval_assignments ||--o{ approval_email_tokens : email

    ecm_requests ||--o{ comments : discussed
    ecm_requests ||--o{ ai_insights : analyzed
    profiles ||--o{ notifications : receives
    ecm_requests ||--o{ qr_codes : identified
    ecm_requests ||--o{ d365_sync_queue : syncs
```

## Key design decisions

- **Data-driven workflow.** `ecm_requests.current_state_id` (and `ecr`/`eco`) point into `wf_states`; movement is validated by `fn_execute_transition()` against `wf_transitions`. Changing the process = changing data, never code.
- **One master, two artifacts.** The `ecm_requests` master flows through the whole lifecycle. `ecr_records` and `eco_records` are spawned as first-class, separately-numbered artifacts (their own QR codes, D365 links, documents) via transition side-effects.
- **Polymorphic collaboration.** `comments`, `attachments`, `documents`, `approval_requests`, `audit_logs` and `ecm_links` use `(entity_type, entity_id)` so any record can be discussed, documented, approved and audited.
- **Append-only history & audit.** `ecm_state_history` (dwell time per state) and field-level `audit_logs` are written by `SECURITY DEFINER` triggers and are read-only to clients.
- **Denormalized `status_category`** on the change tables gives fast dashboard filtering without joining the workflow tables on every query; it is trigger-maintained.
