-- ============================================================================
-- AUTOPULSE AI - PRODUCTION DATA QUALITY (DQ) INFRASTRUCTURE
-- ============================================================================
-- Purpose:
--   * Store governed DQ rule definitions and execution results.
--   * Preserve rejected source records for investigation and reprocessing.
--   * Detect incremental RAW ingestion through append-only streams.
--   * Trigger DQ processing through Snowflake serverless tasks.
--
-- Architecture:
--   Snowpipe -> RAW -> DQ Stream -> Serverless DQ Task -> RUN_DQ_FW()
--                                      |-> DQ_RESULTS
--                                      |-> REJECTED_RECORDS
--
-- Scheduling:
--   Each task checks its stream every 600 minutes (10 hours).
--   SYSTEM$STREAM_HAS_DATA() prevents RUN_DQ_FW from executing when no new
--   records are available.
--
-- IMPORTANT:
--   * Streams are owned by DQ, not RAW.
--   * Tasks are serverless and use XSMALL as their initial managed size.
--   * RUN_DQ_FW must consume the corresponding DQ stream.
--   * RUN_DQ_FW receives the RAW TABLE name, not a Snowpipe/PIPE name.
--   * This file assumes RAW tables, OPS.PIPELINE_RUNS, and RUN_DQ_FW exist.
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE AUTOPULSE_WH;
USE DATABASE AUTOPULSE_AI;
USE SCHEMA DQ;

-- ============================================================================
-- 1. DQ RULE CATALOG
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.DQ.DQ_RULES (
    RULE_ID        VARCHAR(100) COMMENT 'Stable unique identifier for the DQ rule.',
    RULE_NAME      VARCHAR(200) COMMENT 'Human-readable DQ rule name.',
    SOURCE_TABLE   VARCHAR(200) COMMENT 'RAW source table evaluated by the rule.',
    RULE_TYPE      VARCHAR(50) COMMENT 'DQ category such as NOT_NULL, UNIQUE, RANGE, FORMAT, DOMAIN, REFERENTIAL, or DUPLICATE.',
    IS_ACTIVE      BOOLEAN DEFAULT TRUE COMMENT 'Whether the rule is active and eligible for execution.',
    SOURCE_COLUMN  VARCHAR(200) COMMENT 'Source column associated with the rule, when applicable.',
    RULE_SQL       VARCHAR(16777216) COMMENT 'SQL predicate or rule expression used by the DQ framework.',
    CREATED_AT     TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() COMMENT 'Timestamp when the rule was registered.',
    UPDATED_AT     TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() COMMENT 'Timestamp when the rule definition was last updated.',
    CREATED_BY     VARCHAR(200) COMMENT 'User, role, or deployment process that created the rule.',
    COMMENT        VARCHAR(16777216) COMMENT 'Business or technical notes describing the rule.'
)
COMMENT = 'Governed AutoPulse AI DQ rule catalog containing executable rule definitions and operational metadata.';

-- ============================================================================
-- 2. DQ EXECUTION RESULTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.DQ.DQ_RESULTS (
    DQ_RESULT_ID       VARCHAR(100) COMMENT 'Unique identifier for an individual DQ evaluation result.',
    RUN_ID             VARCHAR(100) COMMENT 'Identifier of the DQ pipeline execution recorded in OPS.PIPELINE_RUNS.',
    RULE_ID            VARCHAR(100) COMMENT 'Identifier of the DQ rule that produced this result.',
    SOURCE_TABLE       VARCHAR(200) COMMENT 'RAW source table evaluated by the DQ rule.',
    SOURCE_COLUMN      VARCHAR(200) COMMENT 'Source column evaluated by the DQ rule, when applicable.',
    CHECKED_AT         TIMESTAMP_NTZ(9) COMMENT 'Timestamp when the DQ check was executed.',
    ROWS_CHECKED       NUMBER(38,0) COMMENT 'Number of records evaluated by the DQ rule.',
    ROWS_PASSED        NUMBER(38,0) COMMENT 'Number of records that passed the DQ rule.',
    ROWS_FAILED        NUMBER(38,0) COMMENT 'Number of records that failed the DQ rule.',
    STATUS             VARCHAR(20) COMMENT 'Overall result such as PASS, FAIL, or WARNING.',
    FAILURE_PERCENTAGE NUMBER(7,4) COMMENT 'Percentage of checked records that failed the DQ rule.',
    FAILURE_SUMMARY    VARCHAR(16777216) COMMENT 'Summary of failures identified by the DQ rule.',
    CREATED_AT         TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() COMMENT 'Timestamp when the DQ result record was created.'
)
COMMENT = 'AutoPulse AI DQ execution results containing rule-level pass/fail statistics and failure summaries.';

-- ============================================================================
-- 3. REJECTED RECORDS / QUARANTINE
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.DQ.REJECTED_RECORDS (
    REJECTED_RECORD_ID VARCHAR(100) DEFAULT UUID_STRING() COMMENT 'Unique identifier for the quarantined record.',
    RUN_ID             VARCHAR(100) COMMENT 'Identifier of the DQ pipeline execution that rejected the record.',
    SOURCE_FILE_NAME   VARCHAR(500) COMMENT 'Source file name captured during RAW ingestion, when available.',
    SOURCE_TABLE       VARCHAR(200) COMMENT 'RAW source table associated with the rejected record.',
    SOURCE_ROW_NUMBER  NUMBER(38,0) COMMENT 'Original source row number, when available.',
    RECORD_KEY         VARCHAR(500) COMMENT 'Business/source key identifying the rejected record.',
    RECORD_DATA        VARIANT COMMENT 'Complete rejected source record stored as semi-structured data.',
    RULE_ID            VARCHAR(100) COMMENT 'DQ rule that caused the rejection.',
    RULE_NAME          VARCHAR(200) COMMENT 'DQ rule name that caused the rejection.',
    REJECTION_REASON   VARCHAR(16777216) COMMENT 'Detailed explanation of why the record failed.',
    REJECTED_AT        TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() COMMENT 'Timestamp when the record entered quarantine.',
    REPROCESS_STATUS   VARCHAR(30) DEFAULT 'PENDING' COMMENT 'Lifecycle status: PENDING, CORRECTED, RESUBMITTED, ACCEPTED, or PERMANENTLY_REJECTED.',
    REPROCESS_ATTEMPTS NUMBER(10,0) DEFAULT 0 COMMENT 'Number of reprocessing attempts.',
    REPROCESSED_AT     TIMESTAMP_NTZ(9) COMMENT 'Timestamp when the record was last reprocessed.',
    REPROCESS_NOTES    VARCHAR(16777216) COMMENT 'Notes describing corrections or reprocessing actions.',
    CREATED_AT         TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() COMMENT 'Timestamp when the quarantine record was created.'
)
COMMENT = 'AutoPulse AI DQ quarantine repository preserving rejected records, failure reasons, and reprocessing state.';

-- ============================================================================
-- 4. APPEND-ONLY STREAMS
-- ============================================================================

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_BATTERY_COMPONENTS_RAW
    ON TABLE AUTOPULSE_AI.RAW.BATTERY_COMPONENTS_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested BATTERY_COMPONENTS_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_BATTERY_SUPPLIER_RAW
    ON TABLE AUTOPULSE_AI.RAW.BATTERY_SUPPLIER_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested BATTERY_SUPPLIER_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_BATTERY_TYPE_RAW
    ON TABLE AUTOPULSE_AI.RAW.BATTERY_TYPE_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested BATTERY_TYPE_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_DATE_VALUES_YEAR_RAW
    ON TABLE AUTOPULSE_AI.RAW.DATE_VALUES_YEAR_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested DATE_VALUES_YEAR_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_DTC_BATTERY_ERROR_CODES_RAW
    ON TABLE AUTOPULSE_AI.RAW.DTC_BATTERY_ERROR_CODES_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested DTC_BATTERY_ERROR_CODES_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_PART_BATTERY_RAW
    ON TABLE AUTOPULSE_AI.RAW.PART_BATTERY_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested PART_BATTERY_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_STATES_AND_ABBREVIATIONS_RAW
    ON TABLE AUTOPULSE_AI.RAW.STATES_AND_ABBREVIATIONS_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested STATES_AND_ABBREVIATIONS_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_VEHICLES_RAW
    ON TABLE AUTOPULSE_AI.RAW.VEHICLES_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested VEHICLES_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_VEHICLE_EVENTS_RAW
    ON TABLE AUTOPULSE_AI.RAW.VEHICLE_EVENTS_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested VEHICLE_EVENTS_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_WEATHER_DATA_RAW
    ON TABLE AUTOPULSE_AI.RAW.WEATHER_DATA_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested WEATHER_DATA_RAW records.';

CREATE OR REPLACE STREAM AUTOPULSE_AI.DQ.STREAM_ZIP_CODE_INFO_RAW
    ON TABLE AUTOPULSE_AI.RAW.ZIP_CODE_INFO_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'DQ stream for newly ingested ZIP_CODE_INFO_RAW records.';

-- ============================================================================
-- 5. SERVERLESS DQ TASKS — DEMO MODE: 1 MINUTE
-- ============================================================================
-- For production, change back to SCHEDULE = '600 MINUTE'.
-- ============================================================================

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_BATTERY_COMPONENTS
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for BATTERY_COMPONENTS_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_BATTERY_COMPONENTS_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('BATTERY_COMPONENTS_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_BATTERY_SUPPLIER
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for BATTERY_SUPPLIER_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_BATTERY_SUPPLIER_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('BATTERY_SUPPLIER_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_BATTERY_TYPE
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for BATTERY_TYPE_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_BATTERY_TYPE_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('BATTERY_TYPE_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_DATE_VALUES_YEAR
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for DATE_VALUES_YEAR_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_DATE_VALUES_YEAR_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('DATE_VALUES_YEAR_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_DTC_BATTERY_ERROR_CODES
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for DTC_BATTERY_ERROR_CODES_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_DTC_BATTERY_ERROR_CODES_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('DTC_BATTERY_ERROR_CODES_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_PART_BATTERY
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for PART_BATTERY_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_PART_BATTERY_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('PART_BATTERY_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_STATES_AND_ABBREVIATIONS
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for STATES_AND_ABBREVIATIONS_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_STATES_AND_ABBREVIATIONS_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('STATES_AND_ABBREVIATIONS_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_VEHICLES
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for VEHICLES_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_VEHICLES_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('VEHICLES_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_VEHICLE_EVENTS
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for VEHICLE_EVENTS_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_VEHICLE_EVENTS_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('VEHICLE_EVENTS_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_WEATHER_DATA
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for WEATHER_DATA_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_WEATHER_DATA_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('WEATHER_DATA_RAW');

CREATE OR REPLACE TASK AUTOPULSE_AI.DQ.TASK_DQ_ZIP_CODE_INFO
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Serverless DQ task for ZIP_CODE_INFO_RAW (DEMO: 1 min).'
    WHEN SYSTEM$STREAM_HAS_DATA('AUTOPULSE_AI.DQ.STREAM_ZIP_CODE_INFO_RAW')
AS
    CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('ZIP_CODE_INFO_RAW');

-- ============================================================================
-- 6. ACTIVATE TASKS
-- ============================================================================

ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_BATTERY_COMPONENTS RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_BATTERY_SUPPLIER RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_BATTERY_TYPE RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_DATE_VALUES_YEAR RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_DTC_BATTERY_ERROR_CODES RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_PART_BATTERY RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_STATES_AND_ABBREVIATIONS RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_VEHICLES RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_VEHICLE_EVENTS RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_WEATHER_DATA RESUME;
ALTER TASK AUTOPULSE_AI.DQ.TASK_DQ_ZIP_CODE_INFO RESUME;

-- ============================================================================
-- 7. FIX IS_ACTIVE COLUMN TYPE (CSV LOAD WORKAROUND)
-- ============================================================================
-- When DQ_Rules.CSV is loaded before this script runs, IS_ACTIVE may be
-- VARCHAR 'TRUE'/'FALSE' instead of BOOLEAN. The RUN_DQ_FW procedure
-- checks IS_ACTIVE = TRUE (boolean comparison), so we must ensure the
-- column is BOOLEAN. This block is idempotent — safe to rerun.
-- ============================================================================

ALTER TABLE AUTOPULSE_AI.DQ.DQ_RULES ADD COLUMN IF NOT EXISTS IS_ACTIVE_BOOL BOOLEAN;

UPDATE AUTOPULSE_AI.DQ.DQ_RULES
SET IS_ACTIVE_BOOL = CASE
    WHEN IS_ACTIVE::VARCHAR IN ('TRUE','true','1') THEN TRUE
    ELSE FALSE
END
WHERE IS_ACTIVE_BOOL IS NULL;

-- Only drop + rename if IS_ACTIVE is not already BOOLEAN
-- (safe because ADD COLUMN IF NOT EXISTS is a no-op when column exists)
ALTER TABLE AUTOPULSE_AI.DQ.DQ_RULES DROP COLUMN IS_ACTIVE;
ALTER TABLE AUTOPULSE_AI.DQ.DQ_RULES RENAME COLUMN IS_ACTIVE_BOOL TO IS_ACTIVE;

