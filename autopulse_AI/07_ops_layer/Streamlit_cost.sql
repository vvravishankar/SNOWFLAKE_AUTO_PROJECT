-- ============================================================
-- AUTOPULSE OPS COST LAYER
-- HISTORICAL + AUTOMATED TASK REFRESH
-- ============================================================
-- Run once as ACCOUNTADMIN.
--
-- Design:
--   * Keep historical cost data in OPS tables.
--   * Initial INSERT loads the available 365-day history.
--   * A scheduled/child Task performs incremental INSERTs.
--   * The Task is intended to run after your final upstream Task.
--
-- IMPORTANT:
--   CURATED is implemented with Dynamic Tables in this project.
--   A Dynamic Table cannot be used directly as an AFTER predecessor.
--   AFTER accepts predecessor TASKS.
--
-- Therefore, replace the placeholder:
--   <FINAL_UPSTREAM_TASK>
-- with the name of the final Task that completes your upstream
-- DQ/CLEAN processing.
--
-- If your "final curated load" is a Dynamic Table refresh rather
-- than a Task, use a small scheduled bridge Task as the upstream
-- predecessor instead of putting a Dynamic Table in AFTER.
--
-- The OPS cost data itself comes from SNOWFLAKE.ACCOUNT_USAGE,
-- not from CURATED. CURATED and OPS are parallel reporting layers.
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE AUTOPULSE_WH;

CREATE DATABASE IF NOT EXISTS AUTOPULSE_AI;
CREATE SCHEMA IF NOT EXISTS AUTOPULSE_AI.OPS;

-- ============================================================
-- 1. COST TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.OPS.COST_WAREHOUSE (
    WAREHOUSE_NAME VARCHAR,
    USAGE_DATE TIMESTAMP_LTZ,
    CREDITS_USED NUMBER(38,9),
    CREDITS_COMPUTE NUMBER(38,9),
    CREDITS_CLOUD NUMBER(38,9)
);

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.OPS.COST_SERVERLESS (
    TASK_NAME VARCHAR,
    TASK_SCHEMA VARCHAR,
    USAGE_DATE TIMESTAMP_LTZ,
    CREDITS_USED NUMBER(38,9),
    TASK_RUN_COUNT NUMBER(38,0),
    TASK_AVG_DURATION NUMBER(38,2)
);

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.OPS.COST_PIPES (
    PIPE_NAME VARCHAR,
    USAGE_DATE TIMESTAMP_LTZ,
    CREDITS_USED NUMBER(38,9),
    BYTES_INSERTED FLOAT,
    FILES_INSERTED FLOAT
);

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.OPS.COST_STORAGE (
    USAGE_DATE DATE,
    STORAGE_TB NUMBER(38,4),
    STAGE_TB NUMBER(38,4),
    FAILSAFE_TB NUMBER(38,4),
    TOTAL_TB NUMBER(38,4)
);

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.OPS.COST_STREAMLIT_RUNTIME (
    USAGE_DATE DATE,
    START_TIME TIMESTAMP_LTZ,
    END_TIME TIMESTAMP_LTZ,
    COMPUTE_POOL_NAME VARCHAR,
    RUNTIME_TYPE VARCHAR,
    CREDITS_USED NUMBER(38,9)
);

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.OPS.COST_STREAMLIT_DDL (
    OPERATION_DATE DATE,
    OPERATION VARCHAR,
    USER_NAME VARCHAR,
    ROLE_NAME VARCHAR,
    WAREHOUSE_NAME VARCHAR,
    OPERATION_COUNT NUMBER(38,0)
);

-- ============================================================
-- 2. INITIAL HISTORICAL LOAD
-- ============================================================
-- Run once. Each INSERT has NOT EXISTS protection so the script
-- can safely be rerun without creating duplicate history.

-- 2A. Warehouse
INSERT INTO AUTOPULSE_AI.OPS.COST_WAREHOUSE
(
    WAREHOUSE_NAME,
    USAGE_DATE,
    CREDITS_USED,
    CREDITS_COMPUTE,
    CREDITS_CLOUD
)
SELECT
    WAREHOUSE_NAME,
    START_TIME,
    CREDITS_USED,
    CREDITS_USED_COMPUTE,
    CREDITS_USED_CLOUD_SERVICES
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY S
WHERE S.WAREHOUSE_NAME = 'AUTOPULSE_WH'
  AND S.START_TIME >= DATEADD(DAY, -365, CURRENT_TIMESTAMP())
  AND NOT EXISTS (
      SELECT 1
      FROM AUTOPULSE_AI.OPS.COST_WAREHOUSE T
      WHERE T.WAREHOUSE_NAME = S.WAREHOUSE_NAME
        AND T.USAGE_DATE = S.START_TIME
  );

-- 2B. Serverless DQ tasks
INSERT INTO AUTOPULSE_AI.OPS.COST_SERVERLESS
(
    TASK_NAME,
    TASK_SCHEMA,
    USAGE_DATE,
    CREDITS_USED,
    TASK_RUN_COUNT,
    TASK_AVG_DURATION
)
SELECT
    TASK_NAME,
    SCHEMA_NAME,
    START_TIME,
    TRY_TO_DECIMAL(CREDITS_USED, 38, 9),
    1,
    DATEDIFF('second', START_TIME, END_TIME)
FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY S
WHERE S.DATABASE_NAME = 'AUTOPULSE_AI'
  AND S.START_TIME >= DATEADD(DAY, -365, CURRENT_TIMESTAMP())
  AND NOT EXISTS (
      SELECT 1
      FROM AUTOPULSE_AI.OPS.COST_SERVERLESS T
      WHERE T.TASK_NAME = S.TASK_NAME
        AND T.TASK_SCHEMA = S.SCHEMA_NAME
        AND T.USAGE_DATE = S.START_TIME
  );

-- 2C. Snowpipes
INSERT INTO AUTOPULSE_AI.OPS.COST_PIPES
(
    PIPE_NAME,
    USAGE_DATE,
    CREDITS_USED,
    BYTES_INSERTED,
    FILES_INSERTED
)
SELECT
    PIPE_NAME,
    START_TIME,
    CREDITS_USED,
    BYTES_INSERTED,
    FILES_INSERTED
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY S
WHERE S.PIPE_NAME ILIKE '%AUTOPULSE%'
  AND S.START_TIME >= DATEADD(DAY, -365, CURRENT_TIMESTAMP())
  AND NOT EXISTS (
      SELECT 1
      FROM AUTOPULSE_AI.OPS.COST_PIPES T
      WHERE T.PIPE_NAME = S.PIPE_NAME
        AND T.USAGE_DATE = S.START_TIME
  );

-- 2D. Storage
INSERT INTO AUTOPULSE_AI.OPS.COST_STORAGE
(
    USAGE_DATE,
    STORAGE_TB,
    STAGE_TB,
    FAILSAFE_TB,
    TOTAL_TB
)
SELECT
    USAGE_DATE,
    ROUND(STORAGE_BYTES / POWER(1024, 4), 4),
    ROUND(STAGE_BYTES / POWER(1024, 4), 4),
    ROUND(FAILSAFE_BYTES / POWER(1024, 4), 4),
    ROUND(
        (
            COALESCE(STORAGE_BYTES, 0)
          + COALESCE(STAGE_BYTES, 0)
          + COALESCE(FAILSAFE_BYTES, 0)
        ) / POWER(1024, 4),
        4
    )
FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE S
WHERE S.USAGE_DATE >= DATEADD(DAY, -365, CURRENT_DATE())
  AND NOT EXISTS (
      SELECT 1
      FROM AUTOPULSE_AI.OPS.COST_STORAGE T
      WHERE T.USAGE_DATE = S.USAGE_DATE
  );

-- 2E. Streamlit / SPCS runtime
INSERT INTO AUTOPULSE_AI.OPS.COST_STREAMLIT_RUNTIME
(
    USAGE_DATE,
    START_TIME,
    END_TIME,
    COMPUTE_POOL_NAME,
    RUNTIME_TYPE,
    CREDITS_USED
)
SELECT
    TO_DATE(START_TIME),
    START_TIME,
    END_TIME,
    COMPUTE_POOL_NAME,
    'STREAMLIT_CONTAINER_RUNTIME',
    CREDITS_USED
FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWPARK_CONTAINER_SERVICES_HISTORY S
WHERE S.COMPUTE_POOL_NAME = 'SYSTEM_COMPUTE_POOL_CPU'
  AND S.START_TIME >= DATEADD(DAY, -365, CURRENT_TIMESTAMP())
  AND NOT EXISTS (
      SELECT 1
      FROM AUTOPULSE_AI.OPS.COST_STREAMLIT_RUNTIME T
      WHERE T.START_TIME = S.START_TIME
        AND T.END_TIME = S.END_TIME
        AND T.COMPUTE_POOL_NAME = S.COMPUTE_POOL_NAME
  );

-- 2F. Streamlit CREATE / ALTER / DROP activity
INSERT INTO AUTOPULSE_AI.OPS.COST_STREAMLIT_DDL
(
    OPERATION_DATE,
    OPERATION,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    OPERATION_COUNT
)
SELECT
    TO_DATE(START_TIME),
    CASE
        WHEN REGEXP_LIKE(
            QUERY_TEXT,
            '^\\s*CREATE\\s+(OR\\s+REPLACE\\s+)?STREAMLIT\\b',
            'i'
        ) THEN 'CREATE STREAMLIT'
        WHEN REGEXP_LIKE(
            QUERY_TEXT,
            '^\\s*ALTER\\s+STREAMLIT\\b',
            'i'
        ) THEN 'ALTER STREAMLIT'
        WHEN REGEXP_LIKE(
            QUERY_TEXT,
            '^\\s*DROP\\s+STREAMLIT\\b',
            'i'
        ) THEN 'DROP STREAMLIT'
    END,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    COUNT(*)
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY S
WHERE S.START_TIME >= DATEADD(DAY, -365, CURRENT_TIMESTAMP())
  AND (
       REGEXP_LIKE(
           QUERY_TEXT,
           '^\\s*CREATE\\s+(OR\\s+REPLACE\\s+)?STREAMLIT\\b',
           'i'
       )
    OR REGEXP_LIKE(
           QUERY_TEXT,
           '^\\s*ALTER\\s+STREAMLIT\\b',
           'i'
       )
    OR REGEXP_LIKE(
           QUERY_TEXT,
           '^\\s*DROP\\s+STREAMLIT\\b',
           'i'
       )
  )
GROUP BY
    TO_DATE(START_TIME),
    CASE
        WHEN REGEXP_LIKE(
            QUERY_TEXT,
            '^\\s*CREATE\\s+(OR\\s+REPLACE\\s+)?STREAMLIT\\b',
            'i'
        ) THEN 'CREATE STREAMLIT'
        WHEN REGEXP_LIKE(
            QUERY_TEXT,
            '^\\s*ALTER\\s+STREAMLIT\\b',
            'i'
        ) THEN 'ALTER STREAMLIT'
        WHEN REGEXP_LIKE(
            QUERY_TEXT,
            '^\\s*DROP\\s+STREAMLIT\\b',
            'i'
        ) THEN 'DROP STREAMLIT'
    END,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME;

-- ============================================================
-- 3. AUTOMATED OPS COST TASK
-- ============================================================
-- IMPORTANT:
-- Replace <FINAL_UPSTREAM_TASK> with your actual final upstream
-- TASK name.
--
-- Example:
-- AFTER AUTOPULSE_AI.DQ.<YOUR_FINAL_TASK>
--
-- The task below does incremental INSERTs only.
-- Existing historical records are preserved.
--
-- The Account Usage views have reporting latency, so the task
-- intentionally looks back several hours for each run but uses
-- NOT EXISTS to prevent duplicates.
-- ============================================================

-- DEMO: Changed from AFTER <FINAL_UPSTREAM_TASK> to standalone 1 MINUTE schedule.
-- For production, change to: AFTER AUTOPULSE_AI.DQ.TASK_DQ_ZIP_CODE_INFO

CREATE OR REPLACE TASK AUTOPULSE_AI.OPS.OPS_COST_REFRESH_TASK
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Incrementally load AutoPulse OPS cost data (DEMO: 1 min standalone).'
AS
BEGIN

    -- --------------------------------------------------------
    -- Warehouse cost
    -- --------------------------------------------------------
    INSERT INTO AUTOPULSE_AI.OPS.COST_WAREHOUSE
    (
        WAREHOUSE_NAME,
        USAGE_DATE,
        CREDITS_USED,
        CREDITS_COMPUTE,
        CREDITS_CLOUD
    )
    SELECT
        S.WAREHOUSE_NAME,
        S.START_TIME,
        S.CREDITS_USED,
        S.CREDITS_USED_COMPUTE,
        S.CREDITS_USED_CLOUD_SERVICES
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY S
    WHERE S.WAREHOUSE_NAME = 'AUTOPULSE_WH'
      AND S.START_TIME >= DATEADD(HOUR, -12, CURRENT_TIMESTAMP())
      AND NOT EXISTS (
          SELECT 1
          FROM AUTOPULSE_AI.OPS.COST_WAREHOUSE T
          WHERE T.WAREHOUSE_NAME = S.WAREHOUSE_NAME
            AND T.USAGE_DATE = S.START_TIME
      );

    -- --------------------------------------------------------
    -- Serverless task cost
    -- --------------------------------------------------------
    INSERT INTO AUTOPULSE_AI.OPS.COST_SERVERLESS
    (
        TASK_NAME,
        TASK_SCHEMA,
        USAGE_DATE,
        CREDITS_USED,
        TASK_RUN_COUNT,
        TASK_AVG_DURATION
    )
    SELECT
        S.TASK_NAME,
        S.SCHEMA_NAME,
        S.START_TIME,
        TRY_TO_DECIMAL(S.CREDITS_USED, 38, 9),
        1,
        DATEDIFF('second', S.START_TIME, S.END_TIME)
    FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY S
    WHERE S.DATABASE_NAME = 'AUTOPULSE_AI'
      AND S.START_TIME >= DATEADD(HOUR, -12, CURRENT_TIMESTAMP())
      AND NOT EXISTS (
          SELECT 1
          FROM AUTOPULSE_AI.OPS.COST_SERVERLESS T
          WHERE T.TASK_NAME = S.TASK_NAME
            AND T.TASK_SCHEMA = S.SCHEMA_NAME
            AND T.USAGE_DATE = S.START_TIME
      );

    -- --------------------------------------------------------
    -- Snowpipe cost
    -- --------------------------------------------------------
    INSERT INTO AUTOPULSE_AI.OPS.COST_PIPES
    (
        PIPE_NAME,
        USAGE_DATE,
        CREDITS_USED,
        BYTES_INSERTED,
        FILES_INSERTED
    )
    SELECT
        S.PIPE_NAME,
        S.START_TIME,
        S.CREDITS_USED,
        S.BYTES_INSERTED,
        S.FILES_INSERTED
    FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY S
    WHERE S.PIPE_NAME ILIKE '%AUTOPULSE%'
      AND S.START_TIME >= DATEADD(HOUR, -12, CURRENT_TIMESTAMP())
      AND NOT EXISTS (
          SELECT 1
          FROM AUTOPULSE_AI.OPS.COST_PIPES T
          WHERE T.PIPE_NAME = S.PIPE_NAME
            AND T.USAGE_DATE = S.START_TIME
      );

    -- --------------------------------------------------------
    -- Storage
    -- --------------------------------------------------------
    INSERT INTO AUTOPULSE_AI.OPS.COST_STORAGE
    (
        USAGE_DATE,
        STORAGE_TB,
        STAGE_TB,
        FAILSAFE_TB,
        TOTAL_TB
    )
    SELECT
        S.USAGE_DATE,
        ROUND(S.STORAGE_BYTES / POWER(1024, 4), 4),
        ROUND(S.STAGE_BYTES / POWER(1024, 4), 4),
        ROUND(S.FAILSAFE_BYTES / POWER(1024, 4), 4),
        ROUND(
            (
                COALESCE(S.STORAGE_BYTES, 0)
              + COALESCE(S.STAGE_BYTES, 0)
              + COALESCE(S.FAILSAFE_BYTES, 0)
            ) / POWER(1024, 4),
            4
        )
    FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE S
    WHERE S.USAGE_DATE >= DATEADD(DAY, -7, CURRENT_DATE())
      AND NOT EXISTS (
          SELECT 1
          FROM AUTOPULSE_AI.OPS.COST_STORAGE T
          WHERE T.USAGE_DATE = S.USAGE_DATE
      );

    -- --------------------------------------------------------
    -- Streamlit container runtime
    -- --------------------------------------------------------
    INSERT INTO AUTOPULSE_AI.OPS.COST_STREAMLIT_RUNTIME
    (
        USAGE_DATE,
        START_TIME,
        END_TIME,
        COMPUTE_POOL_NAME,
        RUNTIME_TYPE,
        CREDITS_USED
    )
    SELECT
        TO_DATE(S.START_TIME),
        S.START_TIME,
        S.END_TIME,
        S.COMPUTE_POOL_NAME,
        'STREAMLIT_CONTAINER_RUNTIME',
        S.CREDITS_USED
    FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWPARK_CONTAINER_SERVICES_HISTORY S
    WHERE S.COMPUTE_POOL_NAME = 'SYSTEM_COMPUTE_POOL_CPU'
      AND S.START_TIME >= DATEADD(HOUR, -12, CURRENT_TIMESTAMP())
      AND NOT EXISTS (
          SELECT 1
          FROM AUTOPULSE_AI.OPS.COST_STREAMLIT_RUNTIME T
          WHERE T.START_TIME = S.START_TIME
            AND T.END_TIME = S.END_TIME
            AND T.COMPUTE_POOL_NAME = S.COMPUTE_POOL_NAME
      );

    -- --------------------------------------------------------
    -- Streamlit DDL activity
    -- --------------------------------------------------------
    -- Delete/reload only the recent reporting window because
    -- Account Usage QUERY_HISTORY can receive late-arriving rows.
    DELETE FROM AUTOPULSE_AI.OPS.COST_STREAMLIT_DDL
    WHERE OPERATION_DATE >= DATEADD(DAY, -7, CURRENT_DATE());

    INSERT INTO AUTOPULSE_AI.OPS.COST_STREAMLIT_DDL
    (
        OPERATION_DATE,
        OPERATION,
        USER_NAME,
        ROLE_NAME,
        WAREHOUSE_NAME,
        OPERATION_COUNT
    )
    SELECT
        TO_DATE(S.START_TIME),
        CASE
            WHEN REGEXP_LIKE(
                S.QUERY_TEXT,
                '^\\s*CREATE\\s+(OR\\s+REPLACE\\s+)?STREAMLIT\\b',
                'i'
            ) THEN 'CREATE STREAMLIT'
            WHEN REGEXP_LIKE(
                S.QUERY_TEXT,
                '^\\s*ALTER\\s+STREAMLIT\\b',
                'i'
            ) THEN 'ALTER STREAMLIT'
            WHEN REGEXP_LIKE(
                S.QUERY_TEXT,
                '^\\s*DROP\\s+STREAMLIT\\b',
                'i'
            ) THEN 'DROP STREAMLIT'
        END,
        S.USER_NAME,
        S.ROLE_NAME,
        S.WAREHOUSE_NAME,
        COUNT(*)
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY S
    WHERE S.START_TIME >= DATEADD(DAY, -7, CURRENT_TIMESTAMP())
      AND (
           REGEXP_LIKE(
               S.QUERY_TEXT,
               '^\\s*CREATE\\s+(OR\\s+REPLACE\\s+)?STREAMLIT\\b',
               'i'
           )
        OR REGEXP_LIKE(
               S.QUERY_TEXT,
               '^\\s*ALTER\\s+STREAMLIT\\b',
               'i'
           )
        OR REGEXP_LIKE(
               S.QUERY_TEXT,
               '^\\s*DROP\\s+STREAMLIT\\b',
               'i'
           )
      )
    GROUP BY
        TO_DATE(S.START_TIME),
        CASE
            WHEN REGEXP_LIKE(
                S.QUERY_TEXT,
                '^\\s*CREATE\\s+(OR\\s+REPLACE\\s+)?STREAMLIT\\b',
                'i'
            ) THEN 'CREATE STREAMLIT'
            WHEN REGEXP_LIKE(
                S.QUERY_TEXT,
                '^\\s*ALTER\\s+STREAMLIT\\b',
                'i'
            ) THEN 'ALTER STREAMLIT'
            WHEN REGEXP_LIKE(
                S.QUERY_TEXT,
                '^\\s*DROP\\s+STREAMLIT\\b',
                'i'
            ) THEN 'DROP STREAMLIT'
        END,
        S.USER_NAME,
        S.ROLE_NAME,
        S.WAREHOUSE_NAME;

END;

-- ============================================================
-- 4. TASK PRIVILEGES
-- ============================================================

USE ROLE SYSADMIN;

GRANT USAGE ON DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT USAGE ON SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT SELECT ON ALL TABLES IN SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_AI_ENGINEER;

-- ============================================================
-- 5. ENABLE THE TASK
-- ============================================================
-- Do this ONLY after the OPS tables and procedure are created.

USE ROLE ACCOUNTADMIN;

ALTER TASK AUTOPULSE_AI.OPS.OPS_COST_REFRESH_TASK RESUME;

-- ============================================================
-- 6. VALIDATION
-- ============================================================

SHOW TASKS IN SCHEMA AUTOPULSE_AI.OPS;

SELECT
    'COST_WAREHOUSE' AS TABLE_NAME,
    COUNT(*) AS ROW_COUNT
FROM AUTOPULSE_AI.OPS.COST_WAREHOUSE
UNION ALL
SELECT
    'COST_SERVERLESS',
    COUNT(*)
FROM AUTOPULSE_AI.OPS.COST_SERVERLESS
UNION ALL
SELECT
    'COST_PIPES',
    COUNT(*)
FROM AUTOPULSE_AI.OPS.COST_PIPES
UNION ALL
SELECT
    'COST_STORAGE',
    COUNT(*)
FROM AUTOPULSE_AI.OPS.COST_STORAGE
UNION ALL
SELECT
    'COST_STREAMLIT_RUNTIME',
    COUNT(*)
FROM AUTOPULSE_AI.OPS.COST_STREAMLIT_RUNTIME
UNION ALL
SELECT
    'COST_STREAMLIT_DDL',
    COUNT(*)
FROM AUTOPULSE_AI.OPS.COST_STREAMLIT_DDL;
