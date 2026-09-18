# AutoPulse AI — Deployment Prompt

Copy the prompt below into a new CoCo session to deploy the project end-to-end.

---

```
Can you execute my project AutoPulse_AI from the Workspace in order?

## Rules

1. Skip 02_Git — that is CLI-only, never run it here.
2. Run each step fully (all commands in the script), then STOP.
3. After each step, show me:
   - A validation result (row counts, object counts, pass/fail)
   - The time taken for that step
   - The updated checklist with [x] for done, [ ] for pending
4. Ask my permission before moving to the next step.
5. Do NOT ask permission between individual commands within a step.
6. Use the designated USE ROLE at the top of each script.
7. All compute must run on AUTOPULSE_WH only.

## Pre-Approved SQL Commands (do NOT ask permission for these)

The following SQL command types are pre-approved for this deployment session.
Execute them directly without asking for confirmation:

- USE ROLE, USE WAREHOUSE, USE DATABASE, USE SCHEMA
- CREATE (WAREHOUSE, DATABASE, SCHEMA, TABLE, VIEW, STAGE, FILE FORMAT,
  PIPE, STREAM, TASK, FUNCTION, PROCEDURE, AGENT, SEMANTIC VIEW,
  DYNAMIC TABLE, ROLE, USER)
- CREATE OR REPLACE (all object types listed above)
- ALTER (WAREHOUSE, USER, TASK, DYNAMIC TABLE, GIT REPOSITORY)
- DROP TABLE IF EXISTS, DROP STAGE IF EXISTS
- GRANT, REVOKE
- INSERT INTO, COPY INTO
- CALL (stored procedures, SYSTEM$ functions)
- SET (session variables)
- SHOW, DESCRIBE, LIST, SELECT (validation queries)

## Pre-Approved Bash Commands (do NOT ask permission for these)

The following bash/CLI commands are pre-approved for this deployment session.
Execute them directly without asking for confirmation:

- cat     (read workspace files, e.g. YAML content)
- cp      (copy workspace files to /tmp for staging)
- python3 (run deployment scripts, e.g. semantic view deployer)
- snow stage copy (upload to or download from Snowflake internal stages)
- snow sql -q / -f (execute SQL via CLI)

## Release Notes

After Step 13 (final verification), generate a release note file:

1. Check for existing Release_*.txt files in autopulse_AI/ to determine version:
   - No existing file → v1.0.0
   - Existing v1.0.0 → v1.0.1 (increment patch)
   - Existing v1.0.x → v1.0.(x+1)
2. File name: autopulse_AI/Release_<YYYYMMDD_HHMMSS>.txt
   where the timestamp is the deployment completion time.
3. The release note must contain:
   - Deployment version and timestamp
   - Account, user, role, warehouse
   - Each step with: step number, name, status (PASS/FAIL/SKIP), time taken, object counts
   - Total deployment time
   - Full object summary with counts
   - Demo timing table (production vs demo values)
   - Data flow diagram
   - Project folder structure
   - Known issues or warnings (if any)
   - Next steps (upload data, wait for pipeline, check dashboard)
   - Teardown instructions (reference autopulse_AI/TEARDOWN.sql)

## Deployment Order

Step 1:  autopulse_AI/01_warehouse_and_rbac/User_Role.sql     → WH, DB, schemas, roles, users
Step 2:  SKIP (02_Git is CLI-only)
Step 3:  autopulse_AI/03_raw_layer/Raw_Infra.sql              → file format, stage, 11 RAW tables, 11 pipes
Step 4:  autopulse_AI/04_clean_layer/Clean_Infra.sql          → 11 CLEAN tables
Step 5:  autopulse_AI/05_dq_framework/NORMALIZE_EVENT_DATE.sql → UDF
Step 6:  autopulse_AI/05_dq_framework/RUN_DQ_FW.sql           → DQ stored procedure
Step 7:  Load DQ_Rules.CSV → into AUTOPULSE_AI.DQ.DQ_RULES
         Procedure:
         a. cp /workspace/autopulse_AI/05_dq_framework/DQ_Rules.CSV /tmp/DQ_Rules.CSV
         b. CREATE STAGE IF NOT EXISTS AUTOPULSE_AI.DQ.DQ_TEMP_STAGE
              FILE_FORMAT = (TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='"'
                             FIELD_DELIMITER=',' EMPTY_FIELD_AS_NULL=TRUE);
         c. snow stage copy /tmp/DQ_Rules.CSV @AUTOPULSE_AI.DQ.DQ_TEMP_STAGE/ --overwrite --role SYSADMIN --warehouse AUTOPULSE_WH
         d. COPY INTO AUTOPULSE_AI.DQ.DQ_RULES
            FROM @AUTOPULSE_AI.DQ.DQ_TEMP_STAGE/DQ_Rules.CSV
            FILE_FORMAT = (TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='"'
                           FIELD_DELIMITER=',' EMPTY_FIELD_AS_NULL=TRUE)
            MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
            ON_ERROR='CONTINUE';
            -- MATCH_BY_COLUMN_NAME maps CSV headers to table columns by name
            -- and auto-casts 'TRUE'/'FALSE' strings to BOOLEAN for IS_ACTIVE.
            -- No post-load IS_ACTIVE repair is needed.
         e. DROP STAGE IF EXISTS AUTOPULSE_AI.DQ.DQ_TEMP_STAGE
Step 8:  autopulse_AI/05_dq_framework/DQ_Infra.sql            → DQ tables, 11 streams, 11 tasks
Step 9:  autopulse_AI/06_curated_layer/Curated_Infra.sql      → 5 dynamic tables
Step 10: autopulse_AI/07_ops_layer/Streamlit_cost.sql          → 6 OPS cost tables, proc, task
Step 11: Deploy 3 semantic views from YAML files
         Procedure:
         a. python3 /workspace/autopulse_AI/08_semantic_views/deploy_semantic_views.py
            -- This script handles everything:
            --   reads each .sv.yaml from 08_semantic_views/
            --   escapes single quotes for SQL embedding
            --   calls SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('AUTOPULSE_AI.CURATED', yaml)
            --   via `snow sql`
            --   reports PASS/FAIL for each view
            -- No manual cp, snow stage copy, or quote-escaping needed.
         b. SHOW SEMANTIC VIEWS IN SCHEMA AUTOPULSE_AI.CURATED;  -- verify 3 created
Step 12: autopulse_AI/09_agents/AUTOPULSE_AGENTS_DEPLOY.sql   → 6 Cortex agents (Battery, DQ, RCA, Predictive, OPS, Vehicle Quality)
Step 13: Final verification — object counts, then generate Release Notes file
Step 14: Data Pipeline Health Check — after user uploads data, diagnose the full pipeline

## Step 14: Data Pipeline Health Check

After Step 13 is complete, tell the user:
> "Upload your CSV files to @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE now.
>  Type 'data loaded' when done and I'll run the pipeline health check."

When the user confirms data is loaded, run this diagnostic sequence.
Do NOT ask permission for each query — run them all, then present a single report.

### 14a. Stage Files Check
```sql
LIST @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE;
```
Report: file names, sizes, count. Flag if fewer than 11 files.

### 14b. RAW Layer — Did pipes load?
```sql
SELECT TABLE_NAME, ROW_COUNT
FROM AUTOPULSE_AI.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
```
Flag any table with 0 rows — means the pipe pattern didn't match the filename.
For each 0-row table, try a manual COPY INTO to load it, then report.

### 14c. Streams — Is there data waiting?
```sql
SELECT 'BATTERY_COMPONENTS' AS TBL, SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_BATTERY_COMPONENTS_RAW') AS HAS_DATA
UNION ALL SELECT 'BATTERY_SUPPLIER', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_BATTERY_SUPPLIER_RAW')
UNION ALL SELECT 'BATTERY_TYPE', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_BATTERY_TYPE_RAW')
UNION ALL SELECT 'DATE_VALUES_YEAR', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_DATE_VALUES_YEAR_RAW')
UNION ALL SELECT 'DTC_BATTERY_ERROR_CODES', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_DTC_BATTERY_ERROR_CODES_RAW')
UNION ALL SELECT 'PART_BATTERY', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_PART_BATTERY_RAW')
UNION ALL SELECT 'STATES_AND_ABBREVIATIONS', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_STATES_AND_ABBREVIATIONS_RAW')
UNION ALL SELECT 'VEHICLES', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_VEHICLES_RAW')
UNION ALL SELECT 'VEHICLE_EVENTS', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_VEHICLE_EVENTS_RAW')
UNION ALL SELECT 'WEATHER_DATA', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_WEATHER_DATA_RAW')
UNION ALL SELECT 'ZIP_CODE_INFO', SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_ZIP_CODE_INFO_RAW');
```
If HAS_DATA=TRUE, data is waiting for the DQ task. If FALSE and RAW has rows,
the stream was already consumed (task ran or failed and consumed it).

### 14d. Tasks — Are they running or suspended?
```sql
SHOW TASKS IN SCHEMA AUTOPULSE_AI.DQ;
```
Check the `state` column. Flag any task with state = `suspended`.
If `last_suspended_reason` = `SUSPENDED_DUE_TO_ERRORS`, the task hit 10
consecutive failures and auto-suspended. This is the most common blocker.

**Auto-fix for suspended tasks:**
1. Check object ownership: streams, DQ tables, OPS tables must be owned by
   the same role that owns the RUN_DQ_FW procedure (check with SHOW PROCEDURES).
2. If ownership mismatch, transfer ownership:
   ```sql
   GRANT OWNERSHIP ON ALL STREAMS IN SCHEMA AUTOPULSE_AI.DQ TO ROLE <proc_owner> COPY CURRENT GRANTS;
   GRANT OWNERSHIP ON ALL TABLES IN SCHEMA AUTOPULSE_AI.DQ TO ROLE <proc_owner> COPY CURRENT GRANTS;
   GRANT OWNERSHIP ON ALL TABLES IN SCHEMA AUTOPULSE_AI.OPS TO ROLE <proc_owner> COPY CURRENT GRANTS;
   ```
3. Test manually: `CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('<table_name>');`
4. If manual call succeeds, resume all suspended tasks:
   ```sql
   ALTER TASK AUTOPULSE_AI.DQ.<task_name> RESUME;
   ```
5. If streams are empty (consumed by failed runs), do direct INSERT from RAW to CLEAN:
   ```sql
   INSERT INTO AUTOPULSE_AI.CLEAN.<table>_CLEAN SELECT ... FROM AUTOPULSE_AI.RAW.<table>_RAW;
   ```

### 14e. CLEAN Layer — Did DQ load it?
```sql
SELECT TABLE_NAME, ROW_COUNT
FROM AUTOPULSE_AI.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CLEAN' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
```
Flag any table with 0 rows. Cross-reference with RAW — if RAW has rows
but CLEAN doesn't, the DQ task failed or hasn't run yet.

### 14f. CURATED Layer — Did dynamic tables refresh?
```sql
SHOW DYNAMIC TABLES IN SCHEMA AUTOPULSE_AI.CURATED;
```
Check `scheduling_state` (should be ACTIVE) and `rows` (should be > 0).
If rows = 0 but CLEAN has data, force a manual refresh:
```sql
ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_360 REFRESH;
ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_EVENT_CONTEXT REFRESH;
ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_RCA REFRESH;
ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_PREDICTION REFRESH;
ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_QUALITY_SCORECARD REFRESH;
```

### 14g. Present the Pipeline Health Report

Show a single table like this:
```
PIPELINE HEALTH CHECK
================================================================
Layer     | Object                    | Rows    | Status
----------|---------------------------|---------|-------------------
STAGE     | @AUTOPULSE_RAW_STAGE      | 11 files| OK
RAW       | BATTERY_COMPONENTS_RAW    | 5       | OK
RAW       | VEHICLES_RAW              | 10000   | OK
RAW       | VEHICLE_EVENTS_RAW        | 302883  | OK
  ...     | ...                       | ...     | ...
STREAM    | STREAM_VEHICLES_RAW       | FALSE   | OK (consumed)
  ...     | ...                       | ...     | ...
TASK      | TASK_DQ_VEHICLES          | started | OK
TASK      | TASK_DQ_VEHICLE_EVENTS    | suspended| FIXED → resumed
  ...     | ...                       | ...     | ...
CLEAN     | VEHICLES_CLEAN            | 10000   | OK
CLEAN     | VEHICLE_EVENTS_CLEAN      | 302883  | OK
  ...     | ...                       | ...     | ...
CURATED   | VEHICLE_BATTERY_360       | 10000   | OK
CURATED   | VEHICLE_EVENT_CONTEXT     | 302883  | OK
CURATED   | VEHICLE_BATTERY_RCA       | 5276    | OK
CURATED   | VEHICLE_BATTERY_PREDICTION| 5276    | OK
CURATED   | VEHICLE_QUALITY_SCORECARD | 5276    | OK
================================================================
Pipeline: HEALTHY / BLOCKED AT <layer> / FIXED
================================================================
```

If all CURATED tables have rows > 0, report: "Pipeline HEALTHY — dashboard ready."
If any fixes were applied, list them in the report.

## Teardown

For full teardown, run autopulse_AI/TEARDOWN.sql which drops:
  database, warehouse, API integration, 5 roles, 3 users.

Start with Step 1 now. Record the start time.
```
