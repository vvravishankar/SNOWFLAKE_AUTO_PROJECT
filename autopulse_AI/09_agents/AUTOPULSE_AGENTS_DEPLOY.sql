-- ============================================================================
-- AUTOPULSE AI | CORTEX AGENTS DEPLOYMENT
-- ============================================================================
--
-- Purpose:
--   Deploy 6 Cortex Agents for the AutoPulse AI platform. Each agent uses
--   a cortex_analyst_text_to_sql tool backed by one of the 3 semantic views.
--
-- Agents created (all in AUTOPULSE_AI.CURATED):
--   1. AUTOPULSE_BATTERY_AGENT         (blue)   → AUTOPULSE_BATTERY_INTELLIGENCE
--   2. AUTOPULSE_DQ_INTELLIGENCE       (green)  → AUTOPULSE_DQ_INTELLIGENCE
--   3. AUTOPULSE_RCA_AGENT             (orange) → AUTOPULSE_BATTERY_INTELLIGENCE
--   4. AUTOPULSE_PREDICTIVE_AGENT      (purple) → AUTOPULSE_BATTERY_INTELLIGENCE
--   5. AUTOPULSE_OPS_AGENT             (red)    → AUTOPULSE_OPS_INTELLIGENCE
--   6. AUTOPULSE_VEHICLE_QUALITY_AGENT (teal)   → AUTOPULSE_BATTERY_INTELLIGENCE
--
-- Dependencies:
--   - 3 semantic views must exist in AUTOPULSE_AI.CURATED (Step 11)
--   - Base tables in CURATED, DQ, and OPS must exist (Steps 3-10)
--   - AUTOPULSE_AI_ENGINEER role must have CREATE AGENT, CORTEX_USER,
--     and SELECT on all backing tables
--
-- Execution roles:
--   - ACCOUNTADMIN: grants privileges to AUTOPULSE_AI_ENGINEER
--   - AUTOPULSE_AI_ENGINEER: creates the agents (owns them)
--
-- Warehouse: AUTOPULSE_WH (used by each agent's cortex_analyst tool)
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE AUTOPULSE_WH;

-- Grants for AI_ENGINEER role
GRANT USAGE ON DATABASE AUTOPULSE_AI TO ROLE AUTOPULSE_AI_ENGINEER;
GRANT USAGE ON SCHEMA AUTOPULSE_AI.CURATED TO ROLE AUTOPULSE_AI_ENGINEER;
GRANT USAGE ON SCHEMA AUTOPULSE_AI.DQ TO ROLE AUTOPULSE_AI_ENGINEER;
GRANT USAGE ON SCHEMA AUTOPULSE_AI.OPS TO ROLE AUTOPULSE_AI_ENGINEER;
GRANT CREATE AGENT ON SCHEMA AUTOPULSE_AI.CURATED TO ROLE AUTOPULSE_AI_ENGINEER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE AUTOPULSE_AI_ENGINEER;

-- Select on tables backing the semantic views
GRANT SELECT ON ALL TABLES IN SCHEMA AUTOPULSE_AI.CURATED TO ROLE AUTOPULSE_AI_ENGINEER;
GRANT SELECT ON ALL TABLES IN SCHEMA AUTOPULSE_AI.DQ TO ROLE AUTOPULSE_AI_ENGINEER;
GRANT SELECT ON ALL TABLES IN SCHEMA AUTOPULSE_AI.OPS TO ROLE AUTOPULSE_AI_ENGINEER;


USE ROLE AUTOPULSE_AI_ENGINEER;
USE WAREHOUSE AUTOPULSE_WH;


-- ============================================================
-- 1. BATTERY AGENT
-- ============================================================

CREATE OR REPLACE AGENT AUTOPULSE_AI.CURATED.AUTOPULSE_BATTERY_AGENT
COMMENT = 'AutoPulse Battery Intelligence Agent'
PROFILE = '{"display_name":"AutoPulse Battery Intelligence","color":"blue"}'
FROM SPECIFICATION
$$
models:
  orchestration: auto
orchestration:
  capabilities:
    analytical_search: true
  tool_not_accessible: accept
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: >
    You are the AutoPulse Battery Intelligence Agent.
    Answer questions about vehicle battery health, battery failures,
    battery risk, battery events, battery predictions, root-cause
    analysis, battery components, suppliers, vehicles, and related
    operational context.
    Use the BatteryAnalyst tool when Snowflake data is required.
    Base factual answers on the returned data and never invent values.
    Be concise and business-oriented.
  orchestration: >
    Use BatteryAnalyst for questions about vehicle battery intelligence,
    battery health, battery failures, battery risk, predictions,
    root-cause analysis, vehicle events, battery components,
    suppliers, and related structured data.
  sample_questions:
    - question: "Which vehicles have the highest battery failure risk?"
    - question: "What are the main battery failure patterns?"
    - question: "Show battery-related events for a vehicle."
    - question: "What are the likely root causes of battery failures?"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: BatteryAnalyst
      description: >
        Answers vehicle battery intelligence questions using the
        AutoPulse battery semantic view.
tool_resources:
  BatteryAnalyst:
    semantic_view: AUTOPULSE_AI.CURATED.AUTOPULSE_BATTERY_INTELLIGENCE
    warehouse: AUTOPULSE_WH
$$;


-- ============================================================
-- 2. DQ AGENT
-- ============================================================

CREATE OR REPLACE AGENT AUTOPULSE_AI.CURATED.AUTOPULSE_DQ_INTELLIGENCE
COMMENT = 'AutoPulse Data Quality Intelligence Agent'
PROFILE = '{"display_name":"AutoPulse Data Quality Intelligence","color":"green"}'
FROM SPECIFICATION
$$
models:
  orchestration: auto
orchestration:
  capabilities:
    analytical_search: true
  tool_not_accessible: accept
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: >
    You are the AutoPulse Data Quality Intelligence Agent.
    Answer questions about data quality, DQ rules, DQ results,
    failed records, validation issues, source tables, data-quality
    trends, and pipeline data-quality status.
    Use the DQAnalyst tool when Snowflake data is required.
    Base factual answers on the returned data and never invent values.
    Clearly distinguish counts, failures, rules, and source tables.
  orchestration: >
    Use DQAnalyst for questions about data-quality results,
    failed records, DQ rules, validation status, source tables,
    DQ trends, and pipeline data-quality analysis.
  sample_questions:
    - question: "What data-quality issues occurred today?"
    - question: "Which DQ rules are failing most often?"
    - question: "Which source tables have the most DQ failures?"
    - question: "Show the latest data-quality results."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: DQAnalyst
      description: >
        Answers AutoPulse data-quality questions using the
        AutoPulse DQ semantic view.
tool_resources:
  DQAnalyst:
    semantic_view: AUTOPULSE_AI.CURATED.AUTOPULSE_DQ_INTELLIGENCE
    warehouse: AUTOPULSE_WH
$$;


-- ============================================================
-- 3. RCA AGENT
-- ============================================================

CREATE OR REPLACE AGENT AUTOPULSE_AI.CURATED.AUTOPULSE_RCA_AGENT
COMMENT = 'AutoPulse RCA Intelligence Agent'
PROFILE = '{"display_name":"AutoPulse RCA Intelligence","color":"orange"}'
FROM SPECIFICATION
$$
models:
  orchestration: auto
orchestration:
  capabilities:
    analytical_search: true
  tool_not_accessible: accept
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: >
    You are the AutoPulse RCA Intelligence Agent. Answer questions about
    root cause analysis of battery failures, failure patterns, component-level
    breakdowns, supplier correlations, and severity classifications. Use the
    RCAAnalyst tool when Snowflake data is required. Base factual answers on
    the returned data and never invent values. Be concise and business-oriented.
  orchestration: >
    Use RCAAnalyst for questions about root cause analysis, failure patterns,
    component breakdowns, supplier failure correlations, severity, and
    related structured data.
  sample_questions:
    - question: "What are the top root causes of battery failure?"
    - question: "Which battery components fail most often?"
    - question: "Show root cause breakdown by supplier"
    - question: "Which vehicle models have the most RCA entries?"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: RCAAnalyst
      description: >
        Answers root cause analysis questions using the AutoPulse battery
        semantic view.
tool_resources:
  RCAAnalyst:
    semantic_view: AUTOPULSE_AI.CURATED.AUTOPULSE_BATTERY_INTELLIGENCE
    warehouse: AUTOPULSE_WH
$$;


-- ============================================================
-- 4. PREDICTIVE AGENT
-- ============================================================

CREATE OR REPLACE AGENT AUTOPULSE_AI.CURATED.AUTOPULSE_PREDICTIVE_AGENT
COMMENT = 'AutoPulse Predictive Maintenance Agent'
PROFILE = '{"display_name":"AutoPulse Predictive Maintenance","color":"purple"}'
FROM SPECIFICATION
$$
models:
  orchestration: auto
orchestration:
  capabilities:
    analytical_search: true
  tool_not_accessible: accept
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: >
    You are the AutoPulse Predictive Maintenance Agent. Answer questions about
    battery failure predictions, risk levels, predicted failure days, failure
    probabilities, and predictive maintenance recommendations. Use the
    PredictiveAnalyst tool when Snowflake data is required. Base factual answers
    on the returned data and never invent values. Be concise and business-oriented.
  orchestration: >
    Use PredictiveAnalyst for questions about failure predictions, risk levels,
    predicted failure timelines, failure probability scores, and predictive
    maintenance analysis.
  sample_questions:
    - question: "Which vehicles are predicted to fail within 30 days?"
    - question: "Show the failure risk distribution across the fleet"
    - question: "What is the average predicted failure probability by battery type?"
    - question: "List critical-risk vehicles with their predicted failure days"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: PredictiveAnalyst
      description: >
        Answers predictive maintenance questions using the AutoPulse battery
        semantic view.
tool_resources:
  PredictiveAnalyst:
    semantic_view: AUTOPULSE_AI.CURATED.AUTOPULSE_BATTERY_INTELLIGENCE
    warehouse: AUTOPULSE_WH
$$;


-- ============================================================
-- 5. OPS AGENT
-- ============================================================

CREATE OR REPLACE AGENT AUTOPULSE_AI.CURATED.AUTOPULSE_OPS_AGENT
COMMENT = 'AutoPulse Ops & Cost Intelligence Agent'
PROFILE = '{"display_name":"AutoPulse Ops & Cost Intelligence","color":"red"}'
FROM SPECIFICATION
$$
models:
  orchestration: auto
orchestration:
  capabilities:
    analytical_search: true
  tool_not_accessible: accept
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: >
    You are the AutoPulse Ops & Cost Intelligence Agent. Answer questions
    about pipeline costs, warehouse credit usage, storage trends, task
    execution, pipe ingestion, and Streamlit runtime costs. Use the
    OpsAnalyst tool when Snowflake data is required. Base factual answers
    on the returned data and never invent values. Be concise and
    business-oriented.
  orchestration: >
    Use OpsAnalyst for questions about warehouse credits, storage, task runs,
    pipe ingestion, Streamlit runtime costs, layer-wise cost breakdowns,
    and pipeline operations.
  sample_questions:
    - question: "What is the total warehouse credit usage this month?"
    - question: "Show me layer-wise cost breakdown for Raw, Clean, and Curated"
    - question: "Which tasks consume the most credits?"
    - question: "What are the storage trends over the last 90 days?"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: OpsAnalyst
      description: >
        Answers operations and cost questions using the AutoPulse OPS
        semantic view.
tool_resources:
  OpsAnalyst:
    semantic_view: AUTOPULSE_AI.CURATED.AUTOPULSE_OPS_INTELLIGENCE
    warehouse: AUTOPULSE_WH
$$;


-- ============================================================
-- 6. VEHICLE QUALITY AGENT
-- ============================================================

CREATE OR REPLACE AGENT AUTOPULSE_AI.CURATED.AUTOPULSE_VEHICLE_QUALITY_AGENT
COMMENT = 'AutoPulse Vehicle Quality Agent'
PROFILE = '{"display_name":"AutoPulse Vehicle Quality","color":"teal"}'
FROM SPECIFICATION
$$
models:
  orchestration: auto
orchestration:
  capabilities:
    analytical_search: true
  tool_not_accessible: accept
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: >
    You are the AutoPulse Vehicle Quality Agent. Answer questions about
    vehicle quality scores, quality grade distributions, battery type
    performance, supplier quality rankings, failure rates by conditions
    (temperature, usage), and risk factor analysis. Use the VQAnalyst tool
    when Snowflake data is required. Base factual answers on the returned
    data and never invent values. Be concise and business-oriented.
  orchestration: >
    Use VQAnalyst for questions about vehicle quality grades, quality scores,
    battery type performance, supplier quality, failure rates, temperature
    impact, and risk factors.
  sample_questions:
    - question: "Show quality grade distribution by battery type"
    - question: "Which suppliers have the worst quality scores?"
    - question: "Which battery type at cold temperatures has the highest failure rate?"
    - question: "List all Grade F vehicles with their risk factors"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: VQAnalyst
      description: >
        Answers vehicle quality questions using the AutoPulse battery
        semantic view.
tool_resources:
  VQAnalyst:
    semantic_view: AUTOPULSE_AI.CURATED.AUTOPULSE_BATTERY_INTELLIGENCE
    warehouse: AUTOPULSE_WH
$$;


-- ============================================================
-- VALIDATION
-- ============================================================

SHOW AGENTS IN SCHEMA AUTOPULSE_AI.CURATED;
