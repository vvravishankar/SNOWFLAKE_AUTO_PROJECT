-- ============================================================================
-- AUTOPULSE AI
-- 02_RAW_INGESTION_SETUP.sql
-- ============================================================================
-- Purpose
--   Provision the AutoPulse RAW ingestion layer in a new Snowflake account:
--     1. Standard CSV file format
--     2. Internal RAW landing stage
--     3. RAW source tables
--     4. Operational ingestion audit tables
--     5. Snowpipes for file-to-RAW ingestion
--
-- Execution role
--   Run with a role that owns / can create objects in AUTOPULSE_AI.RAW and
--   AUTOPULSE_AI.OPS. In the AutoPulse RBAC model this is normally
--   AUTOPULSE_ETL_ENGINEER (or SYSADMIN during initial bootstrap).
--
-- Deployment principles
--   * Uses IF NOT EXISTS for persistent tables/stage/file format where possible
--     to avoid accidentally dropping production data during a rerun.
--   * RAW tables preserve source attributes and add the standard audit columns:
--         SOURCE_FILE_NAME
--         LOAD_TIMESTAMP
--   * Snowpipes explicitly list target columns to make source-to-target mapping
--     clear and resilient to later table evolution.
--   * File metadata is captured using METADATA$FILENAME.
--
-- IMPORTANT
--   AUTO_INGEST = TRUE on an INTERNAL named stage is currently dependent on
--   Snowflake account/cloud support. If the account does not support internal
--   stage auto-ingest, keep the same COPY definitions but use an external
--   cloud stage/event integration or another supported ingestion trigger.
--
-- NOTE
--   The SEMANTIC schema is intentionally NOT created in this RAW deployment
--   file. It belongs in the Cortex/semantic-layer deployment script.
-- ============================================================================


-- ============================================================================
-- 0. SESSION CONTEXT
-- ============================================================================

USE ROLE SYSADMIN;
USE DATABASE AUTOPULSE_AI;
USE SCHEMA RAW;
USE WAREHOUSE AUTOPULSE_WH;


-- ============================================================================
-- 1. STANDARD CSV FILE FORMAT
-- ============================================================================
-- Created before the stage because the stage references this named format.
-- ============================================================================

CREATE FILE FORMAT IF NOT EXISTS AUTOPULSE_AI.RAW.CSV_FILE_FORMAT
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_DELIMITER = ','
    TRIM_SPACE = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    EMPTY_FIELD_AS_NULL = TRUE
    NULL_IF = ('NULL', 'null', '')
    COMMENT = 'Standard CSV format for AutoPulse source files loaded into the RAW layer.';


-- ============================================================================
-- 2. INTERNAL LANDING STAGE
-- ============================================================================

CREATE STAGE IF NOT EXISTS AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE
    FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
    COMMENT = 'Internal landing stage for AutoPulse source CSV files prior to RAW ingestion.';


-- ============================================================================
-- 3. RAW TABLES
-- ============================================================================
-- All RAW tables include:
--   SOURCE_FILE_NAME : source file lineage
--   LOAD_TIMESTAMP   : Snowflake ingestion timestamp
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 3.1 BATTERY_COMPONENTS_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.BATTERY_COMPONENTS_RAW (
    BATTERY_TYPE NUMBER(1,0)
        COMMENT 'Battery type identifier associated with the anode, cathode, and electrolyte composition in the source dataset.',
    ANODE VARCHAR
        COMMENT 'Anode material and composition information reported for the battery type.',
    CATHODE VARCHAR
        COMMENT 'Cathode material and composition information reported for the battery type.',
    ELECTROLYTE VARCHAR
        COMMENT 'Electrolyte material and composition information reported for the battery type.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW battery component composition dataset. Preserves battery type, anode, cathode and electrolyte attributes before DQ, standardization, curation, risk scoring or AI processing.';


-- ----------------------------------------------------------------------------
-- 3.2 BATTERY_SUPPLIER_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.BATTERY_SUPPLIER_RAW (
    ID NUMBER(1,0)
        COMMENT 'Unique supplier identifier provided by the source BATTERY_SUPPLIER dataset.',
    NAME VARCHAR
        COMMENT 'Supplier name as provided by the source dataset.',
    STATE VARCHAR
        COMMENT 'State in which the supplier is located according to the source dataset.',
    LATITUDE NUMBER(6,4)
        COMMENT 'Latitude of the supplier location as provided by the source dataset.',
    LONGITUDE NUMBER(7,4)
        COMMENT 'Longitude of the supplier location as provided by the source dataset.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW battery supplier reference dataset. Preserves supplier identifiers and geographic attributes before DQ, curation, supplier risk scoring or AI processing.';


-- ----------------------------------------------------------------------------
-- 3.3 BATTERY_TYPE_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.BATTERY_TYPE_RAW (
    ID NUMBER(1,0)
        COMMENT 'Unique identifier for the battery type in the source BATTERY_TYPE dataset.',
    NAME VARCHAR
        COMMENT 'Battery type name associated with the source battery type identifier.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW battery type reference dataset. Preserves source battery type identifiers and names before DQ, curation, business modeling, risk scoring or AI processing.';


-- ----------------------------------------------------------------------------
-- 3.4 DATE_VALUES_YEAR_RAW
-- ----------------------------------------------------------------------------
-- DATE_VALUES remains DATE to preserve the current AutoPulse contract.
-- Source-date semantic corrections belong in the CLEAN normalization step.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.DATE_VALUES_YEAR_RAW (
    REC_COUNTS NUMBER(3,0)
        COMMENT 'Record sequence or count value provided by the source DATE_VALUES_YEAR dataset.',
    DATE_VALUES DATE
        COMMENT 'Date value provided by the source dataset; semantic date correction is performed downstream in CLEAN.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW date reference dataset. Preserves source date values before DQ and CLEAN-layer date normalization.';


-- ----------------------------------------------------------------------------
-- 3.5 DTC_BATTERY_ERROR_CODES_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.DTC_BATTERY_ERROR_CODES_RAW (
    ERROR_ID NUMBER(1,0)
        COMMENT 'Identifier for the battery diagnostic error record provided by the source dataset.',
    ERROR_CODE VARCHAR
        COMMENT 'Diagnostic trouble code associated with the battery error.',
    DESCRIPTION VARCHAR
        COMMENT 'Description of the battery diagnostic error associated with the error code.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW battery diagnostic trouble-code reference dataset before DQ, curation or business transformation.';


-- ----------------------------------------------------------------------------
-- 3.6 PART_BATTERY_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.PART_BATTERY_RAW (
    PART_ID NUMBER(3,0)
        COMMENT 'Unique part identifier provided by the PART_BATTERY source dataset.',
    AH NUMBER(3,0)
        COMMENT 'Battery amp-hour rating represented as a numeric value in the source dataset.',
    AMP_HOURS VARCHAR
        COMMENT 'Battery amp-hour specification as provided by the source, including AH notation.',
    TERMINAL VARCHAR
        COMMENT 'Battery terminal configuration provided by the source dataset.',
    SIZE_LENGTH_CM NUMBER(2,0)
        COMMENT 'Battery size length in centimeters as provided by the source dataset.',
    MFG_YEAR NUMBER(4,0)
        COMMENT 'Battery part manufacturing year.',
    PART_NUMBER VARCHAR
        COMMENT 'Battery part number used to identify the battery component.',
    TYPE NUMBER(1,0)
        COMMENT 'Battery type identifier associated with the part.',
    SUPPLIER NUMBER(1,0)
        COMMENT 'Supplier identifier associated with the battery part.',
    TEMP_RANGE_CELSIUS VARCHAR
        COMMENT 'Operating temperature range in Celsius as provided by the source.',
    TEMP_RANGE_FAHRENHEIT VARCHAR
        COMMENT 'Operating temperature range in Fahrenheit as provided by the source.',
    VOLTAGE_RANGE VARCHAR
        COMMENT 'Battery voltage operating range as provided by the source.',
    RECOMMENDED_CHARGING_VOLTAGE_RANGE VARCHAR
        COMMENT 'Recommended battery charging voltage range as provided by the source.',
    RECOMMENDED_CHARGING_CURRENT_RANGE VARCHAR
        COMMENT 'Recommended battery charging current range as provided by the source.',
    OVERCHARGE_PROTECTION NUMBER(1,0)
        COMMENT 'Indicator identifying whether overcharge protection is provided by the battery part.',
    OVERCURRENT_PROTECTION NUMBER(1,0)
        COMMENT 'Indicator identifying whether overcurrent protection is provided by the battery part.',
    DISCHARGE_CURRENT VARCHAR
        COMMENT 'Battery discharge current specification as provided by the source.',
    CUT_OFF_VOLTAGE VARCHAR
        COMMENT 'Battery cut-off voltage specification as provided by the source.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW battery part dataset. Preserves source specifications, supplier, operating ranges, charging characteristics and protection indicators before DQ and curation.';


-- ----------------------------------------------------------------------------
-- 3.7 STATES_AND_ABBREVIATIONS_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.STATES_AND_ABBREVIATIONS_RAW (
    ID NUMBER(2,0)
        COMMENT 'Identifier for the state record provided by the source dataset.',
    STATE VARCHAR
        COMMENT 'Full state name provided by the source dataset.',
    STATE_AB VARCHAR
        COMMENT 'Two-letter state abbreviation provided by the source dataset.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW state reference dataset. Preserves source state identifiers, names and abbreviations before DQ and curation.';


-- ----------------------------------------------------------------------------
-- 3.8 VEHICLES_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.VEHICLES_RAW (
    CAR_ID NUMBER(5,0)
        COMMENT 'Unique numeric identifier assigned to the vehicle record in the source dataset.',
    VIN VARCHAR
        COMMENT 'Vehicle Identification Number associated with the vehicle.',
    MODEL_YEAR NUMBER(4,0)
        COMMENT 'Model year of the vehicle.',
    VEHICLE_CONFIG VARCHAR
        COMMENT 'Vehicle configuration or body configuration reported by the source.',
    DOORS NUMBER(1,0)
        COMMENT 'Number of doors configured for the vehicle.',
    STATE VARCHAR
        COMMENT 'Full state name associated with the vehicle location.',
    STATE_AB VARCHAR
        COMMENT 'Two-character state abbreviation associated with the vehicle location.',
    COUNTRY VARCHAR
        COMMENT 'Country associated with the vehicle location.',
    PART_NUMBER VARCHAR
        COMMENT 'Part number associated with the battery/component installed in the vehicle.',
    BATTERY_SERIAL_NUMBER VARCHAR
        COMMENT 'Unique serial number identifying the battery associated with the vehicle.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW vehicle master dataset. Preserves vehicle, geographic, part and battery identifiers before DQ, curation, risk scoring or AI processing.';


-- ----------------------------------------------------------------------------
-- 3.9 VEHICLE_EVENTS_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.VEHICLE_EVENTS_RAW (
    CAR_ID NUMBER(4,0)
        COMMENT 'Vehicle identifier provided by the source vehicle event dataset.',
    VIN VARCHAR
        COMMENT 'Vehicle Identification Number associated with the event.',
    MODEL_YEAR NUMBER(4,0)
        COMMENT 'Model year of the vehicle.',
    VEHICLE_CONFIG VARCHAR
        COMMENT 'Vehicle configuration reported for the vehicle.',
    DOORS NUMBER(1,0)
        COMMENT 'Number of doors configured for the vehicle.',
    STATE VARCHAR
        COMMENT 'Full state name associated with the event location.',
    STATE_AB VARCHAR
        COMMENT 'Two-letter state abbreviation associated with the event location.',
    CITY VARCHAR
        COMMENT 'City associated with the event location.',
    COUNTRY VARCHAR
        COMMENT 'Country associated with the event location.',
    PART_NUMBER VARCHAR
        COMMENT 'Battery/component part number associated with the vehicle event.',
    BATTERY_SERIAL_NUMBER VARCHAR
        COMMENT 'Battery serial number associated with the vehicle event.',
    ZIP NUMBER(5,0)
        COMMENT 'ZIP code associated with the vehicle event location.',
    LONGITUDE NUMBER(8,6)
        COMMENT 'Longitude of the source location.',
    LATITUDE NUMBER(8,6)
        COMMENT 'Latitude of the source location.',
    DES_LONG NUMBER(8,6)
        COMMENT 'Destination longitude associated with the vehicle event.',
    DEST_LAT NUMBER(8,6)
        COMMENT 'Destination latitude associated with the vehicle event.',
    DIST_IN_M NUMBER(5,2)
        COMMENT 'Distance in miles associated with the source and destination locations.',
    RECORD_COUNTS NUMBER(3,0)
        COMMENT 'Record count or source record sequence value provided by the event dataset.',
    DATE_VALUES DATE
        COMMENT 'Date associated with the vehicle event; semantic normalization is performed downstream in CLEAN.',
    AVG_TEMP_F NUMBER(3,1)
        COMMENT 'Average temperature in degrees Fahrenheit associated with the event.',
    AVG_WIND_SPEED_MPH NUMBER(3,1)
        COMMENT 'Average wind speed in miles per hour associated with the event.',
    TOT_PRECIPITATION_IN NUMBER(3,2)
        COMMENT 'Total precipitation in inches associated with the event.',
    TOT_SNOWFALL_IN NUMBER(3,2)
        COMMENT 'Total snowfall in inches associated with the event.',
    DTC_ERROR_CODE NUMBER(1,0)
        COMMENT 'Indicator identifying whether a DTC error is associated with the event; 1 indicates error and 0 indicates no error.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW vehicle event dataset. Preserves vehicle, battery, geography, distance, date, weather and DTC attributes before DQ, CLEAN normalization, curation or risk scoring.';


-- ----------------------------------------------------------------------------
-- 3.10 WEATHER_DATA_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.WEATHER_DATA_RAW (
    POSTAL_CODE VARCHAR
        COMMENT 'Postal or ZIP code associated with the weather observation.',
    DATE_VALID_STD DATE
        COMMENT 'Date associated with the weather observation as supplied by the source.',
    AVG_TEMPERATURE_AIR_2M_F NUMBER(4,1)
        COMMENT 'Average air temperature at approximately 2 meters above ground level, in degrees Fahrenheit.',
    AVG_WIND_SPEED_10M_MPH NUMBER(3,1)
        COMMENT 'Average wind speed at approximately 10 meters above ground level, in miles per hour.',
    TOT_PRECIPITATION_IN NUMBER(4,2)
        COMMENT 'Total precipitation associated with the weather observation, in inches.',
    TOT_SNOWFALL_IN NUMBER(4,2)
        COMMENT 'Total snowfall associated with the weather observation, in inches.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW weather observation dataset. Preserves postal code, observation date, temperature, wind, precipitation and snowfall before DQ and curation.';


-- ----------------------------------------------------------------------------
-- 3.11 ZIP_CODE_INFO_RAW
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.RAW.ZIP_CODE_INFO_RAW (
    ZIP VARCHAR(5)
        COMMENT 'ZIP code stored as text in RAW to preserve leading zeros from the source.',
    LATITUDE NUMBER(17,15)
        COMMENT 'Latitude associated with the ZIP code location as provided by the source dataset.',
    LONGITUDE NUMBER(9,6)
        COMMENT 'Longitude associated with the ZIP code location as provided by the source dataset.',
    CITY VARCHAR
        COMMENT 'City associated with the ZIP code as provided by the source dataset.',
    STATE VARCHAR
        COMMENT 'Two-letter state abbreviation associated with the ZIP code as provided by the source dataset.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name captured from Snowflake file metadata at ingestion time.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the source record was ingested into the RAW layer.'
)
COMMENT = 'RAW ZIP-code geographic reference dataset before DQ, geographic enrichment and AI processing.';


-- ============================================================================
-- 4. OPERATIONAL INGESTION AUDIT TABLES
-- ============================================================================
-- These tables live in OPS, not RAW. They are retained here because they are
-- part of the ingestion deployment dependency.
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.OPS.DATA_LOAD_AUDIT (
    LOAD_ID VARCHAR(100)
        COMMENT 'Unique identifier for an individual source data load operation.',
    RUN_ID VARCHAR(100)
        COMMENT 'Identifier linking the load operation to the parent pipeline run.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Name of the source file being loaded.',
    SOURCE_STAGE VARCHAR(500)
        COMMENT 'Snowflake stage from which the source file was loaded.',
    TARGET_TABLE VARCHAR(200)
        COMMENT 'RAW table receiving the source data.',
    LOAD_STARTED_AT TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when loading of the source file started.',
    LOAD_COMPLETED_AT TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when loading of the source file completed.',
    STATUS VARCHAR(30)
        COMMENT 'Load status such as RUNNING, SUCCESS, PARTIAL or FAILED.',
    ROWS_PARSED NUMBER(38,0)
        COMMENT 'Number of source records parsed during the load.',
    ROWS_LOADED NUMBER(38,0)
        COMMENT 'Number of records successfully loaded into the target RAW table.',
    ROWS_REJECTED NUMBER(38,0)
        COMMENT 'Number of records rejected during source loading.',
    FIRST_ERROR_MESSAGE VARCHAR
        COMMENT 'First load error returned for the source file, when applicable.',
    CREATED_AT TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP()
        COMMENT 'Timestamp when the data-load audit record was created.'
)
COMMENT = 'Operational audit table for file-level RAW ingestion outcomes, row counts and load errors.';


CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.OPS.INGESTION_AUDIT (
    BATCH_ID VARCHAR
        COMMENT 'Unique identifier for a source ingestion batch.',
    SOURCE_FILE_NAME VARCHAR
        COMMENT 'Name of the source file received for ingestion.',
    SOURCE_SYSTEM VARCHAR
        COMMENT 'Originating source system or dataset.',
    FILE_ROW_COUNT NUMBER(38,0)
        COMMENT 'Number of data rows contained in the source file.',
    LOADED_ROW_COUNT NUMBER(38,0)
        COMMENT 'Number of rows successfully loaded into the RAW table.',
    LOAD_STATUS VARCHAR
        COMMENT 'Status of the ingestion operation such as STARTED, SUCCESS or FAILED.',
    LOAD_STARTED_AT TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when ingestion of the source file started.',
    LOAD_COMPLETED_AT TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when ingestion of the source file completed.',
    ERROR_COUNT NUMBER(38,0)
        COMMENT 'Number of errors encountered during ingestion.',
    ERROR_MESSAGE VARCHAR
        COMMENT 'Error details when the ingestion operation fails.',
    CREATED_AT TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP()
        COMMENT 'Timestamp when the ingestion audit record was created.'
)
COMMENT = 'Operational audit table for ingestion batches, row counts, status, timing and errors.';


CREATE TABLE IF NOT EXISTS AUTOPULSE_AI.OPS.PIPELINE_RUNS (
    RUN_ID VARCHAR(100)
        COMMENT 'Unique identifier for a complete pipeline execution.',
    PIPELINE_NAME VARCHAR(200)
        COMMENT 'Name of the pipeline being executed, such as RAW_INGESTION or DQ_PIPELINE.',
    PIPELINE_TYPE VARCHAR(50)
        COMMENT 'Pipeline type such as INGESTION, DQ, CLEAN, CURATED or AI.',
    STARTED_AT TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the pipeline execution started.',
    COMPLETED_AT TIMESTAMP_NTZ(9)
        COMMENT 'Timestamp when the pipeline execution completed.',
    STATUS VARCHAR(30)
        COMMENT 'Overall pipeline status such as RUNNING, SUCCESS, PARTIAL or FAILED.',
    TOTAL_ROWS_PROCESSED NUMBER(38,0)
        COMMENT 'Total number of source records processed during the pipeline execution.',
    TOTAL_ROWS_SUCCEEDED NUMBER(38,0)
        COMMENT 'Total number of records successfully processed.',
    TOTAL_ROWS_REJECTED NUMBER(38,0)
        COMMENT 'Total number of records rejected during the pipeline execution.',
    ERROR_MESSAGE VARCHAR
        COMMENT 'Pipeline-level error message when applicable.',
    CREATED_AT TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP()
        COMMENT 'Timestamp when the pipeline-run audit record was created.'
)
COMMENT = 'Operational run-control table containing one row per AutoPulse pipeline execution.';


-- ============================================================================
-- 5. SNOWPIPES
-- ============================================================================
-- Each pipe:
--   * isolates one source-file family through PATTERN
--   * maps source columns explicitly
--   * appends SOURCE_FILE_NAME and LOAD_TIMESTAMP
--
-- If a pipe already exists in an established environment, review before using
-- CREATE OR REPLACE because pipe replacement is a deployment operation.
-- For this NEW account build, CREATE OR REPLACE is intentional.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 5.1 BATTERY_COMPONENTS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_BATTERY_COMPONENTS
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests BATTERY_COMPONENTS CSV files into BATTERY_COMPONENTS_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.BATTERY_COMPONENTS_RAW
(
    BATTERY_TYPE,
    ANODE,
    CATHODE,
    ELECTROLYTE,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1,
        $2,
        $3,
        $4,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*BATTERY_COMPONENTS[.]csv';


-- ----------------------------------------------------------------------------
-- 5.2 BATTERY_SUPPLIER
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_BATTERY_SUPPLIER
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests BATTERY_SUPPLIER CSV files into BATTERY_SUPPLIER_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.BATTERY_SUPPLIER_RAW
(
    ID,
    NAME,
    STATE,
    LATITUDE,
    LONGITUDE,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2, $3, $4, $5,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*BATTERY_SUPPLIER[.]csv';


-- ----------------------------------------------------------------------------
-- 5.3 BATTERY_TYPE
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_BATTERY_TYPE
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests BATTERY_TYPE CSV files into BATTERY_TYPE_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.BATTERY_TYPE_RAW
(
    ID,
    NAME,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*BATTERY_TYPE[.]csv';


-- ----------------------------------------------------------------------------
-- 5.4 DATE_VALUES_YEAR
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_DATE_VALUES_YEAR
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests DATE_VALUES_YEAR CSV files into DATE_VALUES_YEAR_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.DATE_VALUES_YEAR_RAW
(
    REC_COUNTS,
    DATE_VALUES,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*DATE_VALUES_YEAR[.]csv';


-- ----------------------------------------------------------------------------
-- 5.5 DTC_BATTERY_ERROR_CODES
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_DTC_BATTERY_ERROR_CODES
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests DTC_BATTERY_ERROR_CODES CSV files into DTC_BATTERY_ERROR_CODES_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.DTC_BATTERY_ERROR_CODES_RAW
(
    ERROR_ID,
    ERROR_CODE,
    DESCRIPTION,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2, $3,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*DTC_BATTERY_ERROR_CODES[.]csv';


-- ----------------------------------------------------------------------------
-- 5.6 PART_BATTERY
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_PART_BATTERY
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests PART_BATTERY CSV files into PART_BATTERY_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.PART_BATTERY_RAW
(
    PART_ID,
    AH,
    AMP_HOURS,
    TERMINAL,
    SIZE_LENGTH_CM,
    MFG_YEAR,
    PART_NUMBER,
    TYPE,
    SUPPLIER,
    TEMP_RANGE_CELSIUS,
    TEMP_RANGE_FAHRENHEIT,
    VOLTAGE_RANGE,
    RECOMMENDED_CHARGING_VOLTAGE_RANGE,
    RECOMMENDED_CHARGING_CURRENT_RANGE,
    OVERCHARGE_PROTECTION,
    OVERCURRENT_PROTECTION,
    DISCHARGE_CURRENT,
    CUT_OFF_VOLTAGE,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2, $3, $4, $5, $6, $7, $8, $9,
        $10, $11, $12, $13, $14, $15, $16, $17, $18,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*PART_BATTERY[.]csv';


-- ----------------------------------------------------------------------------
-- 5.7 STATES_AND_ABBREVIATIONS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_STATES_AND_ABBREVIATIONS
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests STATES_AND_ABBREVIATIONS CSV files into STATES_AND_ABBREVIATIONS_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.STATES_AND_ABBREVIATIONS_RAW
(
    ID,
    STATE,
    STATE_AB,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2, $3,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*STATES_AND_ABBREVIATIONS[.]csv';


-- ----------------------------------------------------------------------------
-- 5.8 VEHICLES
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_VEHICLES
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests VEHICLES.csv into VEHICLES_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.VEHICLES_RAW
(
    CAR_ID,
    VIN,
    MODEL_YEAR,
    VEHICLE_CONFIG,
    DOORS,
    STATE,
    STATE_AB,
    COUNTRY,
    PART_NUMBER,
    BATTERY_SERIAL_NUMBER,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*[/]VEHICLES[.]csv';


-- ----------------------------------------------------------------------------
-- 5.9 VEHICLE_EVENTS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_VEHICLE_EVENTS
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests vehicle distance/date/weather/DTC files into VEHICLE_EVENTS_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.VEHICLE_EVENTS_RAW
(
    CAR_ID,
    VIN,
    MODEL_YEAR,
    VEHICLE_CONFIG,
    DOORS,
    STATE,
    STATE_AB,
    CITY,
    COUNTRY,
    PART_NUMBER,
    BATTERY_SERIAL_NUMBER,
    ZIP,
    LONGITUDE,
    LATITUDE,
    DES_LONG,
    DEST_LAT,
    DIST_IN_M,
    RECORD_COUNTS,
    DATE_VALUES,
    AVG_TEMP_F,
    AVG_WIND_SPEED_MPH,
    TOT_PRECIPITATION_IN,
    TOT_SNOWFALL_IN,
    DTC_ERROR_CODE,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
        $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*VEHICLES_ZIPCODES_DISTANCES_DATES_WEATHER_DTC.*[.]csv';


-- ----------------------------------------------------------------------------
-- 5.10 WEATHER_DATA
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_WEATHER_DATA
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests WEATHER_DATA CSV files into WEATHER_DATA_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.WEATHER_DATA_RAW
(
    POSTAL_CODE,
    DATE_VALID_STD,
    AVG_TEMPERATURE_AIR_2M_F,
    AVG_WIND_SPEED_10M_MPH,
    TOT_PRECIPITATION_IN,
    TOT_SNOWFALL_IN,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2, $3, $4, $5, $6,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*WEATHER_DATA[.]csv';


-- ----------------------------------------------------------------------------
-- 5.11 ZIP_CODE_INFO
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PIPE AUTOPULSE_AI.RAW.PIPE_ZIP_CODE_INFO
    AUTO_INGEST = TRUE
    COMMENT = 'Auto-ingests ZIP_CODE_INFO CSV files into ZIP_CODE_INFO_RAW.'
AS
COPY INTO AUTOPULSE_AI.RAW.ZIP_CODE_INFO_RAW
(
    ZIP,
    LATITUDE,
    LONGITUDE,
    CITY,
    STATE,
    SOURCE_FILE_NAME,
    LOAD_TIMESTAMP
)
FROM (
    SELECT
        $1, $2, $3, $4, $5,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE/
)
FILE_FORMAT = (FORMAT_NAME = 'AUTOPULSE_AI.RAW.CSV_FILE_FORMAT')
PATTERN = '.*ZIP_CODE_INFO[.]csv';


-- ============================================================================
-- 6. POST-DEPLOYMENT VERIFICATION
-- ============================================================================

SHOW FILE FORMATS LIKE 'CSV_FILE_FORMAT' IN SCHEMA AUTOPULSE_AI.RAW;

SHOW STAGES LIKE 'AUTOPULSE_RAW_STAGE' IN SCHEMA AUTOPULSE_AI.RAW;

SHOW TABLES IN SCHEMA AUTOPULSE_AI.RAW;

SHOW TABLES IN SCHEMA AUTOPULSE_AI.OPS;

SHOW PIPES IN SCHEMA AUTOPULSE_AI.RAW;

-- Optional after files are uploaded:
-- LIST @AUTOPULSE_AI.RAW.AUTOPULSE_RAW_STAGE;

-- Optional pipe-health check after ingestion begins:
-- SELECT SYSTEM$PIPE_STATUS('AUTOPULSE_AI.RAW.PIPE_VEHICLES');


-- ============================================================================
-- END OF 02_RAW_INGESTION_SETUP.sql
-- ============================================================================
