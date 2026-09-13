-- ============================================================
-- PHASE 4: POST-DEPLOYMENT VERIFICATION
-- ============================================================
-- Validates all deployed objects exist with expected counts.
-- Run after Phase 3 to confirm deployment success.
--
-- Expected:
--   RAW: 11 tables, 11 pipes, 1 stage, 1 file format
--   CLEAN: 11 tables
--   DQ: 3 tables, 11 streams, 11 tasks, 148 rules, 1 UDF, 1 proc
--   CURATED: 5 dynamic tables
--   OPS: 7 tables
--   Semantic Views: 3
--   Agents: 6
--   Roles: 5
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE AUTOPULSE_WH;

-- Object counts by schema
SELECT TABLE_SCHEMA, TABLE_TYPE, COUNT(*) AS CNT
FROM AUTOPULSE_AI.INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
GROUP BY TABLE_SCHEMA, TABLE_TYPE
ORDER BY TABLE_SCHEMA;

-- Dynamic tables
SHOW DYNAMIC TABLES IN DATABASE AUTOPULSE_AI;

-- Streams
SHOW STREAMS IN SCHEMA AUTOPULSE_AI.DQ;

-- Tasks
SHOW TASKS IN DATABASE AUTOPULSE_AI;

-- Pipes
SHOW PIPES IN SCHEMA AUTOPULSE_AI.RAW;

-- Semantic views
SHOW SEMANTIC VIEWS IN DATABASE AUTOPULSE_AI;

-- Agents
SHOW AGENTS IN DATABASE AUTOPULSE_AI;

-- DQ Rules loaded
SELECT COUNT(*) AS DQ_RULE_COUNT FROM AUTOPULSE_AI.DQ.DQ_RULES;

-- Roles
SHOW ROLES LIKE 'AUTOPULSE_%';
