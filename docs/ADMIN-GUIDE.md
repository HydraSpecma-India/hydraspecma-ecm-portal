# Administrator Operations Guide — HydraSpecma ECM Portal

This guide provides operational documentation for managers and system administrators maintaining the HydraSpecma Engineering Change Management (ECM) Portal.

---

## 1. User Role Administration (RBAC)

The portal uses Role-Based Access Control (RBAC) to restrict access to sensitive parameters and approval gates.
- **Roles list**:
  - `SUPER_ADMIN`: Access to all settings, user roles, logs, and database bypasses.
  - `ECM_ADMIN`: Manage workflows, approve emergency overrides, and configure templates.
  - `ENGINEER`: Modify change requests, assign tasks, and upload documentation.
  - `VIEWER`: Read-only access to dashboard data.

### To Promote / Edit User Roles:
1. Navigate to the **Admin Control Panel** (`/pages/admin.html`).
2. Go to the **User Roles Management** tab.
3. Find the user from the profile directory.
4. Click **"Edit Roles"**.
5. Check/uncheck role assignments and click **"Save Role Assignments"**.

---

## 2. FDA 21 CFR Part 11 Compliance Auditing

All change logs, transitions, and signature actions are recorded in an immutable ledger:
1. Navigate to the **Audit Trail** page (`/pages/audit-trail.html`).
2. Search by keyword or apply filters (e.g. `ecm_requests`, `INSERT` actions).
3. Click **"View Diff"** on any record to view a side-by-side JSON payload showing precisely what values changed before and after the modification.
4. Use **"Export CSV"** to generate reports for regulatory audits.

---

## 3. SLA Bottleneck Analysis & Reports

To review manufacturing site performance:
1. Navigate to the **Reporting & Analytics Center** (`/pages/reports.html`).
2. The **State Bottlenecks** tab highlights delay status warnings if a state's average dwell time breaches its configured SLA hours limit.
3. Click **"Print Report"** to print or export to PDF formatted cleanly for physical paper outputs.
4. Click **"Export CSV"** to save report tables locally.
