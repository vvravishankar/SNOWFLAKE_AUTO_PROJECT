-- ============================================================
-- TEARDOWN — AutoPulse AI (Full Clean Slate)
-- ============================================================
-- Drops EVERYTHING: database, warehouse, roles, users.
-- Run this to completely remove the AutoPulse AI platform.
--
-- WARNING: This is irreversible. All data will be lost.
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- 1. Drop database (cascades: tables, pipes, streams, tasks,
--    stages, dynamic tables, semantic views, agents, procedures,
--    functions, file formats)
DROP DATABASE IF EXISTS AUTOPULSE_AI CASCADE;

-- 2. Drop warehouse
DROP WAREHOUSE IF EXISTS AUTOPULSE_WH;

-- 3. Drop API integration (Git)
DROP API INTEGRATION IF EXISTS GIT_API_INTEGRATION;

-- 4. Drop roles
DROP ROLE IF EXISTS AUTOPULSE_COMMON;
DROP ROLE IF EXISTS AUTOPULSE_ETL_ENGINEER;
DROP ROLE IF EXISTS AUTOPULSE_AI_ENGINEER;
DROP ROLE IF EXISTS AUTOPULSE_PYTHON_ENGINEER;
DROP ROLE IF EXISTS AUTOPULSE_VIEWER;

-- 5. Drop users
DROP USER IF EXISTS PRASHANTPALIWAL;
DROP USER IF EXISTS SHAREENKHAN;
DROP USER IF EXISTS VEERESHGODUGU;

-- ============================================================
-- VERIFICATION — confirm nothing remains
-- ============================================================
SHOW DATABASES LIKE 'AUTOPULSE_AI';
SHOW WAREHOUSES LIKE 'AUTOPULSE%';
SHOW ROLES LIKE 'AUTOPULSE_%';
SHOW API INTEGRATIONS LIKE 'GIT%';
