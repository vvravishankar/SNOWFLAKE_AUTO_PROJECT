---
name: deploy
description: "Deploy the AutoPulse AI project end-to-end. Interactive checklist that runs each SQL script in order, validates results, and tracks progress. Use when: deploy project, run deployment, deploy autopulse, deploy demo, dry run, test deployment. Triggers: deploy, deployment, dry run, deploy project."
---

# AutoPulse AI — Fast Phased Deployment

Deploy the full project in 6 phases using `EXECUTE IMMEDIATE FROM @stage` for speed.
Each phase is a single SQL file uploaded to a deploy stage and executed as one batch.

**IMPORTANT:** `02_Git/` is CLI-only and is NEVER run during this deployment.

## Architecture

```
Phase 1 — Pre-Deployment Validation     (~5 sec)
Phase 2 — Environment Preparation       (~15 sec)
Phase 3 — Deployment Execution           (~30 sec)
  3a. DQ Stored Procedure (separate — large $$-delimited file)
  3b. Main deploy script (RAW + CLEAN + DQ + OPS)
  3c. DQ Rules CSV load
  3d. Curated Dynamic Tables
  3e. Semantic Views (3 YAML → SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML)
  3f. Cortex Agents (6 agents)
Phase 4 — Post-Deployment Verification   (~5 sec)
Phase 5 — Release Confirmation           (display only)
Phase 6 — Monitoring & Rollback          (on demand)
```

## Workflow

### Phase 1: Pre-Deployment Validation

Ask the user:
> Starting AutoPulse AI deployment. **Clean slate** (teardown first) or **incremental**?

If clean slate, upload and execute `00_deploy/05_teardown.sql` via the deploy stage.

### Phase 2: Environment Preparation

1. Create a permanent deploy stage:
```sql
USE ROLE ACCOUNTADMIN;
CREATE WAREHOUSE IF NOT EXISTS AUTOPULSE_WH WITH WAREHOUSE_SIZE='X-SMALL' AUTO_SUSPEND=300 AUTO_RESUME=TRUE INITIALLY_SUSPENDED=TRUE;
USE WAREHOUSE AUTOPULSE_WH;
CREATE DATABASE IF NOT EXISTS AUTOPULSE_AI;
CREATE STAGE IF NOT EXISTS AUTOPULSE_AI.DQ.DEPLOY_STAGE;
```

Wait — the DQ schema may not exist yet. Use a temporary approach:
```sql
CREATE SCHEMA IF NOT EXISTS AUTOPULSE_AI.DQ;
CREATE STAGE IF NOT EXISTS AUTOPULSE_AI.DQ.DEPLOY_STAGE;
```

2. Upload all phase scripts to the deploy stage using `snow stage copy`:
```bash
for f in 02_environment.sql 03_deploy.sql 04_post_verify.sql 05_teardown.sql; do
  cp /workspace/hackathon_dl/00_deploy/$f /tmp/$f
  snow stage copy /tmp/$f @AUTOPULSE_AI.DQ.DEPLOY_STAGE/ --overwrite
done
```

Also upload:
- `hackathon_dl/05_dq_framework/RUN_DQ_FW.sql` (the large JS stored procedure)
- `hackathon_dl/05_dq_framework/DQ_Rules.CSV`
- `hackathon_dl/06_curated_layer/Curated_Infra.sql`
- `hackathon_dl/09_agents/AUTOPULSE_AGENTS_DEPLOY.sql`
- Build and upload the 3 semantic view wrapper scripts (SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML calls)

3. Execute environment setup:
```sql
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/02_environment.sql;
```

**STOP**: Report: WH, DB, 5 schemas, 5 roles, 3 users. Ask to continue.

### Phase 3: Deployment Execution

Execute in this order (each is 1 EXECUTE IMMEDIATE call):

```sql
-- 3a. DQ Stored Procedure
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/RUN_DQ_FW.sql;

-- 3b. Main deploy (RAW + CLEAN + DQ streams/tasks + OPS)
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/03_deploy.sql;

-- 3c. Load DQ Rules
COPY INTO AUTOPULSE_AI.DQ.DQ_RULES (RULE_ID, RULE_NAME, SOURCE_TABLE, RULE_TYPE, IS_ACTIVE, SOURCE_COLUMN, RULE_SQL)
FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/DQ_Rules.CSV
FILE_FORMAT = (TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='"')
ON_ERROR='CONTINUE';

-- 3d. Curated Dynamic Tables (includes VEHICLE_QUALITY_SCORECARD)
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/Curated_Infra.sql;

-- 3e. Semantic Views (3 calls)
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/create_sv_battery_intelligence.sql;
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/create_sv_dq_intelligence.sql;
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/create_sv_ops_intelligence.sql;

-- 3f. Cortex Agents (6 agents)
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/AUTOPULSE_AGENTS_DEPLOY.sql;
```

Note: The agents script starts with `USE ROLE ACCOUNTADMIN` for grants, then switches to `AUTOPULSE_AI_ENGINEER` for CREATE AGENT. If the GRANT USAGE ON SEMANTIC VIEW fails (syntax changed), skip it — the SELECT grants from Phase 2 are sufficient.

**STOP**: Report counts. Ask to continue.

### Phase 4: Post-Deployment Verification

```sql
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/04_post_verify.sql;
```

Expected totals:
- RAW: 11 tables, 11 pipes, 1 stage, 1 file format
- CLEAN: 11 tables
- DQ: 3 tables, 11 streams, 11 tasks (started), 148 rules, 1 UDF, 1 procedure
- CURATED: 5 dynamic tables (360, Events, RCA, Prediction, Quality Scorecard)
- OPS: 7 tables, 1 task
- Semantic Views: 3
- Agents: 6
- Roles: 5, Users: 3

### Phase 5: Release Confirmation

Print the final checklist:

```
AUTOPULSE AI DEPLOYMENT — RELEASE CONFIRMED
=============================================
[x] Phase 1: Pre-Deployment Validation
[x] Phase 2: Environment (WH, DB, schemas, RBAC, users)
[x] Phase 3: Deployment
    [x] RAW layer (11 tables, 11 pipes)
    [x] CLEAN layer (11 tables)
    [x] DQ framework (UDF, procedure, 148 rules, 11 streams, 11 tasks)
    [x] Curated layer (5 dynamic tables incl. Quality Scorecard)
    [x] OPS layer (7 tables)
    [x] Semantic Views (3)
    [x] Cortex Agents (6)
[x] Phase 4: Verification passed

NEXT STEPS:
1. Upload CSV data → @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE
2. Wait ~5 min for pipeline flow
3. Launch the Streamlit dashboard
```

Clean up the deploy stage:
```sql
DROP STAGE IF EXISTS AUTOPULSE_AI.DQ.DEPLOY_STAGE;
```

### Phase 6: Monitoring & Rollback Readiness

On demand — if user asks to tear down:
```sql
USE ROLE ACCOUNTADMIN;
-- Upload and execute teardown
EXECUTE IMMEDIATE FROM @AUTOPULSE_AI.DQ.DEPLOY_STAGE/05_teardown.sql;
```

Or run the teardown SQL directly from `hackathon_dl/00_deploy/05_teardown.sql`.

## File Map

| Phase | File | Purpose |
|---|---|---|
| 1 | `00_deploy/01_pre_validation.sql` | Check existing state |
| 2 | `00_deploy/02_environment.sql` | WH, DB, schemas, RBAC, users |
| 3 | `00_deploy/03_deploy.sql` | RAW + CLEAN + DQ + OPS objects |
| 3 | `05_dq_framework/RUN_DQ_FW.sql` | DQ stored procedure |
| 3 | `05_dq_framework/DQ_Rules.CSV` | DQ rules data |
| 3 | `06_curated_layer/Curated_Infra.sql` | 5 Dynamic Tables |
| 3 | `08_semantic_views/*.sv.yaml` | 3 Semantic Views (wrapped) |
| 3 | `09_agents/AUTOPULSE_AGENTS_DEPLOY.sql` | 6 Cortex Agents |
| 4 | `00_deploy/04_post_verify.sql` | Object counts + status |
| 6 | `00_deploy/05_teardown.sql` | Full teardown |

## Stopping Points

- STOP after Phase 1 (clean slate confirmation)
- STOP after Phase 2 (environment ready)
- STOP after Phase 3 (deployment complete, show counts)
- STOP after Phase 4 (verification results)
