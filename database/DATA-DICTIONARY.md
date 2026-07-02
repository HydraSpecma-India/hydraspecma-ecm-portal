# Data Dictionary — HydraSpecma ECM Portal

Generated from `sql/00_schema_full.sql`. 55 tables across 15 functional areas.

## Identity & Access

### `roles`

> Application roles (Super Admin ... Viewer). Codes mirrored in config/app.config.js ROLES.

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `name` | text |
| `description` | text |
| `hierarchy_level` | int |
| `--` | lower = more privileged (Super Admin=0) is_system boolean |
| `--` | system roles cannot be deleted is_active boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `permissions`

> Fine-grained permission catalog referenced by RLS via fn_has_permission().

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `--` | e.g. 'ecm.create' |
| `'workflow.transition'` | module text |
| `--` | e.g. 'ecm' |
| `'workflow'` | ? |
| `'document'` | ? |
| `'admin'` | action text |
| `--` | e.g. 'create' |
| `'read'` | ? |
| `'update'` | ? |
| `'delete'` | ? |
| `'approve'` | description text |
| `created_at` | timestamptz |

### `role_permissions`

| Column | Type |
|--------|------|
| `role_id` | uuid |
| `permission_id` | uuid |
| `granted_at` | timestamptz |

### `profiles`

> User profile, 1:1 with auth.users; synchronized from Entra ID (Module 13).

| Column | Type |
|--------|------|
| `id` | uuid |
| `email` | citext |
| `full_name` | text |
| `employee_no` | text |
| `job_title` | text |
| `phone` | text |
| `avatar_url` | text |
| `department_id` | uuid |
| `--` | FK added in 0003 (org tables) plant_id uuid |
| `--` | FK added in 0003 manager_id uuid |
| `azure_ad_object_id` | text |
| `--` | Entra ID objectId for SSO mapping locale text |
| `theme` | text |
| `is_active` | boolean |
| `last_login_at` | timestamptz |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `user_roles`

> Assignment of roles to users, optionally scoped to a plant.

| Column | Type |
|--------|------|
| `id` | uuid |
| `user_id` | uuid |
| `role_id` | uuid |
| `plant_id` | uuid |
| `--` | ? |
| `assigned_at` | timestamptz |
| `expires_at` | timestamptz |

## Organization

### `plants`

> Manufacturing plants / sites. Roles and ECMs can be scoped per plant.

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `--` | e.g. 'DK01' name text |
| `address` | text |
| `city` | text |
| `country` | text |
| `timezone` | text |
| `d365_site_id` | text |
| `--` | Dynamics 365 Site/Warehouse mapping is_active boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `departments`

> Organizational units (Quality, Production, Planning, Purchasing, Warehouse, Finance, Engineering...).

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `name` | text |
| `description` | text |
| `parent_id` | uuid |
| `head_user_id` | uuid |
| `plant_id` | uuid |
| `is_active` | boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `customers`

> Customers impacted by / requesting changes. Synced from D365 (Module 12).

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `name` | text |
| `d365_account_id` | text |
| `--` | Dynamics 365 CustAccount country text |
| `contact_name` | text |
| `contact_email` | citext |
| `is_active` | boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `suppliers`

> Suppliers/vendors affected by changes. Synced from D365 (Module 12).

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `name` | text |
| `d365_vendor_id` | text |
| `--` | Dynamics 365 VendAccount country text |
| `contact_name` | text |
| `contact_email` | citext |
| `is_active` | boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

## Workflow engine

### `wf_workflows`

> Versioned workflow definitions. Multiple versions may coexist; one active per code.

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `name` | text |
| `version` | int |
| `description` | text |
| `source_document` | text |
| `--` | provenance |
| `e.g.` | 'ECM Flow.xlsx' is_active boolean |
| `effective_from` | date |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `wf_state_categories`

> Semantic buckets for states (draft, approval, hold, rejected...). Covers the spec status set.

| Column | Type |
|--------|------|
| `code` | citext |
| `name` | text |
| `description` | text |
| `is_terminal_default` | boolean |
| `color` | text |
| `sort_order` | int |

### `wf_stages`

| Column | Type |
|--------|------|
| `id` | uuid |
| `workflow_id` | uuid |
| `code` | citext |
| `name` | text |
| `sequence` | int |
| `entity_type` | text |
| `color` | text |
| `description` | text |
| `created_at` | timestamptz |

### `wf_states`

| Column | Type |
|--------|------|
| `id` | uuid |
| `workflow_id` | uuid |
| `stage_id` | uuid |
| `code` | citext |
| `name` | text |
| `sequence` | int |
| `category` | citext |
| `is_initial` | boolean |
| `is_terminal` | boolean |
| `sla_hours` | int |
| `--` | target dwell time; feeds overdue/bottleneck analytics color text |
| `description` | text |
| `created_at` | timestamptz |

### `wf_transitions`

| Column | Type |
|--------|------|
| `id` | uuid |
| `workflow_id` | uuid |
| `from_state_id` | uuid |
| `--` | ? |
| `action_code` | citext |
| `action_label` | text |
| `required_permission` | citext |
| `--` | checked by fn_has_permission() requires_comment boolean |
| `requires_approval` | boolean |
| `side_effect` | text |
| `guard_expression` | text |
| `--` | optional SQL boolean guard (evaluated by engine) sort_order int |
| `is_active` | boolean |
| `created_at` | timestamptz |

### `wf_task_templates`

| Column | Type |
|--------|------|
| `id` | uuid |
| `workflow_id` | uuid |
| `stage_id` | uuid |
| `state_id` | uuid |
| `seq_number` | int |
| `title` | text |
| `description` | text |
| `task_type` | text |
| `is_mandatory` | boolean |
| `default_assignee_role_id` | uuid |
| `sla_hours` | int |
| `checklist` | jsonb |
| `created_at` | timestamptz |

## Items & BOM

### `items`

> Item / part master. Synced with D365 released products (Module 12).

| Column | Type |
|--------|------|
| `id` | uuid |
| `item_number` | citext |
| `name` | text |
| `description` | text |
| `uom` | text |
| `item_type` | text |
| `product_dimension` | text |
| `revision` | text |
| `lifecycle_state` | text |
| `unit_cost` | numeric(14,4) |
| `currency` | text |
| `d365_item_id` | text |
| `--` | D365 released product number is_active boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `boms`

> Bill of materials headers, versioned per parent item.

| Column | Type |
|--------|------|
| `id` | uuid |
| `bom_number` | citext |
| `item_id` | uuid |
| `name` | text |
| `version` | int |
| `is_active` | boolean |
| `approved_at` | timestamptz |
| `approved_by` | uuid |
| `d365_bom_id` | text |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `bom_lines`

| Column | Type |
|--------|------|
| `id` | uuid |
| `bom_id` | uuid |
| `line_no` | int |
| `component_item_id` | uuid |
| `quantity` | numeric(18,6) |
| `uom` | text |
| `position` | text |
| `ref_designator` | text |
| `valid_from` | date |
| `valid_to` | date |
| `created_at` | timestamptz |

## Change records

### `ecm_requests`

> Master engineering change record. Progresses through the data-driven workflow.

| Column | Type |
|--------|------|
| `id` | uuid |
| `ecm_number` | citext |
| `--` | ? |
| `description` | text |
| `reason` | text |
| `change_type` | text |
| `affected_part_number` | text |
| `affected_bom` | text |
| `primary_item_id` | uuid |
| `customer_id` | uuid |
| `supplier_id` | uuid |
| `department_id` | uuid |
| `plant_id` | uuid |
| `priority` | priority_level |
| `risk_level` | risk_level |
| `cost_impact` | numeric(14,2) |
| `cost_currency` | text |
| `owner_id` | uuid |
| `requestor_id` | uuid |
| `--` | workflow position (all FKs into the data-driven engine) workflow_id uuid |
| `current_stage_id` | uuid |
| `current_state_id` | uuid |
| `status_category` | citext |
| `--` | denormalized cache (trigger-maintained) state_entered_at timestamptz |
| `source` | change_source |
| `d365_reference` | text |
| `created_date` | date |
| `due_date` | date |
| `target_implementation_date` | date |
| `closed_at` | timestamptz |
| `search_tsv` | tsvector |
| `--` | maintained in 0008 is_deleted boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |
| `created_by` | uuid |
| `updated_by` | uuid |

### `ecr_records`

> Engineering Change Request spawned from an accepted pre-request.

| Column | Type |
|--------|------|
| `id` | uuid |
| `ecr_number` | citext |
| `--` | ? |
| `title` | text |
| `solution_description` | text |
| `impact_analysis` | text |
| `current_state_id` | uuid |
| `status_category` | citext |
| `state_entered_at` | timestamptz |
| `crb_meeting_date` | date |
| `priority` | priority_level |
| `risk_level` | risk_level |
| `owner_id` | uuid |
| `d365_ecr_id` | text |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |
| `created_by` | uuid |

### `eco_records`

> Engineering Change Order spawned from an accepted ECR; drives implementation.

| Column | Type |
|--------|------|
| `id` | uuid |
| `eco_number` | citext |
| `--` | ? |
| `ecr_record_id` | uuid |
| `title` | text |
| `implementation_plan` | text |
| `current_state_id` | uuid |
| `status_category` | citext |
| `state_entered_at` | timestamptz |
| `planned_release_date` | date |
| `actual_release_date` | date |
| `ppap_status` | text |
| `owner_id` | uuid |
| `d365_eco_id` | text |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |
| `created_by` | uuid |

### `ecm_links`

| Column | Type |
|--------|------|
| `id` | uuid |
| `source_type` | entity_type |
| `source_id` | uuid |
| `target_type` | entity_type |
| `target_id` | uuid |
| `relation_type` | text |
| `note` | text |
| `created_by` | uuid |
| `created_at` | timestamptz |

### `ecm_affected_items`

| Column | Type |
|--------|------|
| `id` | uuid |
| `ecm_request_id` | uuid |
| `item_id` | uuid |
| `bom_id` | uuid |
| `change_kind` | text |
| `from_revision` | text |
| `to_revision` | text |
| `note` | text |
| `created_at` | timestamptz |

### `ecm_state_history`

| Column | Type |
|--------|------|
| `id` | bigint |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `ecm_request_id` | uuid |
| `--` | denormalized for fast joins workflow_id uuid |
| `from_state_id` | uuid |
| `to_state_id` | uuid |
| `transition_id` | uuid |
| `action_code` | citext |
| `performed_by` | uuid |
| `performed_at` | timestamptz |
| `comment` | text |
| `dwell_seconds` | bigint -- time spent in from_state |

## Tasks

### `ecm_tasks`

> Work items for a change record; support Kanban, list, calendar, timeline and Gantt views.

| Column | Type |
|--------|------|
| `id` | uuid |
| `ecm_request_id` | uuid |
| `entity_type` | entity_type |
| `--` | ecm | ecr | eco this task belongs to entity_id uuid |
| `template_id` | uuid |
| `--` | ? |
| `state_id` | uuid |
| `parent_task_id` | uuid |
| `--` | subtasks seq_number int |
| `title` | text |
| `description` | text |
| `task_type` | text |
| `status` | task_status |
| `progress_pct` | int |
| `priority` | priority_level |
| `assignee_id` | uuid |
| `assignee_role_id` | uuid |
| `is_mandatory` | boolean |
| `sort_order` | int |
| `--` | board / gantt ordering start_date date |
| `due_date` | date |
| `started_at` | timestamptz |
| `completed_at` | timestamptz |
| `completed_by` | uuid |
| `checklist` | jsonb |
| `--` | lightweight inline checklist mirror created_by uuid |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `ecm_task_dependencies`

| Column | Type |
|--------|------|
| `id` | uuid |
| `task_id` | uuid |
| `depends_on_task_id` | uuid |
| `dependency_type` | text |
| `lag_hours` | int |
| `created_at` | timestamptz |

### `task_checklist_items`

| Column | Type |
|--------|------|
| `id` | uuid |
| `task_id` | uuid |
| `position` | int |
| `label` | text |
| `is_done` | boolean |
| `done_by` | uuid |
| `done_at` | timestamptz |
| `created_at` | timestamptz |

### `task_reminders`

| Column | Type |
|--------|------|
| `id` | uuid |
| `task_id` | uuid |
| `remind_at` | timestamptz |
| `channel` | notification_channel |
| `is_sent` | boolean |
| `sent_at` | timestamptz |
| `created_by` | uuid |
| `created_at` | timestamptz |

## Documents

### `document_categories`

> Engineering drawings, CAD, specs, work instructions, etc.

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `name` | text |
| `description` | text |
| `allowed_extensions` | text[] |
| `requires_approval` | boolean |
| `retention_months` | int |
| `created_at` | timestamptz |

### `documents`

> Controlled documents attached to a change record; one row per logical document.

| Column | Type |
|--------|------|
| `id` | uuid |
| `doc_number` | citext |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `ecm_request_id` | uuid |
| `--` | denormalized rollup category_id uuid |
| `name` | text |
| `description` | text |
| `doc_type` | text |
| `status` | document_status |
| `current_version_id` | uuid |
| `--` | FK added after document_versions is_checked_out boolean |
| `checked_out_by` | uuid |
| `checked_out_at` | timestamptz |
| `created_by` | uuid |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `document_versions`

| Column | Type |
|--------|------|
| `id` | uuid |
| `document_id` | uuid |
| `version_no` | int |
| `storage_bucket` | text |
| `storage_path` | text |
| `file_name` | text |
| `file_size` | bigint |
| `mime_type` | text |
| `checksum` | text |
| `--` | sha256 for integrity status document_status |
| `change_note` | text |
| `is_current` | boolean |
| `uploaded_by` | uuid |
| `uploaded_at` | timestamptz |

### `document_signatures`

> 21 CFR Part 11-style e-signatures bound to a specific document version.

| Column | Type |
|--------|------|
| `id` | uuid |
| `document_version_id` | uuid |
| `signer_id` | uuid |
| `meaning` | signature_meaning |
| `signature_hash` | text |
| `--` | HMAC over version checksum + signer + timestamp method text |
| `ip_address` | inet |
| `comment` | text |
| `signed_at` | timestamptz |

## Collaboration

### `comments`

> Threaded discussion attached to any entity; mentions drive notifications.

| Column | Type |
|--------|------|
| `id` | uuid |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `parent_comment_id` | uuid |
| `author_id` | uuid |
| `body` | text |
| `mentions` | uuid[] |
| `--` | profile ids @-mentioned is_internal boolean |
| `--` | hidden from external/viewer roles is_deleted boolean |
| `edited_at` | timestamptz |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `attachments`

| Column | Type |
|--------|------|
| `id` | uuid |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `name` | text |
| `storage_bucket` | text |
| `storage_path` | text |
| `file_size` | bigint |
| `mime_type` | text |
| `uploaded_by` | uuid |
| `created_at` | timestamptz |

## Approvals

### `approval_requests`

> A gate awaiting one or more approvers before a transition may fire.

| Column | Type |
|--------|------|
| `id` | uuid |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `ecm_request_id` | uuid |
| `stage_id` | uuid |
| `state_id` | uuid |
| `transition_id` | uuid |
| `title` | text |
| `description` | text |
| `policy` | approval_policy |
| `quorum` | int |
| `--` | required approvals when policy = 'quorum' status approval_status |
| `requested_by` | uuid |
| `due_at` | timestamptz |
| `decided_at` | timestamptz |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `approval_assignments`

| Column | Type |
|--------|------|
| `id` | uuid |
| `approval_request_id` | uuid |
| `sequence` | int |
| `--` | ordering for sequential policy approver_id uuid |
| `approver_role_id` | uuid |
| `decision` | approval_decision |
| `decision_at` | timestamptz |
| `comment` | text |
| `delegated_to` | uuid |
| `escalated_to` | uuid |
| `notified_at` | timestamptz |
| `created_at` | timestamptz |

### `approval_email_tokens`

| Column | Type |
|--------|------|
| `id` | uuid |
| `assignment_id` | uuid |
| `token` | text |
| `action_scope` | text[] |
| `'reject'` | ? |
| `'return'` | ? |
| `'comment']` | ? |
| `expires_at` | timestamptz |
| `used_at` | timestamptz |
| `used_action` | text |
| `created_at` | timestamptz |

## Notifications & email

### `email_templates`

> Reusable templates for approval, reminder, escalation and assignment emails.

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `name` | text |
| `subject` | text |
| `body_html` | text |
| `body_text` | text |
| `variables` | jsonb |
| `--` | documented merge fields channel notification_channel |
| `is_active` | boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `notification_rules`

> Declarative mapping of events to channels, templates and recipients (Admin-editable).

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `event_type` | text |
| `--` | e.g. 'ecm.transition' |
| `'task.assigned'` | ? |
| `'approval.pending'` | description text |
| `channel` | notification_channel |
| `template_id` | uuid |
| `recipient_expression` | text |
| `--` | owner|requestor|assignee|role:CODE|mentions|manager is_active boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `notifications`

> In-app / multi-channel notifications; realtime via Supabase (Module 11).

| Column | Type |
|--------|------|
| `id` | uuid |
| `recipient_id` | uuid |
| `type` | text |
| `title` | text |
| `body` | text |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `priority` | priority_level |
| `channel` | notification_channel |
| `action_url` | text |
| `meta` | jsonb |
| `is_read` | boolean |
| `read_at` | timestamptz |
| `created_at` | timestamptz |

### `notification_preferences`

| Column | Type |
|--------|------|
| `user_id` | uuid |
| `event_type` | text |
| `channel` | notification_channel |
| `enabled` | boolean |

## Audit

### `audit_logs`

> Immutable field-level audit trail. Never updated/deleted by the app (enforced via RLS).

| Column | Type |
|--------|------|
| `id` | bigint |
| `table_name` | text |
| `record_id` | uuid |
| `entity_type` | entity_type |
| `action` | audit_action |
| `field_name` | text |
| `--` | populated per-field on UPDATE old_value text |
| `new_value` | text |
| `row_snapshot` | jsonb |
| `--` | full row for INSERT / DELETE changed_by uuid |
| `--` | profile id (no FK: audit must survive user deletion) changed_at timestamptz |
| `ip_address` | inet |
| `user_agent` | text |
| `browser` | text |
| `device` | text |
| `session_id` | text |
| `request_id` | text |

## Integration

### `integration_endpoints`

> Configured external systems (D365 F&O, MS Graph, Power BI). Secrets are never stored here.

| Column | Type |
|--------|------|
| `id` | uuid |
| `system` | text |
| `name` | text |
| `base_url` | text |
| `odata_path` | text |
| `auth_type` | text |
| `config` | jsonb |
| `--` | non-secret settings; secrets live in env is_active boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `api_logs`

> Full request/response log for every integration call (Admin > API Logs).

| Column | Type |
|--------|------|
| `id` | bigint |
| `system` | text |
| `endpoint` | text |
| `method` | text |
| `direction` | text |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `correlation_id` | text |
| `request_headers` | jsonb |
| `request_payload` | jsonb |
| `response_status` | int |
| `response_payload` | jsonb |
| `is_success` | boolean |
| `error_message` | text |
| `duration_ms` | int |
| `retry_count` | int |
| `created_at` | timestamptz |

### `integration_sync_state`

| Column | Type |
|--------|------|
| `id` | uuid |
| `system` | text |
| `entity_type` | entity_type |
| `external_id` | text |
| `internal_id` | uuid |
| `direction` | text |
| `last_synced_at` | timestamptz |
| `sync_status` | sync_status |
| `checksum` | text |
| `message` | text |

### `d365_sync_queue`

> Outbound operations to D365 F&O with retry/backoff; drained by an Edge Function (Module 12).

| Column | Type |
|--------|------|
| `id` | uuid |
| `operation` | text |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `ecm_request_id` | uuid |
| `payload` | jsonb |
| `status` | sync_status |
| `attempts` | int |
| `max_attempts` | int |
| `next_retry_at` | timestamptz |
| `last_error` | text |
| `correlation_id` | text |
| `processed_at` | timestamptz |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

## AI assistant

### `ai_conversations`

| Column | Type |
|--------|------|
| `id` | uuid |
| `user_id` | uuid |
| `ecm_request_id` | uuid |
| `title` | text |
| `context` | jsonb |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `ai_messages`

| Column | Type |
|--------|------|
| `id` | uuid |
| `conversation_id` | uuid |
| `role` | text |
| `content` | text |
| `tokens` | int |
| `model` | text |
| `created_at` | timestamptz |

### `ai_insights`

> Persisted AI outputs (summaries, risk, suggested approvers/docs, predictions).

| Column | Type |
|--------|------|
| `id` | uuid |
| `ecm_request_id` | uuid |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `insight_type` | text |
| `summary` | text |
| `content` | jsonb |
| `model` | text |
| `confidence` | numeric(4,3) |
| `created_by` | uuid |
| `created_at` | timestamptz |

## Analytics & BI

### `powerbi_reports`

> Registry of embeddable Power BI reports (SSO, filter-by-ECM).

| Column | Type |
|--------|------|
| `id` | uuid |
| `name` | text |
| `description` | text |
| `workspace_id` | text |
| `report_id` | text |
| `dataset_id` | text |
| `embed_url` | text |
| `rls_role` | text |
| `--` | Power BI RLS role for row filtering filter_field text |
| `--` | field used to filter by ECM is_active boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `report_definitions`

> Built-in report catalog (Executive, Compliance, Engineering, Cycle Time...).

| Column | Type |
|--------|------|
| `id` | uuid |
| `code` | citext |
| `name` | text |
| `category` | text |
| `description` | text |
| `source_view` | text |
| `--` | analytics view backing the report params jsonb |
| `export_formats` | text[] |
| `'excel'` | ? |
| `'csv']` | ? |
| `is_active` | boolean |
| `created_at` | timestamptz |

### `dashboard_layouts`

| Column | Type |
|--------|------|
| `id` | uuid |
| `user_id` | uuid |
| `--` | ? |
| `scope` | text |
| `config` | jsonb |
| `--` | widgets |
| `order` | ? |
| `sizes` | is_default boolean |
| `is_shared` | boolean |
| `created_at` | timestamptz |
| `updated_at` | timestamptz |

### `saved_filters`

| Column | Type |
|--------|------|
| `id` | uuid |
| `user_id` | uuid |
| `name` | text |
| `scope` | text |
| `criteria` | jsonb |
| `is_default` | boolean |
| `created_at` | timestamptz |

## System

### `number_sequences`

| Column | Type |
|--------|------|
| `scope` | text |
| `--` | e.g. 'ECM:2026' current_value bigint |

### `qr_codes`

> Resolvable short codes for QR scanning; open the related record in the portal.

| Column | Type |
|--------|------|
| `id` | uuid |
| `entity_type` | entity_type |
| `entity_id` | uuid |
| `code` | text |
| `--` | short scan slug target_url text |
| `created_by` | uuid |
| `created_at` | timestamptz |

