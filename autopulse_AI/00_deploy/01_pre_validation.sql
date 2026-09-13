-- ============================================================
-- PHASE 1: PRE-DEPLOYMENT VALIDATION
-- ============================================================
-- Checks if AutoPulse objects already exist.
-- Run BEFORE deployment to understand current state.
-- No warehouse needed — uses only SHOW commands.
-- ============================================================

USE ROLE ACCOUNTADMIN;

SHOW DATABASES LIKE 'AUTOPULSE_AI';
SHOW WAREHOUSES LIKE 'AUTOPULSE_WH';
SHOW ROLES LIKE 'AUTOPULSE_%';
