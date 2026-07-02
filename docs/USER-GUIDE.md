# User Guide — HydraSpecma ECM Portal

How to use the portal to raise, review, approve and implement engineering changes. Screens are delivered progressively (Modules 3–19); this guide describes how the system works end to end, grounded in the workflow and data model that already exist.

> Terminology: **ECM** = the master change record · **ECR** = Engineering Change Request · **ECO** = Engineering Change Order · **CRB** = Change Review Board · **BOM** = Bill of Materials · **PPAP** = Production Part Approval Process.

---

## 1. Roles — who can do what

| Role | Typical user | Can do |
|------|--------------|--------|
| **Super Admin** | IT/platform owner | Everything, including platform settings. |
| **ECM Administrator** | Change process owner | Full ECM administration: users, workflow, templates, all records. |
| **Engineering Manager** | Eng lead | Screen pre-requests, run CR-board, approve, manage ECR/ECO, release. |
| **CR Board** | Board members | Vote on CR-board decisions and approvals. |
| **Department Head** | Dept lead | Create/update changes, approve for their area. |
| **Quality / Production / Planning / Purchasing / Warehouse** | Functional teams | Execute their implementation tasks, update records & documents. |
| **Finance** | Controlling | Review cost impact, approve where required. |
| **Engineer** | Design/mfg engineer | Raise pre-requests, prepare solutions, complete tasks, manage documents. |
| **Viewer** | Stakeholders | Read-only access to records and reports. |

Permissions are enforced everywhere by the database (Row-Level Security), so the UI only ever offers actions you are allowed to perform.

---

## 2. Signing in
- **Email & password**, or **Sign in with Microsoft** (Azure AD / M365 single sign-on).
- **Remember me** keeps you signed in on this device; leave it off on shared machines.
- **Forgot password** emails a secure reset link.
Your first sign-in provisions your profile automatically. (The first-ever user becomes Super Admin.)

---

## 3. The dashboard
The executive dashboard shows live KPI cards — Total, Open, Pending Approval, Rejected, Cancelled, Completed, Average Lead Time, Average Approval Time, Implementation Success Rate, Overdue Tasks and Open Actions — plus charts for monthly trends, requests per department, priority distribution, the workflow funnel, approval durations, bottlenecks and workload per user. Everything respects your role and plant scope.

---

## 4. The change lifecycle
```
Pre-request ──► ECR ──► CR-board ──► ECO ──► Implementation ──► Validation ──► Resolved
      │           │                    │
   (screening)  (customer)         (release)
      └────────── Rejected / Cancelled / Hold / Backlog can occur at each stage ──────────┘
```
Movement between states is only possible via defined **transitions**. Each transition checks your permission, may require a comment, and may require an approval. Every move is timestamped in the record's timeline with the time spent in the previous state.

---

## 5. Raise a pre-request
Create a pre-request and fill in: **title, description, reason, affected part number / BOM, customer, supplier, department, plant, priority, risk level** and **estimated cost impact**. Save as **Draft**, then **Submit for screening**. The system assigns the ECM number automatically (e.g. `ECM-2026-00001`) and generates a QR code for the record.

## 6. Screening
An Engineering Manager reviews the pre-request and decides the go-ahead: **Accept**, **Reject** (with reason), **Return** (send back for more information), **Hold**, or move to **Backlog**. Accepting creates the **ECR** (with its own `ECR-YYYY-#####` number) and moves the change into ECR preparation.

## 7. ECR — request & board
In the ECR stage the team **analyses impact and prepares a solution**, then **reviews** it, and takes it to the **CR-board meeting**. The board decides: preliminary-accept, return, hold, backlog, reject or cancel. On preliminary acceptance the change goes to **customer discussion**; the customer decision then accepts (creating the **ECO**), rejects or cancels.

## 8. ECO — implementation
The ECO drives execution:
1. Create the **implementation task list** and have it reviewed.
2. **Execute**: create/updated item numbers and BOMs, create/update documents, release BOM to site, prepare components for purchase, define PPAP.
3. **Implementation review** → accept or rework.
4. **Release for scheduling** (local schedule, customer agreement) → **release for production**.
5. Update ECO/component data, follow up on PPAP and quality, inform customer, plan orders, update production documents, clear stock.
6. **Final review** → **Resolve & close** (or rework).

## 9. Tasks
Each state automatically seeds its checklist of tasks (with the right default owner department). Work them in **Kanban, list, calendar, timeline or Gantt** views. Tasks support **assignees, due dates, progress %, checklists, dependencies** (for Gantt) and **reminders**. Overdue and open tasks roll up to the dashboard and to per-user workload.

## 10. Documents
Attach engineering drawings, CAD files, PDFs, Word/Excel, images, specifications and work instructions. Documents are **version-controlled** with **check-out/check-in**, **revision history**, in-browser **preview**, **download**, approval and **digital signatures** (bound to a specific version). Controlled categories can require approval before release.

## 11. Approvals
Approvals gate the transitions that require them. Approvers act **in-app** or directly from an **email** (Approve / Reject / Return / Comment) via a secure one-time link. Approvals support **delegation**, **escalation** on SLA breach, and policies (**any / all / quorum / sequential**). The full approval history is kept on the record.

## 12. Notifications
A realtime **bell** with an unread counter surfaces assignments, mentions, approvals pending, due-today and overdue items and system alerts. You control delivery per event and channel (in-app / email / Teams) in your notification preferences.

## 13. Search & QR
**Global search** finds records by ECM/ECR/ECO number, part number, customer, supplier, status, priority, department, date or owner. Every ECM/ECR/ECO has a **QR code** — scan it to open the record on any device; QR codes can be printed or downloaded (e.g. onto travelers or drawings).

## 14. AI assistant
The assistant can summarize a change, detect missing information, suggest required documents and approvers, assess risk, recommend priority, estimate lead time, find similar past ECMs, predict delays, suggest engineering tasks, and generate executive summaries and meeting minutes — plus a general chat. It runs server-side so no keys are exposed.

## 15. Reports & exports
Executive, compliance, engineering, department, cycle-time and approval reports are available, with **export to Excel, PDF and CSV** and print. You can also generate compliance, engineering and audit **packages**, and a QR sheet.

## 16. Admin panel (admins only)
Manage users, roles and the **permission matrix**; departments and plants; the **workflow** (statuses, transitions, task templates) — all data-driven, so process changes need no code; email templates, notification and approval rules; document categories; dashboard settings; and view **audit logs** and **API logs**.

---

## Permissions quick reference
- **Raise & edit changes:** Engineer, Department Head, Engineering Manager, ECM/Super Admin.
- **Screen / go-ahead:** Engineering Manager, ECM/Super Admin.
- **CR-board decisions:** CR Board, Engineering Manager.
- **Release for production / close:** Engineering Manager, ECM/Super Admin.
- **Execute implementation tasks:** the assigned functional department.
- **View only:** Viewer (and everyone, for records within their plant scope).

## Audit & compliance
Every field change is recorded (old value, new value, who, when, IP, browser, device) in an immutable audit trail, and every workflow move is captured in the record timeline — supporting compliance reviews and full traceability.
