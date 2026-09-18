-- ============================================================================
-- AUTOPULSE AI | OPS LAYER
-- Cost, Storage, and Streamlit Operations Tables
-- ============================================================================
--
-- Purpose:
--   Populate OPS cost tables from SNOWFLAKE.ACCOUNT_USAGE views.
--   Table names and column names match the AUTOPULSE_OPS_INTELLIGENCE
--   semantic view YAML exactly so no post-deploy column patching is needed.
--
-- Tables created:
--   1. COST_WAREHOUSE          — daily warehouse credit usage
--   2. COST_SERVERLESS         — per-task serverless credit usage
--   3. COST_PIPES              — per-pipe ingestion credit usage
--   4. COST_STORAGE            — daily storage in TB
--   5. COST_STREAMLIT_RUNTIME  — Streamlit container-runtime compute-pool usage
--   6. COST_STREAMLIT_DDL      — Streamlit CREATE/ALTER/DROP activity
--
-- Also creates:
--   - REFRESH_COST_TABLES()    — stored procedure to refresh all 6 tables
--   - OPS_COST_REFRESH_TASK    — serverless task (DEMO: 1 min)
--
-- Execution role:
--   Run as ACCOUNTADMIN (reads from SNOWFLAKE.ACCOUNT_USAGE).
--
-- ============================================================================


-- ============================================================================
-- 0. SESSION CONTEXT
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE AUTOPULSE_WH;
USE DATABASE AUTOPULSE_AI;
USE SCHEMA OPS;


-- ============================================================================
-- 1. COST_WAREHOUSE
-- ============================================================================
-- Columns: WAREHOUSE_NAME, USAGE_DATE, CREDITS_USED, CREDITS_COMPUTE, CREDITS_CLOUD
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_WAREHOUSE AS
SELECT
    WAREHOUSE_NAME,
    START_TIME                          AS USAGE_DATE,
    CREDITS_USED,
    CREDITS_USED_COMPUTE                AS CREDITS_COMPUTE,
    CREDITS_USED_CLOUD_SERVICES         AS CREDITS_CLOUD
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE WAREHOUSE_NAME = 'AUTOPULSE_WH'
  AND START_TIME >= DATEADD(DAY, -30, CURRENT_TIMESTAMP());


-- ============================================================================
-- 2. COST_SERVERLESS
-- ============================================================================
-- Columns: TASK_NAME, TASK_SCHEMA, USAGE_DATE, CREDITS_USED,
--          TASK_AVG_DURATION, TASK_RUN_COUNT
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_SERVERLESS AS
SELECT
    TASK_NAME,
    SCHEMA_NAME                         AS TASK_SCHEMA,
    START_TIME                          AS USAGE_DATE,
    CREDITS_USED,
    COALESCE(
        DATEDIFF('second', START_TIME, END_TIME), 0
    )                                   AS TASK_AVG_DURATION,
    1                                   AS TASK_RUN_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY
WHERE DATABASE_NAME = 'AUTOPULSE_AI'
  AND START_TIME >= DATEADD(DAY, -30, CURRENT_TIMESTAMP());


-- ============================================================================
-- 3. COST_PIPES
-- ============================================================================
-- Columns: PIPE_NAME, USAGE_DATE, BYTES_INSERTED, CREDITS_USED, FILES_INSERTED
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_PIPES AS
SELECT
    PIPE_NAME,
    START_TIME                          AS USAGE_DATE,
    BYTES_INSERTED,
    CREDITS_USED,
    FILES_INSERTED
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
WHERE PIPE_NAME LIKE 'PIPE_%'
  AND START_TIME >= DATEADD(DAY, -30, CURRENT_TIMESTAMP());


-- ============================================================================
-- 4. COST_STORAGE
-- ============================================================================
-- Columns: USAGE_DATE, STORAGE_TB, STAGE_TB, FAILSAFE_TB, TOTAL_TB
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_STORAGE AS
SELECT
    USAGE_DATE,
    ROUND(STORAGE_BYTES   / POWER(1024, 4), 6) AS STORAGE_TB,
    ROUND(STAGE_BYTES     / POWER(1024, 4), 6) AS STAGE_TB,
    ROUND(FAILSAFE_BYTES  / POWER(1024, 4), 6) AS FAILSAFE_TB,
    ROUND(
        (STORAGE_BYTES + STAGE_BYTES + FAILSAFE_BYTES) / POWER(1024, 4), 6
    )                                           AS TOTAL_TB
FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE
WHERE USAGE_DATE >= DATEADD(DAY, -30, CURRENT_DATE());


-- ============================================================================
-- 5. COST_STREAMLIT_RUNTIME
-- ============================================================================
-- Columns: COMPUTE_POOL_NAME, START_TIME, END_TIME, RUNTIME_TYPE,
--          USAGE_DATE, CREDITS_USED
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_STREAMLIT_RUNTIME (
    COMPUTE_POOL_NAME   VARCHAR,
    START_TIME          TIMESTAMP_LTZ,
    END_TIME            TIMESTAMP_LTZ,
    RUNTIME_TYPE        VARCHAR,
    USAGE_DATE          DATE,
    CREDITS_USED        NUMBER(38,9)
)
COMMENT = 'Streamlit container-runtime compute-pool credit usage. Populated after Streamlit app is deployed.';


-- ============================================================================
-- 6. COST_STREAMLIT_DDL
-- ============================================================================
-- Columns: OPERATION, OPERATION_DATE, ROLE_NAME, USER_NAME,
--          WAREHOUSE_NAME, OPERATION_COUNT
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_STREAMLIT_DDL (
    OPERATION       VARCHAR,
    OPERATION_DATE  DATE,
    ROLE_NAME       VARCHAR,
    USER_NAME       VARCHAR,
    WAREHOUSE_NAME  VARCHAR,
    OPERATION_COUNT NUMBER(38,0)
)
COMMENT = 'Streamlit CREATE/ALTER/DROP activity from QUERY_HISTORY.';


-- ============================================================================
-- 7. REFRESH PROCEDURE
-- ============================================================================

CREATE OR REPLACE PROCEDURE AUTOPULSE_AI.OPS.REFRESH_COST_TABLES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_WAREHOUSE AS
    SELECT
        WAREHOUSE_NAME,
        START_TIME                      AS USAGE_DATE,
        CREDITS_USED,
        CREDITS_USED_COMPUTE            AS CREDITS_COMPUTE,
        CREDITS_USED_CLOUD_SERVICES     AS CREDITS_CLOUD
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE WAREHOUSE_NAME = 'AUTOPULSE_WH'
      AND START_TIME >= DATEADD(DAY, -30, CURRENT_TIMESTAMP());

    CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_SERVERLESS AS
    SELECT
        TASK_NAME,
        SCHEMA_NAME                     AS TASK_SCHEMA,
        START_TIME                      AS USAGE_DATE,
        CREDITS_USED,
        COALESCE(DATEDIFF('second', START_TIME, END_TIME), 0) AS TASK_AVG_DURATION,
        1                               AS TASK_RUN_COUNT
    FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY
    WHERE DATABASE_NAME = 'AUTOPULSE_AI'
      AND START_TIME >= DATEADD(DAY, -30, CURRENT_TIMESTAMP());

    CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_PIPES AS
    SELECT
        PIPE_NAME,
        START_TIME                      AS USAGE_DATE,
        BYTES_INSERTED,
        CREDITS_USED,
        FILES_INSERTED
    FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
    WHERE PIPE_NAME LIKE 'PIPE_%'
      AND START_TIME >= DATEADD(DAY, -30, CURRENT_TIMESTAMP());

    CREATE OR REPLACE TABLE AUTOPULSE_AI.OPS.COST_STORAGE AS
    SELECT
        USAGE_DATE,
        ROUND(STORAGE_BYTES   / POWER(1024, 4), 6) AS STORAGE_TB,
        ROUND(STAGE_BYTES     / POWER(1024, 4), 6) AS STAGE_TB,
        ROUND(FAILSAFE_BYTES  / POWER(1024, 4), 6) AS FAILSAFE_TB,
        ROUND((STORAGE_BYTES + STAGE_BYTES + FAILSAFE_BYTES) / POWER(1024, 4), 6) AS TOTAL_TB
    FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE
    WHERE USAGE_DATE >= DATEADD(DAY, -30, CURRENT_DATE());

    RETURN 'OPS cost tables refreshed at ' || CURRENT_TIMESTAMP()::VARCHAR;
END;


-- ============================================================================
-- 8. REFRESH TASK — DEMO: 1 MINUTE
-- ============================================================================
-- For production, change to SCHEDULE = '60 MINUTE'.
-- ============================================================================

CREATE OR REPLACE TASK AUTOPULSE_AI.OPS.OPS_COST_REFRESH_TASK
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Refreshes OPS cost tables from ACCOUNT_USAGE (DEMO: 1 min).'
AS
    CALL AUTOPULSE_AI.OPS.REFRESH_COST_TABLES();

ALTER TASK AUTOPULSE_AI.OPS.OPS_COST_REFRESH_TASK RESUME;


-- ============================================================================
-- 9. POST-DEPLOYMENT VERIFICATION
-- ============================================================================

SHOW TABLES IN SCHEMA AUTOPULSE_AI.OPS;
SHOW TASKS IN SCHEMA AUTOPULSE_AI.OPS;
