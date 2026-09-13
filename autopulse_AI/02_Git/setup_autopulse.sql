-- ============================================================
-- AutoPulse Setup Script (Warehouse -> DB -> Schema -> Git Integration)
-- ============================================================

-- Use highest role for setup
USE ROLE ACCOUNTADMIN;

-- Step 0a: Define variables directly in the script
-- For production, replace with secure injection or external secret manager.
SET gh_username = 'vvravishankar';
SET gh_pat = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';

-- Step 1: Warehouse
CREATE WAREHOUSE IF NOT EXISTS AUTOPULSE_WH
    WITH WAREHOUSE_SIZE='X-SMALL'
    AUTO_SUSPEND=300
    AUTO_RESUME=TRUE
    INITIALLY_SUSPENDED=TRUE
    COMMENT='AutoPulse AI project warehouse - all scripts use this WH for cost tracking';

USE WAREHOUSE AUTOPULSE_WH;

-- Step 2: Database
CREATE DATABASE IF NOT EXISTS AUTOPULSE_AI
    COMMENT='AutoPulse AI - battery intelligence, DQ, ML and Cortex platform';

USE DATABASE AUTOPULSE_AI;

-- Step 3: Schema
CREATE SCHEMA IF NOT EXISTS GIT
    COMMENT='Schema for Git integration objects (secrets, API integrations, repo clones)';

USE SCHEMA GIT;

-- Step 4: Secret
CREATE OR REPLACE SECRET git_secret
    TYPE=PASSWORD
    USERNAME=$gh_username
    PASSWORD=$gh_pat
    COMMENT='GitHub PAT for Git integration - created by setup script';

-- Step 5: API Integration
CREATE OR REPLACE API INTEGRATION git_api_integration
    API_PROVIDER=git_https_api
    API_ALLOWED_PREFIXES=('https://github.com/vvravishankar')
    ALLOWED_AUTHENTICATION_SECRETS=(git_secret)
    ENABLED=TRUE
    COMMENT='API integration for GitHub (vvravishankar)';

-- Step 6: Git Repository
CREATE OR REPLACE GIT REPOSITORY SNOWFLAKE_AUTO_PROJECT
    API_INTEGRATION=git_api_integration
    GIT_CREDENTIALS=git_secret
    ORIGIN='https://github.com/vvravishankar/snowflake_auto_project.git';

ALTER GIT REPOSITORY SNOWFLAKE_AUTO_PROJECT FETCH;

-- ============================================================
-- Verification Section (role-agnostic, using SHOW commands)
-- ============================================================

SHOW WAREHOUSES;
SHOW DATABASES;
SHOW SCHEMAS IN DATABASE AUTOPULSE_AI;
SHOW SECRETS IN SCHEMA AUTOPULSE_AI.GIT;
SHOW API INTEGRATIONS LIKE 'GIT_API_INTEGRATION';
SHOW GIT REPOSITORIES;
