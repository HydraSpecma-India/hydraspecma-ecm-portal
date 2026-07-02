#!/usr/bin/env python3
"""
HydraSpecma ECM Portal — Workflow Config Builder
-------------------------------------------------
Parses the business workflow captured in `ECM Flow.xlsx` (Sheet1 = tasks &
sequence numbers, Sheet2 = state machine & transitions) into a normalized,
version-controlled workflow definition.

Outputs:
  * workflow/ecm-flow.json          -> machine-readable workflow config (source of truth for imports)
  * supabase/seed/30_workflow.sql   -> idempotent seed that imports the config into Postgres/Supabase

The workflow is NEVER hardcoded in application code — it lives in the
wf_* tables and is loaded from here. Editing the flow = editing data.

Deterministic UUIDv5 identifiers are derived from stable business codes so
transitions/tasks can reference states without subqueries, and re-running the
seed is fully idempotent.
"""
import json
import uuid

NS = uuid.UUID("6f9619ff-8b86-d011-b42d-00cf4fc964ff")  # fixed namespace for this workflow

def uid(kind: str, code: str) -> str:
    return str(uuid.uuid5(NS, f"{kind}:{code}"))

WORKFLOW = {
    "code": "HYDRA-ECM-STD",
    "name": "HydraSpecma Standard Engineering Change Flow",
    "version": 1,
    "source_document": "ECM Flow.xlsx",
    "description": "Pre-request -> ECR -> ECO -> Resolved. Derived from HydraSpecma ECM Flow workbook.",
}
WORKFLOW["id"] = uid("workflow", f'{WORKFLOW["code"]}:v{WORKFLOW["version"]}')

# ---------------------------------------------------------------- stages
# entity_type drives which record (ECM master / ECR / ECO) the stage governs.
STAGES = [
    {"code": "PRE", "name": "Pre-request",  "sequence": 10, "entity_type": "ECM", "color": "#64748B",
     "description": "Idea capture, information gathering and screening/go-ahead decision."},
    {"code": "ECR", "name": "ECR",          "sequence": 20, "entity_type": "ECR", "color": "#0EA5E9",
     "description": "Engineering Change Request: impact analysis, solution, CR-board and customer decision."},
    {"code": "ECO", "name": "ECO",          "sequence": 30, "entity_type": "ECO", "color": "#00A3E0",
     "description": "Engineering Change Order: implementation planning, execution, review and release."},
    {"code": "CLOSED", "name": "Closed",    "sequence": 40, "entity_type": "ECM", "color": "#16A34A",
     "description": "Terminal grouping for resolved / rejected / cancelled changes."},
]
for s in STAGES:
    s["id"] = uid("stage", f'{WORKFLOW["code"]}:{s["code"]}')

# ---------------------------------------------------------------- states
# category values are validated against the wf_state_categories lookup table.
# is_initial marks the entry state of a stage; is_terminal marks a dead-end (no outgoing transitions).
def st(stage, code, name, seq, category, initial=False, terminal=False, sla=None, color=None, desc=""):
    return {
        "stage_code": stage, "code": code, "name": name, "sequence": seq,
        "category": category, "is_initial": initial, "is_terminal": terminal,
        "sla_hours": sla, "color": color, "description": desc,
    }

STATES = [
    # Pre-request
    st("PRE", "PRE_DRAFT",     "Draft",              10, "draft",      initial=True, sla=72,  desc="Requestor fills in the pre-request."),
    st("PRE", "PRE_SCREENING", "Screening",          20, "screening",  sla=48, desc="Under review; go-ahead decision is taken."),
    st("PRE", "PRE_ACCEPTED",  "Accepted",           30, "accepted",   desc="Pre-request accepted; linked to an ECR."),
    st("PRE", "PRE_HOLD",      "Hold",               40, "hold",       desc="Temporarily paused."),
    st("PRE", "PRE_BACKLOG",   "Backlog",            50, "backlog",    desc="Waiting for an implementation opportunity."),
    st("PRE", "PRE_REJECTED",  "Rejected",           60, "rejected",   terminal=True, desc="No action will be taken."),
    st("PRE", "PRE_CANCELLED", "Cancelled",          70, "cancelled",  terminal=True, desc="Solved by another change."),
    # ECR
    st("ECR", "ECR_PREP",      "Implementation preparation", 10, "in_progress", initial=True, sla=120,
       desc="ECR number shared; impact analysed; solution prepared and reviewed."),
    st("ECR", "ECR_CRB",       "CR-board",           20, "approval",   sla=72, desc="Change Review Board meeting and go-ahead decision."),
    st("ECR", "ECR_PRELIM",    "Preliminary accepted",30,"in_progress", sla=120, desc="Preliminary accepted; customer discussion and decision."),
    st("ECR", "ECR_ACCEPTED",  "Accepted",           40, "accepted",   desc="ECR accepted; linked to an ECO."),
    st("ECR", "ECR_HOLD",      "Hold",               50, "hold",       desc="Temporarily paused."),
    st("ECR", "ECR_BACKLOG",   "Backlog",            60, "backlog",    desc="Waiting for an implementation opportunity."),
    st("ECR", "ECR_REJECTED",  "Rejected",           70, "rejected",   terminal=True, desc="No action will be taken."),
    st("ECR", "ECR_CANCELLED", "Cancelled",          80, "cancelled",  terminal=True, desc="Solved by another change."),
    # ECO
    st("ECO", "ECO_TASKLIST",     "Task list",              10, "in_progress", initial=True, sla=72,
       desc="ECO created, stakeholders informed and implementation task list built."),
    st("ECO", "ECO_REVIEW_TASKS", "Review task list",       20, "review",      sla=48, desc="Implementation task list reviewed/evaluated."),
    st("ECO", "ECO_IMPL",         "Implementation",         30, "in_progress", sla=240, desc="Execute implementation plan (items, BOM, docs, purchasing, PPAP)."),
    st("ECO", "ECO_IMPL_REVIEW",  "Implementation review",  40, "review",      sla=48, desc="Review implementation; accept or rework."),
    st("ECO", "ECO_REL_SCHED",    "Released for scheduling",50, "in_progress", sla=72, desc="Local scheduling and customer agreement."),
    st("ECO", "ECO_REL_PROD",     "Released for production", 60,"in_progress", sla=240, desc="Update ECO/component data, PPAP follow-up, orders, stock clean-up, quality."),
    st("ECO", "ECO_FINAL_REVIEW", "Final review",           70, "review",      sla=48, desc="Final review/evaluation of the implementation."),
    st("ECO", "ECO_REJECTED",     "Rejected",               80, "rejected",    terminal=True, desc="No action will be taken."),
    st("ECO", "ECO_CANCELLED",    "Cancelled",              90, "cancelled",   terminal=True, desc="Solved by another change."),
    # Closed
    st("CLOSED", "RESOLVED", "Resolved", 10, "resolved", terminal=True, color="#16A34A",
       desc="Change successfully implemented and closed."),
]
for s in STATES:
    s["id"] = uid("state", f'{WORKFLOW["code"]}:{s["code"]}')
STATE_ID = {s["code"]: s["id"] for s in STATES}
STATE_STAGE = {s["code"]: s["stage_code"] for s in STATES}

# ---------------------------------------------------------------- transitions
# action_code is the machine trigger; required_permission gates who may fire it (checked by fn_has_permission).
def tr(frm, to, action, label, perm=None, comment=False, approval=False, effect=None, order=0):
    return {
        "from_code": frm, "to_code": to, "action_code": action, "action_label": label,
        "required_permission": perm, "requires_comment": comment, "requires_approval": approval,
        "side_effect": effect, "sort_order": order,
    }

TRANSITIONS = [
    # Pre-request
    tr("PRE_DRAFT",     "PRE_SCREENING", "submit",           "Submit pre-request for screening", "ecm.submit", order=10),
    tr("PRE_SCREENING", "PRE_ACCEPTED",  "accept",           "Accept pre-request",               "ecm.screen", comment=True, order=10),
    tr("PRE_SCREENING", "PRE_DRAFT",     "return",           "Return pre-request",               "ecm.screen", comment=True, order=20),
    tr("PRE_SCREENING", "PRE_HOLD",      "hold",             "Hold pre-request",                 "ecm.screen", comment=True, order=30),
    tr("PRE_SCREENING", "PRE_BACKLOG",   "backlog",          "Move to backlog",                  "ecm.screen", order=40),
    tr("PRE_SCREENING", "PRE_REJECTED",  "reject",           "Reject pre-request",               "ecm.screen", comment=True, order=50),
    tr("PRE_SCREENING", "PRE_CANCELLED", "cancel",           "Cancel pre-request",               "ecm.screen", comment=True, order=60),
    tr("PRE_HOLD",      "PRE_SCREENING", "resume",           "Resume screening",                 "ecm.screen", order=10),
    tr("PRE_BACKLOG",   "PRE_SCREENING", "reactivate",       "Reactivate from backlog",          "ecm.screen", order=10),
    tr("PRE_ACCEPTED",  "ECR_PREP",      "link_to_ecr",      "Create ECR & share number",        "ecr.create", effect="create_ecr", order=10),
    # ECR
    tr("ECR_PREP",      "ECR_CRB",       "submit_to_crb",    "Submit solution to CR-board",      "ecr.submit", order=10),
    tr("ECR_CRB",       "ECR_PRELIM",    "prelim_accept",    "Preliminary accept (CRB)",         "ecr.crb_decide", comment=True, approval=True, order=10),
    tr("ECR_CRB",       "ECR_PREP",      "return",           "Return solution",                  "ecr.crb_decide", comment=True, order=20),
    tr("ECR_CRB",       "ECR_HOLD",      "hold",             "Hold solution",                    "ecr.crb_decide", comment=True, order=30),
    tr("ECR_CRB",       "ECR_BACKLOG",   "backlog",          "Move to backlog",                  "ecr.crb_decide", order=40),
    tr("ECR_CRB",       "ECR_REJECTED",  "reject",           "Reject solution",                  "ecr.crb_decide", comment=True, approval=True, order=50),
    tr("ECR_CRB",       "ECR_CANCELLED", "cancel",           "Cancel ECR",                       "ecr.crb_decide", comment=True, order=60),
    tr("ECR_HOLD",      "ECR_CRB",       "resume",           "Resume at CR-board",               "ecr.crb_decide", order=10),
    tr("ECR_BACKLOG",   "ECR_CRB",       "reactivate",       "Reactivate from backlog",          "ecr.crb_decide", order=10),
    tr("ECR_PRELIM",    "ECR_ACCEPTED",  "customer_accept", "Customer accepts ECR",             "ecr.customer_decide", comment=True, order=10),
    tr("ECR_PRELIM",    "ECR_REJECTED",  "customer_reject", "Customer rejects ECR",             "ecr.customer_decide", comment=True, order=20),
    tr("ECR_PRELIM",    "ECR_CANCELLED", "cancel",           "Cancel ECR",                       "ecr.customer_decide", comment=True, order=30),
    tr("ECR_ACCEPTED",  "ECO_TASKLIST",  "link_to_eco",      "Create ECO & inform stakeholders", "eco.create", effect="create_eco", order=10),
    # ECO
    tr("ECO_TASKLIST",     "ECO_REVIEW_TASKS", "submit_tasklist", "Submit task list for review",  "eco.manage", order=10),
    tr("ECO_REVIEW_TASKS", "ECO_IMPL",         "accept",          "Accept task list",             "eco.review", comment=True, order=10),
    tr("ECO_REVIEW_TASKS", "ECO_TASKLIST",     "rework",          "Rework task list",             "eco.review", comment=True, order=20),
    tr("ECO_IMPL",         "ECO_IMPL_REVIEW",  "submit_review",   "Submit implementation for review","eco.manage", order=10),
    tr("ECO_IMPL_REVIEW",  "ECO_REL_SCHED",    "accept",          "Accept implementation",        "eco.review", comment=True, approval=True, order=10),
    tr("ECO_IMPL_REVIEW",  "ECO_IMPL",         "rework",          "Rework implementation",        "eco.review", comment=True, order=20),
    tr("ECO_REL_SCHED",    "ECO_REL_PROD",     "release_prod",    "Release for production",       "eco.release", comment=True, approval=True, order=10),
    tr("ECO_REL_SCHED",    "ECO_REJECTED",     "reject",          "Reject (customer)",            "eco.review", comment=True, order=20),
    tr("ECO_REL_SCHED",    "ECO_CANCELLED",    "cancel",          "Cancel ECO",                   "eco.review", comment=True, order=30),
    tr("ECO_REL_PROD",     "ECO_FINAL_REVIEW", "submit_final",    "Submit for final review",      "eco.manage", order=10),
    tr("ECO_FINAL_REVIEW", "RESOLVED",         "resolve",         "Resolve & close",              "eco.close", comment=True, approval=True, effect="close_ecm", order=10),
    tr("ECO_FINAL_REVIEW", "ECO_REL_PROD",     "rework",          "Rework (production)",          "eco.review", comment=True, order=20),
]
for t in TRANSITIONS:
    t["id"] = uid("transition", f'{WORKFLOW["code"]}:{t["from_code"]}:{t["action_code"]}:{t["to_code"]}')

# ---------------------------------------------------------------- task templates
# seq is the "Sequense number" from Sheet1 where present; mandatory tasks gate stage exit.
def tk(state, seq, title, ttype="task", mandatory=True, role=None, sla=None, desc=""):
    return {"state_code": state, "seq": seq, "title": title, "task_type": ttype,
            "is_mandatory": mandatory, "default_role_code": role, "sla_hours": sla, "description": desc}

TASKS = [
    # Pre-request / Draft
    tk("PRE_DRAFT", 10, "Fill in information in the pre-request", role="ENGINEER"),
    tk("PRE_DRAFT", 20, "Submit pre-request for screening",       role="ENGINEER"),
    # Pre-request / Screening
    tk("PRE_SCREENING", 30, "Decide on go-ahead (accept / reject / return / hold)", ttype="decision", role="ENG_MANAGER"),
    # ECR / Implementation preparation
    tk("ECR_PREP", 10, "ECR created and ECR number shared with requestor", role="ECM_ADMIN"),
    tk("ECR_PREP", 20, "Analyse impact & prepare solution", role="ENGINEER"),
    tk("ECR_PREP", 30, "Review solution", ttype="review", role="ENG_MANAGER"),
    # ECR / CR-board
    tk("ECR_CRB", 10, "CRB meeting", ttype="meeting", role="CR_BOARD"),
    tk("ECR_CRB", 20, "Decide on go-ahead", ttype="decision", role="CR_BOARD"),
    # ECR / Preliminary accepted
    tk("ECR_PRELIM", 10, "Discussion with customer", role="ENG_MANAGER"),
    tk("ECR_PRELIM", 20, "Customer decision", ttype="decision", role="ENG_MANAGER"),
    # ECO / Task list
    tk("ECO_TASKLIST", 10, "Create ECO & inform stakeholders", role="ECM_ADMIN"),
    tk("ECO_TASKLIST", 20, "Create implementation task list", role="ENGINEER"),
    # ECO / Review task list
    tk("ECO_REVIEW_TASKS", 10, "Review / evaluate implementation task list", ttype="review", role="ENG_MANAGER"),
    # ECO / Implementation
    tk("ECO_IMPL", 10, "Execute implementation plan", role="ENGINEER"),
    tk("ECO_IMPL", 20, "Create new item number", role="ENGINEER"),
    tk("ECO_IMPL", 30, "Create / update BOM", role="ENGINEER"),
    tk("ECO_IMPL", 40, "Create / update documents", role="ENGINEER"),
    tk("ECO_IMPL", 50, "Release BOM to site", role="PLANNING"),
    tk("ECO_IMPL", 60, "Prepare components for purchase", role="PURCHASING"),
    tk("ECO_IMPL", 70, "Define PPAP", role="QUALITY"),
    # ECO / Implementation review
    tk("ECO_IMPL_REVIEW", 10, "Review implementation (accept / rework)", ttype="review", role="ENG_MANAGER"),
    # ECO / Released for scheduling
    tk("ECO_REL_SCHED", 10, "Local schedule", role="PLANNING"),
    tk("ECO_REL_SCHED", 20, "Agreement with customer", mandatory=False, role="ENG_MANAGER"),
    # ECO / Released for production
    tk("ECO_REL_PROD", 10, "Update ECO", role="ECM_ADMIN"),
    tk("ECO_REL_PROD", 20, "Update component data", role="ENGINEER"),
    tk("ECO_REL_PROD", 30, "Follow up on PPAP", role="QUALITY"),
    tk("ECO_REL_PROD", 40, "Inform customer", mandatory=False, role="ENG_MANAGER"),
    tk("ECO_REL_PROD", 50, "Plan orders", role="PLANNING"),
    tk("ECO_REL_PROD", 60, "Update production documents (projects & serial)", role="PRODUCTION"),
    tk("ECO_REL_PROD", 70, "Clear up stock", role="WAREHOUSE"),
    tk("ECO_REL_PROD", 80, "Follow up on quality", role="QUALITY"),
    # ECO / Final review
    tk("ECO_FINAL_REVIEW", 10, "Review / evaluate implementation", ttype="review", role="ENG_MANAGER"),
]
for t in TASKS:
    t["stage_code"] = STATE_STAGE[t["state_code"]]
    t["id"] = uid("tasktpl", f'{WORKFLOW["code"]}:{t["state_code"]}:{t["seq"]}')

CONFIG = {"workflow": WORKFLOW, "stages": STAGES, "states": STATES,
          "transitions": TRANSITIONS, "task_templates": TASKS}

with open("workflow/ecm-flow.json", "w") as f:
    json.dump(CONFIG, f, indent=2)

# integrity checks -------------------------------------------------
codes = {s["code"] for s in STATES}
for t in TRANSITIONS:
    assert t["from_code"] in codes, f"bad from {t['from_code']}"
    assert t["to_code"] in codes, f"bad to {t['to_code']}"
for t in TASKS:
    assert t["state_code"] in codes, f"bad task state {t['state_code']}"
initials = {s["stage_code"] for s in STATES if s["is_initial"]}
print(f"stages={len(STAGES)} states={len(STATES)} transitions={len(TRANSITIONS)} tasks={len(TASKS)}")
print("stages with initial state:", sorted(initials))
print("JSON written -> workflow/ecm-flow.json")
