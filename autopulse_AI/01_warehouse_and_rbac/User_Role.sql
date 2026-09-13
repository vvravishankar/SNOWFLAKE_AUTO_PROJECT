-- ============================================================================
-- AUTOPULSE AI - NEW ACCOUNT BOOTSTRAP & PRODUCTION-STYLE RBAC
-- ============================================================================
-- Run as ACCOUNTADMIN.
--
-- Creates:
--   * AUTOPULSE_WH (X-SMALL, auto-resume, 5-minute auto-suspend)
--   * AUTOPULSE_AI database
--   * RAW / CLEAN / CURATED / DQ / OPS schemas
--   * Functional roles:
--       AUTOPULSE_COMMON
--       AUTOPULSE_ETL_ENGINEER
--       AUTOPULSE_AI_ENGINEER
--       AUTOPULSE_PYTHON_ENGINEER
--       AUTOPULSE_VIEWER
--   * Team users:
--       PRASHANTPALIWAL -> ETL
--       SHAREENKHAN     -> AI
--       VEERESHGODUGU   -> Python
--
-- SECURITY:
--   Do NOT commit the real bootstrap password to the public Git repository.
--   Before running, change TEMP_PASSWORD below to a temporary password.
--   Users are forced to change that password at first login.
-- ============================================================================


-- ============================================================================
-- 0. ACCOUNT ADMIN
-- ============================================================================

USE ROLE ACCOUNTADMIN;


-- ============================================================================
-- 1. TEMPORARY BOOTSTRAP PASSWORD
-- ============================================================================
-- CHANGE THIS VALUE BEFORE RUNNING.
-- Do NOT commit your real password to Git.
-- ============================================================================

-- IMPORTANT: Replace this placeholder with a temporary password before running.
-- Do NOT commit the real password to Git.
SET TEMP_PASSWORD = 'TempPassword@123';


-- ============================================================================
-- 2. AUTOPULSE COMPUTE WAREHOUSE
-- ============================================================================
-- Cost-conscious development configuration:
--   SIZE          = X-SMALL
--   AUTO_RESUME   = TRUE
--   AUTO_SUSPEND  = 300 seconds / 5 minutes
--   INITIALLY_SUSPENDED = TRUE
--
-- The warehouse starts only when a query needs it and automatically stops
-- after 5 minutes of inactivity.
-- ============================================================================

CREATE WAREHOUSE IF NOT EXISTS AUTOPULSE_WH
    WITH
        WAREHOUSE_SIZE = 'X-SMALL'
        AUTO_SUSPEND = 300
        AUTO_RESUME = TRUE
        INITIALLY_SUSPENDED = TRUE
        COMMENT = 'AutoPulse AI hackathon warehouse - X-SMALL, auto-suspend after 5 minutes';

ALTER WAREHOUSE AUTOPULSE_WH SET
    WAREHOUSE_SIZE = 'X-SMALL',
    AUTO_SUSPEND = 300,
    AUTO_RESUME = TRUE;


-- ============================================================================
-- 3. AUTOPULSE DATABASE
-- ============================================================================

CREATE DATABASE IF NOT EXISTS AUTOPULSE_AI
    COMMENT = 'AutoPulse AI battery intelligence, DQ, ML and Cortex platform';


-- Make SYSADMIN the database owner so the database follows the standard
-- Snowflake administrator hierarchy.
GRANT OWNERSHIP ON DATABASE AUTOPULSE_AI
    TO ROLE SYSADMIN
    COPY CURRENT GRANTS;


-- ============================================================================
-- 4. AUTOPULSE SCHEMAS
-- ============================================================================

USE ROLE SYSADMIN;

CREATE SCHEMA IF NOT EXISTS AUTOPULSE_AI.RAW
    COMMENT = 'Raw ingestion layer - source data, stages, file formats and Snowpipes';

CREATE SCHEMA IF NOT EXISTS AUTOPULSE_AI.CURATED
    COMMENT = 'Curated business layer - 360 views, predictions, RCA and AI assets';

CREATE SCHEMA IF NOT EXISTS AUTOPULSE_AI.DQ
    COMMENT = 'Data quality framework, rules, results and date normalization';

CREATE SCHEMA IF NOT EXISTS AUTOPULSE_AI.CLEAN
    COMMENT = 'Clean/standardized data layer after normalization and DQ processing';

CREATE SCHEMA IF NOT EXISTS AUTOPULSE_AI.OPS
    COMMENT = 'Operational metadata, run tracking and orchestration';


-- ============================================================================
-- 5. FUNCTIONAL ROLES
-- ============================================================================
-- Production-style least-privilege design:
--
--   Prashant -> ETL Engineer
--   Shareen  -> AI Engineer
--   Veeresh  -> Python Engineer
--
-- AUTOPULSE_COMMON provides shared read/consumption access.
-- AUTOPULSE_VIEWER is reserved for judges/business users.
-- ============================================================================

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS AUTOPULSE_COMMON
    COMMENT = 'Common AutoPulse access for all project team members';

CREATE ROLE IF NOT EXISTS AUTOPULSE_ETL_ENGINEER
    COMMENT = 'AutoPulse ETL/Data Engineering - RAW, Snowpipe, DQ and orchestration';

CREATE ROLE IF NOT EXISTS AUTOPULSE_AI_ENGINEER
    COMMENT = 'AutoPulse AI Engineering - Cortex Agents, Cortex Analyst and semantic views';

CREATE ROLE IF NOT EXISTS AUTOPULSE_PYTHON_ENGINEER
    COMMENT = 'AutoPulse Python Engineering - Python, Streamlit, Snowpark and ML';

CREATE ROLE IF NOT EXISTS AUTOPULSE_VIEWER
    COMMENT = 'AutoPulse read-only consumer and judge access';


-- ============================================================================
-- 6. ROLE HIERARCHY
-- ============================================================================
-- Custom roles are granted to SYSADMIN.
-- Users receive functional roles, NOT SYSADMIN.
-- This follows Snowflake's recommended functional-role hierarchy.
-- ============================================================================

GRANT ROLE AUTOPULSE_COMMON
    TO ROLE SYSADMIN;

GRANT ROLE AUTOPULSE_ETL_ENGINEER
    TO ROLE SYSADMIN;

GRANT ROLE AUTOPULSE_AI_ENGINEER
    TO ROLE SYSADMIN;

GRANT ROLE AUTOPULSE_PYTHON_ENGINEER
    TO ROLE SYSADMIN;

GRANT ROLE AUTOPULSE_VIEWER
    TO ROLE SYSADMIN;


-- ============================================================================
-- 7. COMMON TEAM ACCESS
-- ============================================================================

GRANT USAGE
    ON DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_COMMON;

GRANT USAGE
    ON ALL SCHEMAS IN DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_COMMON;

GRANT USAGE
    ON FUTURE SCHEMAS IN DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_COMMON;

GRANT USAGE
    ON WAREHOUSE AUTOPULSE_WH
    TO ROLE AUTOPULSE_COMMON;


-- Shared consumption of curated outputs.

GRANT SELECT
    ON ALL TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_COMMON;

GRANT SELECT
    ON FUTURE TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_COMMON;

GRANT SELECT
    ON ALL VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_COMMON;

GRANT SELECT
    ON FUTURE VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_COMMON;


-- ============================================================================
-- 8. VIEWER / JUDGE ROLE
-- ============================================================================

GRANT USAGE
    ON DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_VIEWER;

GRANT USAGE
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_VIEWER;

GRANT USAGE
    ON WAREHOUSE AUTOPULSE_WH
    TO ROLE AUTOPULSE_VIEWER;

GRANT SELECT
    ON ALL TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_VIEWER;

GRANT SELECT
    ON FUTURE TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_VIEWER;

GRANT SELECT
    ON ALL VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_VIEWER;

GRANT SELECT
    ON FUTURE VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_VIEWER;


-- ============================================================================
-- 9. PRASHANT - ETL ENGINEER
-- ============================================================================
-- Responsibilities:
--   * RAW ingestion
--   * Snowpipe
--   * Stages / file formats
--   * DQ framework
--   * Date normalization
--   * Tasks / orchestration
--   * Curated data pipelines
-- ============================================================================

GRANT USAGE
    ON DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT USAGE
    ON ALL SCHEMAS IN DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT USAGE
    ON FUTURE SCHEMAS IN DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT USAGE, OPERATE, MONITOR
    ON WAREHOUSE AUTOPULSE_WH
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- RAW creation privileges.

GRANT CREATE TABLE
    ON SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE VIEW
    ON SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE STAGE
    ON SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE FILE FORMAT
    ON SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE PIPE
    ON SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE STREAM
    ON SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE PROCEDURE
    ON SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE FUNCTION
    ON SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- RAW table DML.

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
    ON ALL TABLES IN SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
    ON FUTURE TABLES IN SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- RAW stages.

GRANT USAGE, READ, WRITE
    ON ALL STAGES IN SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT USAGE, READ, WRITE
    ON FUTURE STAGES IN SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- RAW file formats.

GRANT USAGE
    ON ALL FILE FORMATS IN SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT USAGE
    ON FUTURE FILE FORMATS IN SCHEMA AUTOPULSE_AI.RAW
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- DQ creation privileges.

GRANT CREATE TABLE
    ON SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE VIEW
    ON SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE PROCEDURE
    ON SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE FUNCTION
    ON SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE TASK
    ON SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE STREAM
    ON SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- DQ table DML.

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
    ON ALL TABLES IN SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
    ON FUTURE TABLES IN SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- Tasks.

GRANT EXECUTE TASK
    ON ACCOUNT
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- OPS creation privileges.

GRANT CREATE TABLE
    ON SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE VIEW
    ON SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE PROCEDURE
    ON SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE FUNCTION
    ON SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE TASK
    ON SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE STREAM
    ON SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- OPS table DML.

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
    ON ALL TABLES IN SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
    ON FUTURE TABLES IN SCHEMA AUTOPULSE_AI.OPS
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- CURATED pipeline creation.

GRANT CREATE TABLE
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE VIEW
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE PROCEDURE
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE FUNCTION
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT CREATE STREAM
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- CURATED pipeline DML.

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
    ON ALL TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_ETL_ENGINEER;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
    ON FUTURE TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_ETL_ENGINEER;


-- ============================================================================
-- 10. SHAREEN - AI ENGINEER
-- ============================================================================
-- Responsibilities:
--   * Cortex Agents
--   * Cortex Analyst
--   * Semantic Views
--   * Cortex Search
--   * AI/LLM capabilities
--   * AI-facing curated data
-- ============================================================================

GRANT USAGE
    ON DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT USAGE
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT USAGE
    ON SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT USAGE
    ON WAREHOUSE AUTOPULSE_WH
    TO ROLE AUTOPULSE_AI_ENGINEER;


-- Curated data used by AI.

GRANT SELECT
    ON ALL TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT SELECT
    ON FUTURE TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT SELECT
    ON ALL VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT SELECT
    ON FUTURE VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;


-- DQ information used by the Data Quality Agent.

GRANT SELECT
    ON ALL TABLES IN SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT SELECT
    ON FUTURE TABLES IN SCHEMA AUTOPULSE_AI.DQ
    TO ROLE AUTOPULSE_AI_ENGINEER;


-- Cortex access.
-- CORTEX_USER includes Cortex Agents and other covered Cortex AI features.

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER
    TO ROLE AUTOPULSE_AI_ENGINEER;


-- Agent creation.

GRANT CREATE AGENT
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;


-- Semantic View creation for Cortex Analyst.

GRANT CREATE SEMANTIC VIEW
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;


-- Existing and future semantic views.

GRANT REFERENCES, SELECT
    ON ALL SEMANTIC VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT REFERENCES, SELECT
    ON FUTURE SEMANTIC VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;


-- Cortex Search services, if used by AutoPulse Agents.

GRANT CREATE CORTEX SEARCH SERVICE
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT USAGE
    ON ALL CORTEX SEARCH SERVICES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT USAGE
    ON FUTURE CORTEX SEARCH SERVICES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_AI_ENGINEER;

-- Streamlit Creation 

USE ROLE SYSADMIN;

GRANT USAGE
ON DATABASE AUTOPULSE_AI
TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT USAGE
ON SCHEMA AUTOPULSE_AI.CURATED
TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT CREATE STREAMLIT
ON SCHEMA AUTOPULSE_AI.CURATED
TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT USAGE
ON WAREHOUSE AUTOPULSE_WH
TO ROLE AUTOPULSE_AI_ENGINEER;

GRANT USAGE
ON COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU
TO ROLE AUTOPULSE_AI_ENGINEER;

-- ============================================================================
-- 11. VEERESH - PYTHON ENGINEER
-- ============================================================================
-- Responsibilities:
--   * Python / Snowpark
--   * Streamlit
--   * Stored procedures
--   * UDFs
--   * ML models
-- ============================================================================

GRANT USAGE
    ON DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;

GRANT USAGE
    ON ALL SCHEMAS IN DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;

GRANT USAGE
    ON FUTURE SCHEMAS IN DATABASE AUTOPULSE_AI
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;

GRANT USAGE
    ON WAREHOUSE AUTOPULSE_WH
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;


-- Python/Snowpark procedures and functions.

GRANT CREATE PROCEDURE
    ON SCHEMA AUTOPULSE_AI.CLEAN
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;

GRANT CREATE FUNCTION
    ON SCHEMA AUTOPULSE_AI.CLEAN
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;

GRANT CREATE STREAM
    ON SCHEMA AUTOPULSE_AI.CLEAN
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;


-- ML model creation.

GRANT CREATE MODEL
    ON SCHEMA AUTOPULSE_AI.CLEAN
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;


-- Curated data consumption.

GRANT SELECT
    ON ALL TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;

GRANT SELECT
    ON FUTURE TABLES IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;

GRANT SELECT
    ON ALL VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;

GRANT SELECT
    ON FUTURE VIEWS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;


-- Streamlit development/deployment in CURATED.

GRANT CREATE STREAMLIT
    ON SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_PYTHON_ENGINEER;


-- ============================================================================
-- 12. USER CREATION
-- ============================================================================
-- Three named project users are created below.
-- Each user receives only their functional AutoPulse role plus common access.
-- No project user is granted SYSADMIN directly.
-- ============================================================================
-- 12. USERS
-- ============================================================================
-- The users receive functional roles rather than SYSADMIN.
-- ============================================================================

USE ROLE ACCOUNTADMIN;


-- ----------------------------------------------------------------------------
-- Shareen Khan - AI Engineer
-- ----------------------------------------------------------------------------

CREATE USER IF NOT EXISTS SHAREENKHAN
    PASSWORD = $TEMP_PASSWORD
    LOGIN_NAME = 'shareen_khan'
    DISPLAY_NAME = 'Shareen Khan'
    FIRST_NAME = 'Shareen'
    LAST_NAME = 'Khan'
    EMAIL = 'shareen.khan@capgemini.com'
    DEFAULT_ROLE = AUTOPULSE_AI_ENGINEER
    DEFAULT_WAREHOUSE = AUTOPULSE_WH
    MUST_CHANGE_PASSWORD = TRUE
    COMMENT = 'AutoPulse AI Engineer - Cortex Agents, Cortex Analyst and semantic views';


-- ----------------------------------------------------------------------------
-- Prashant Paliwal - ETL Engineer
-- ----------------------------------------------------------------------------

CREATE USER IF NOT EXISTS PRASHANTPALIWAL
    PASSWORD = $TEMP_PASSWORD
    LOGIN_NAME = 'prashant.paliwal'
    DISPLAY_NAME = 'Prashant Paliwal'
    FIRST_NAME = 'Prashant'
    LAST_NAME = 'Paliwal'
    EMAIL = 'prashant.paliwal@capgemini.com'
    DEFAULT_ROLE = AUTOPULSE_ETL_ENGINEER
    DEFAULT_WAREHOUSE = AUTOPULSE_WH
    MUST_CHANGE_PASSWORD = TRUE
    COMMENT = 'AutoPulse ETL Engineer - ingestion, Snowpipe, DQ and orchestration';


-- ----------------------------------------------------------------------------
-- Veeresh Godugu - Python Engineer
-- ----------------------------------------------------------------------------

CREATE USER IF NOT EXISTS VEERESHGODUGU
    PASSWORD = $TEMP_PASSWORD
    LOGIN_NAME = 'godugu.veeresh'
    DISPLAY_NAME = 'Veeresh Godugu'
    FIRST_NAME = 'Veeresh'
    LAST_NAME = 'Godugu'
    EMAIL = 'godugu.veeresh@capgemini.com'
    DEFAULT_ROLE = AUTOPULSE_PYTHON_ENGINEER
    DEFAULT_WAREHOUSE = AUTOPULSE_WH
    MUST_CHANGE_PASSWORD = TRUE
    COMMENT = 'AutoPulse Python Engineer - Streamlit, Python, Snowpark and ML';


-- ============================================================================
-- 13. ASSIGN ROLES TO USERS
-- ============================================================================

GRANT ROLE AUTOPULSE_COMMON
    TO USER SHAREENKHAN;

GRANT ROLE AUTOPULSE_AI_ENGINEER
    TO USER SHAREENKHAN;


GRANT ROLE AUTOPULSE_COMMON
    TO USER PRASHANTPALIWAL;

GRANT ROLE AUTOPULSE_ETL_ENGINEER
    TO USER PRASHANTPALIWAL;


GRANT ROLE AUTOPULSE_COMMON
    TO USER VEERESHGODUGU;

GRANT ROLE AUTOPULSE_PYTHON_ENGINEER
    TO USER VEERESHGODUGU;


-- ============================================================================
-- 14. DEFAULT ROLE + DEFAULT WAREHOUSE
-- ============================================================================

ALTER USER SHAREENKHAN SET
    DEFAULT_ROLE = AUTOPULSE_AI_ENGINEER,
    DEFAULT_WAREHOUSE = AUTOPULSE_WH;

ALTER USER PRASHANTPALIWAL SET
    DEFAULT_ROLE = AUTOPULSE_ETL_ENGINEER,
    DEFAULT_WAREHOUSE = AUTOPULSE_WH;

ALTER USER VEERESHGODUGU SET
    DEFAULT_ROLE = AUTOPULSE_PYTHON_ENGINEER,
    DEFAULT_WAREHOUSE = AUTOPULSE_WH;


-- ============================================================================
-- 15. FUTURE STREAMLIT VIEW ACCESS
-- ============================================================================
-- Judges/business users can later receive AUTOPULSE_VIEWER.
-- This future grant lets that role view Streamlit apps created in CURATED.

GRANT USAGE
    ON FUTURE STREAMLITS IN SCHEMA AUTOPULSE_AI.CURATED
    TO ROLE AUTOPULSE_VIEWER;


-- ============================================================================
-- 16. AGENT ACCESS - RUN AFTER AGENTS ARE CREATED
-- ============================================================================
-- The following grants intentionally are NOT run in this bootstrap file
-- because the Agent objects may not exist yet.
--
-- Once the AutoPulse Agents exist, run:
--
-- GRANT USAGE ON AGENT
--     AUTOPULSE_AI.CURATED.AUTOPULSE_BATTERY_AGENT
--     TO ROLE AUTOPULSE_AI_ENGINEER;
--
-- GRANT USAGE ON AGENT
--     AUTOPULSE_AI.CURATED.AUTOPULSE_DQ_INTELLIGENCE
--     TO ROLE AUTOPULSE_AI_ENGINEER;
--
-- Add the same USAGE grant for any RCA / Predictive Maintenance Agents
-- when their exact object names are known.
-- ============================================================================


-- ============================================================================
-- 17. OPTIONAL CORTEX HARDENING
-- ============================================================================
-- Snowflake commonly grants CORTEX_USER to PUBLIC by default.
--
-- If this is a dedicated hackathon account and you want strict selective
-- Cortex access, you can remove the PUBLIC grant:
--
-- REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE PUBLIC;
--
-- Then only AUTOPULSE_AI_ENGINEER has CORTEX_USER from this script.
--
-- DO NOT execute this optional hardening blindly in a shared account because
-- it can affect other users/applications that rely on PUBLIC Cortex access.
-- ============================================================================


-- ============================================================================
-- 18. VERIFICATION
-- ============================================================================

SHOW WAREHOUSES LIKE 'AUTOPULSE_WH';

SHOW DATABASES LIKE 'AUTOPULSE_AI';

SHOW SCHEMAS IN DATABASE AUTOPULSE_AI;

SHOW ROLES LIKE 'AUTOPULSE_%';

SHOW USERS;

SHOW GRANTS TO USER SHAREENKHAN;
SHOW GRANTS TO USER PRASHANTPALIWAL;
SHOW GRANTS TO USER VEERESHGODUGU;

SHOW GRANTS TO ROLE AUTOPULSE_COMMON;

SHOW GRANTS TO ROLE AUTOPULSE_ETL_ENGINEER;

SHOW GRANTS TO ROLE AUTOPULSE_AI_ENGINEER;

SHOW GRANTS TO ROLE AUTOPULSE_PYTHON_ENGINEER;

SHOW GRANTS TO ROLE AUTOPULSE_VIEWER;

-- After Agents are created:
-- SHOW AGENTS IN DATABASE AUTOPULSE_AI;

-- After Streamlit is deployed:
-- SHOW STREAMLITS IN SCHEMA AUTOPULSE_AI.CURATED;


-- ============================================================================
-- END
-- ============================================================================
