#!/usr/bin/env python3
"""
Static validator for the HydraSpecma ECM schema + seed.
No live DB required. Checks (hard):
  1. Global dollar-quote ($tag$) balance
  2. Per-statement parenthesis balance (strings/comments/dollar-bodies stripped)
  3. Foreign-key REFERENCES targets exist (as created tables or auth.users)
  4. Seed INSERT column lists all exist on their target tables (schema/seed drift)
  5. Workflow required_permissions and default_role_codes exist in the RBAC seed
Soft: sqlglot parse of INSERT statements (reported, non-fatal).
"""
import re, sys, json

SCHEMA = open("sql/00_schema_full.sql").read()
SEED   = open("sql/01_seed_full.sql").read()
FLOW   = json.load(open("workflow/ecm-flow.json"))
errors, warns = [], []

# ---------- dollar-quote-aware tokenizer -------------------------------------
def split_statements(sql):
    stmts, buf, i, n = [], [], 0, len(sql)
    state = 'normal'; dollar_tag = None
    while i < n:
        c = sql[i]
        if state == 'normal':
            if sql.startswith('--', i):
                j = sql.find('\n', i); i = n if j < 0 else j; continue
            if sql.startswith('/*', i):
                j = sql.find('*/', i); i = n if j < 0 else j+2; continue
            if c == "'":
                state = 'squote'; buf.append(c); i += 1; continue
            m = re.match(r'\$[A-Za-z0-9_]*\$', sql[i:])
            if m:
                dollar_tag = m.group(0); state = 'dollar'; buf.append(dollar_tag); i += len(dollar_tag); continue
            if c == ';':
                s = ''.join(buf).strip()
                if s: stmts.append(s)
                buf = []; i += 1; continue
            buf.append(c); i += 1
        elif state == 'squote':
            if c == "'":
                if i+1 < n and sql[i+1] == "'": buf.append("''"); i += 2; continue
                state = 'normal'; buf.append(c); i += 1; continue
            buf.append(c); i += 1
        elif state == 'dollar':
            if sql.startswith(dollar_tag, i):
                buf.append(dollar_tag); i += len(dollar_tag); state = 'normal'; dollar_tag = None; continue
            buf.append(c); i += 1
    if ''.join(buf).strip(): stmts.append(''.join(buf).strip())
    return stmts

def strip_noncode(stmt):
    """Remove comments, single-quoted strings and dollar-quoted bodies for structural checks."""
    out, i, n = [], 0, len(stmt); state='normal'; tag=None
    while i < n:
        c = stmt[i]
        if state=='normal':
            if stmt.startswith('--', i): j=stmt.find('\n',i); i=n if j<0 else j; continue
            if c=="'": state='squote'; i+=1; continue
            m=re.match(r'\$[A-Za-z0-9_]*\$', stmt[i:])
            if m: tag=m.group(0); state='dollar'; i+=len(tag); continue
            out.append(c); i+=1
        elif state=='squote':
            if c=="'":
                if i+1<n and stmt[i+1]=="'": i+=2; continue
                state='normal'; i+=1; continue
            i+=1
        else:
            if stmt.startswith(tag,i): i+=len(tag); state='normal'; tag=None; continue
            i+=1
    return ''.join(out)

# ---------- 1. global dollar balance -----------------------------------------
tags = re.findall(r'\$[A-Za-z0-9_]*\$', SCHEMA)
from collections import Counter
cnt = Counter(tags)
for t,k in cnt.items():
    if k % 2 != 0: errors.append(f"Unbalanced dollar-quote {t}: {k} occurrences")

schema_stmts = split_statements(SCHEMA)
seed_stmts   = split_statements(SEED)
print(f"Parsed statements: schema={len(schema_stmts)} seed={len(seed_stmts)}")

# ---------- 2. paren balance per statement -----------------------------------
for label, stmts in [("schema", schema_stmts), ("seed", seed_stmts)]:
    for s in stmts:
        code = strip_noncode(s)
        if code.count('(') != code.count(')'):
            errors.append(f"[{label}] paren imbalance in: {s[:70].replace(chr(10),' ')}...")

# ---------- parse created tables + columns -----------------------------------
tables = {}           # name -> set(columns)
created_types = set()
def parse_columns(body):
    cols=set(); depth=0; cur=''
    parts=[]
    for ch in body:
        if ch=='(' : depth+=1; cur+=ch
        elif ch==')': depth-=1; cur+=ch
        elif ch==',' and depth==0: parts.append(cur); cur=''
        else: cur+=ch
    if cur.strip(): parts.append(cur)
    kw=('primary','foreign','unique','check','constraint','exclude','like')
    for p in parts:
        p=p.strip()
        if not p: continue
        first=p.split()[0].strip('"').lower()
        if first in kw: continue
        cols.add(first)
    return cols

for s in schema_stmts:
    code=strip_noncode(s)
    m=re.match(r'CREATE TABLE(?:\s+IF NOT EXISTS)?\s+"?([A-Za-z_][\w]*)"?\s*\((.*)\)\s*$', code, re.S|re.I)
    if m:
        name=m.group(1).lower()
        # cut off trailing table options after last ')'
        body=m.group(2)
        tables[name]=parse_columns(body)
    mt=re.match(r'CREATE TYPE\s+"?([A-Za-z_][\w]*)"?', code, re.I)
    if mt: created_types.add(mt.group(1).lower())

print(f"Tables parsed: {len(tables)}  Types parsed: {len(created_types)}")

# ---------- 3. FK targets exist ----------------------------------------------
external_ok={'auth.users','storage.buckets','storage.objects'}
for s in schema_stmts:
    code=strip_noncode(s)
    for ref in re.finditer(r'REFERENCES\s+((?:auth\.|storage\.)?"?[A-Za-z_][\w]*)"?\s*\(', code, re.I):
        tgt=ref.group(1).lower().replace('"','')
        if tgt in external_ok: continue
        if tgt not in tables:
            errors.append(f"FK references unknown table '{tgt}' in: {code[:60]}...")

# ---------- 4. seed INSERT columns exist -------------------------------------
for s in seed_stmts:
    code=strip_noncode(s)
    m=re.match(r'INSERT INTO\s+"?([A-Za-z_][\w]*)"?\s*\(([^)]*)\)', code, re.I|re.S)
    if not m: continue
    tbl=m.group(1).lower(); collist=[c.strip().strip('"').lower() for c in m.group(2).split(',') if c.strip()]
    if tbl not in tables:
        errors.append(f"Seed INSERT into unknown table '{tbl}'"); continue
    for c in collist:
        if c not in tables[tbl]:
            errors.append(f"Seed INSERT column '{c}' not found on table '{tbl}'")

# ---------- 5. workflow perms / roles exist in RBAC seed ---------------------
perm_codes=set(re.findall(r"\('([a-z_]+\.[a-z_]+)'", SEED))       # e.g. 'ecm.read'
role_codes=set(re.findall(r"\('([A-Z_]{3,})','", SEED))            # e.g. 'ENG_MANAGER'
req_perms={t['required_permission'] for t in FLOW['transitions'] if t.get('required_permission')}
req_roles={t['default_role_code'] for t in FLOW['task_templates'] if t.get('default_role_code')}
for p in sorted(req_perms):
    if p not in perm_codes: errors.append(f"Workflow requires permission '{p}' missing from RBAC seed")
for r in sorted(req_roles):
    if r not in role_codes: errors.append(f"Workflow references role '{r}' missing from RBAC seed")
print(f"Workflow perms referenced: {len(req_perms)} (all seeded: {req_perms<=perm_codes})")
print(f"Workflow roles referenced: {len(req_roles)} (all seeded: {req_roles<=role_codes})")

# ---------- soft: sqlglot parse of INSERTs -----------------------------------
try:
    import sqlglot
    ok=bad=0
    for s in seed_stmts:
        if re.match(r'\s*INSERT INTO', s, re.I):
            try: sqlglot.parse_one(s, dialect='postgres'); ok+=1
            except Exception as e: bad+=1; warns.append(f"sqlglot INSERT parse: {str(e)[:80]}")
    print(f"sqlglot INSERT parse: ok={ok} bad={bad}")
except Exception as e:
    warns.append(f"sqlglot unavailable: {e}")

# ---------- report -----------------------------------------------------------
print("\n=== WARNINGS ==="); [print(" -", w) for w in warns[:15]] or print(" none")
print("\n=== ERRORS ===")
if errors:
    for e in errors[:60]: print(" -", e)
    print(f"\nRESULT: FAIL ({len(errors)} errors)"); sys.exit(1)
else:
    print(" none")
    print("\nRESULT: PASS — schema + seed are structurally consistent."); sys.exit(0)
