-- ============================================================================
-- AUTOPULSE AI | CLEAN LAYER
-- Production-grade CLEAN table definitions
-- ============================================================================
--
-- Purpose:
--   Store DQ-approved/processed records from AUTOPULSE_AI.RAW.
--
-- Lineage contract:
--   SOURCE_FILE_NAME and LOAD_TIMESTAMP are intentionally carried from RAW
--   into CLEAN so source-file and ingestion-time lineage are preserved.
--
-- Important:
--   RUN_DQ_FW logic does NOT need to be changed for these definitions.
--   The CLEAN tables retain the RAW column order so the procedure's SELECT *
--   loads remain compatible.
--
-- Deployment:
--   Run this script with the required CREATE TABLE privileges on
--   AUTOPULSE_AI.CLEAN.
--
-- ============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE AUTOPULSE_WH;

-- ============================================================================
-- 1. BATTERY_COMPONENTS
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.BATTERY_COMPONENTS_CLEAN (
    BATTERY_TYPE NUMBER(1,0)
        COMMENT 'Battery type identifier associated with the anode, cathode, and electrolyte composition in the source dataset.',
    ANODE VARCHAR(16777216)
        COMMENT 'Anode material and composition information reported for the battery type.',
    CATHODE VARCHAR(16777216)
        COMMENT 'Cathode material and composition information reported for the battery type.',
    ELECTROLYTE VARCHAR(16777216)
        COMMENT 'Electrolyte material and composition information reported for the battery type.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- 2. BATTERY_SUPPLIER
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.BATTERY_SUPPLIER_CLEAN (
    ID NUMBER(1,0)
        COMMENT 'Unique supplier identifier provided by the source BATTERY_SUPPLIER dataset.',
    NAME VARCHAR(16777216)
        COMMENT 'Supplier name as provided by the source dataset.',
    STATE VARCHAR(16777216)
        COMMENT 'State in which the supplier is located according to the source dataset.',
    LATITUDE NUMBER(6,4)
        COMMENT 'Latitude of the supplier location as provided by the source dataset.',
    LONGITUDE NUMBER(7,4)
        COMMENT 'Longitude of the supplier location as provided by the source dataset.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- 3. BATTERY_TYPE
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.BATTERY_TYPE_CLEAN (
    ID NUMBER(1,0)
        COMMENT 'Unique identifier for the battery type in the source BATTERY_TYPE dataset.',
    NAME VARCHAR(16777216)
        COMMENT 'Battery type name associated with the battery type identifier in the source dataset.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- 4. DATE_VALUES_YEAR
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.DATE_VALUES_YEAR_CLEAN (
    DATE_VALUES DATE
        COMMENT 'Date value from the source dataset used for event/date processing.',
    YEAR NUMBER(4,0)
        COMMENT 'Year value associated with the source date record.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- 5. DTC_BATTERY_ERROR_CODES
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.DTC_BATTERY_ERROR_CODES_CLEAN (
    ERROR_ID NUMBER(1,0)
        COMMENT 'Identifier for the battery diagnostic error record provided by the source dataset.',
    ERROR_CODE VARCHAR(16777216)
        COMMENT 'Diagnostic trouble code associated with the battery error.',
    DESCRIPTION VARCHAR(16777216)
        COMMENT 'Description of the battery diagnostic error associated with the error code.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- 6. PART_BATTERY
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.PART_BATTERY_CLEAN (
    PART_ID NUMBER(3,0)
        COMMENT 'Unique part identifier provided by the PART_BATTERY source dataset.',
    AH NUMBER(3,0)
        COMMENT 'Battery amp-hour rating represented as a numeric value in the source dataset.',
    AMP_HOURS VARCHAR(16777216)
        COMMENT 'Battery amp-hour specification as provided by the source, including the AH notation.',
    TERMINAL VARCHAR(16777216)
        COMMENT 'Battery terminal configuration provided by the source dataset.',
    SIZE_LENGTH_CM NUMBER(2,0)
        COMMENT 'Battery size length in centimeters as provided by the source dataset.',
    MFG_YEAR NUMBER(4,0)
        COMMENT 'Battery part manufacturing year.',
    PART_NUMBER VARCHAR(16777216)
        COMMENT 'Battery part number used to identify the battery component.',
    TYPE NUMBER(1,0)
        COMMENT 'Battery type identifier associated with the part.',
    SUPPLIER NUMBER(1,0)
        COMMENT 'Supplier identifier associated with the battery part.',
    TEMP_RANGE_CELSIUS VARCHAR(16777216)
        COMMENT 'Operating temperature range in Celsius as provided by the source.',
    TEMP_RANGE_FAHRENHEIT VARCHAR(16777216)
        COMMENT 'Operating temperature range in Fahrenheit as provided by the source.',
    VOLTAGE_RANGE VARCHAR(16777216)
        COMMENT 'Battery voltage operating range as provided by the source.',
    RECOMMENDED_CHARGING_VOLTAGE_RANGE VARCHAR(16777216)
        COMMENT 'Recommended battery charging voltage range as provided by the source.',
    RECOMMENDED_CHARGING_CURRENT_RANGE VARCHAR(16777216)
        COMMENT 'Recommended battery charging current range as provided by the source.',
    OVERCHARGE_PROTECTION NUMBER(1,0)
        COMMENT 'Indicator identifying whether overcharge protection is provided by the battery part.',
    OVERCURRENT_PROTECTION NUMBER(1,0)
        COMMENT 'Indicator identifying whether overcurrent protection is provided by the battery part.',
    DISCHARGE_CURRENT VARCHAR(16777216)
        COMMENT 'Battery discharge current specification as provided by the source.',
    CUT_OFF_VOLTAGE VARCHAR(16777216)
        COMMENT 'Battery cut-off voltage specification as provided by the source.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- 7. STATES_AND_ABBREVIATIONS
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.STATES_AND_ABBREVIATIONS_CLEAN (
    ID NUMBER(2,0)
        COMMENT 'Identifier for the state record provided by the source STATES_AND_ABBREVIATIONS dataset.',
    STATE VARCHAR(16777216)
        COMMENT 'Full state name provided by the source dataset.',
    STATE_AB VARCHAR(16777216)
        COMMENT 'Two-letter state abbreviation provided by the source dataset.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- 8. VEHICLES
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.VEHICLES_CLEAN (
    CAR_ID NUMBER(5,0)
        COMMENT 'Unique numeric identifier assigned to the vehicle record in the source VEHICLES dataset.',
    VIN VARCHAR(16777216)
        COMMENT 'Vehicle Identification Number associated with the vehicle.',
    MODEL_YEAR NUMBER(4,0)
        COMMENT 'Model year of the vehicle.',
    VEHICLE_CONFIG VARCHAR(16777216)
        COMMENT 'Vehicle configuration or body configuration reported by the source.',
    DOORS NUMBER(1,0)
        COMMENT 'Number of doors configured for the vehicle.',
    STATE VARCHAR(16777216)
        COMMENT 'Full state name associated with the vehicle location.',
    STATE_AB VARCHAR(16777216)
        COMMENT 'Two-character state abbreviation associated with the vehicle location.',
    COUNTRY VARCHAR(16777216)
        COMMENT 'Country associated with the vehicle location.',
    PART_NUMBER VARCHAR(16777216)
        COMMENT 'Part number associated with the battery/component installed in the vehicle.',
    BATTERY_SERIAL_NUMBER VARCHAR(16777216)
        COMMENT 'Unique serial number identifying the battery associated with the vehicle.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- 9. VEHICLE_EVENTS
-- ============================================================================
CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.VEHICLE_EVENTS_CLEAN (
    CAR_ID NUMBER(4,0),
    VIN VARCHAR(16777216),
    MODEL_YEAR NUMBER(4,0),
    VEHICLE_CONFIG VARCHAR(16777216),
    DOORS NUMBER(1,0),
    STATE VARCHAR(16777216),
    STATE_AB VARCHAR(16777216),
    CITY VARCHAR(16777216),
    COUNTRY VARCHAR(16777216),
    PART_NUMBER VARCHAR(16777216),
    BATTERY_SERIAL_NUMBER VARCHAR(16777216),
    ZIP NUMBER(5,0),
    LONGITUDE NUMBER(8,6),
    LATITUDE NUMBER(8,6),
    DES_LONG NUMBER(8,6),
    DEST_LAT NUMBER(8,6),
    DIST_IN_M NUMBER(5,2),
    RECORD_COUNTS NUMBER(3,0),
    DATE_VALUES DATE,
    AVG_TEMP_F NUMBER(3,1),
    AVG_WIND_SPEED_MPH NUMBER(3,1),
    TOT_PRECIPITATION_IN NUMBER(3,2),
    TOT_SNOWFALL_IN NUMBER(3,2),
    DTC_ERROR_CODE NUMBER(1,0),
    SOURCE_FILE_NAME VARCHAR(500),
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
);


-- ============================================================================
-- 10. WEATHER_DATA
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.WEATHER_DATA_CLEAN (
    POSTAL_CODE VARCHAR(16777216)
        COMMENT 'Postal or ZIP code associated with the weather observation.',
    DATE_VALID_STD DATE
        COMMENT 'Standardized date associated with the weather observation.',
    AVG_TEMPERATURE_AIR_2M_F NUMBER(4,1)
        COMMENT 'Average air temperature at approximately 2 meters above ground level, in degrees Fahrenheit.',
    AVG_WIND_SPEED_10M_MPH NUMBER(3,1)
        COMMENT 'Average wind speed at approximately 10 meters above ground level, in miles per hour.',
    TOT_PRECIPITATION_IN NUMBER(4,2)
        COMMENT 'Total precipitation associated with the weather observation, in inches.',
    TOT_SNOWFALL_IN NUMBER(4,2)
        COMMENT 'Total snowfall associated with the weather observation, in inches.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- 11. ZIP_CODE_INFO
-- ============================================================================

CREATE OR REPLACE TABLE AUTOPULSE_AI.CLEAN.ZIP_CODE_INFO_CLEAN (
    ZIP VARCHAR(5)
        COMMENT 'ZIP code associated with the geographic location. Stored as text to preserve leading zeros present in the source data.',
    LATITUDE NUMBER(17,15)
        COMMENT 'Latitude associated with the ZIP code location as provided by the source dataset.',
    LONGITUDE NUMBER(9,6)
        COMMENT 'Longitude associated with the ZIP code location as provided by the source dataset.',
    CITY VARCHAR(16777216)
        COMMENT 'City associated with the ZIP code as provided by the source dataset.',
    STATE VARCHAR(16777216)
        COMMENT 'Two-letter state abbreviation associated with the ZIP code as provided by the source dataset.',
    SOURCE_FILE_NAME VARCHAR(500)
        COMMENT 'Source file name inherited from the RAW ingestion layer for record-level data lineage.',
    LOAD_TIMESTAMP TIMESTAMP_NTZ(9)
        COMMENT 'RAW ingestion timestamp used for record lineage and processing-date filtering.'
);


-- ============================================================================
-- POST-DEPLOYMENT VERIFICATION
-- ============================================================================

SHOW TABLES IN SCHEMA AUTOPULSE_AI.CLEAN;

SELECT
    TABLE_NAME,
    ROW_COUNT
FROM AUTOPULSE_AI.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CLEAN'
ORDER BY TABLE_NAME;

-- Verify lineage columns exist on every CLEAN table.
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    ORDINAL_POSITION,
    DATA_TYPE
FROM AUTOPULSE_AI.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'CLEAN'
  AND COLUMN_NAME IN ('SOURCE_FILE_NAME', 'LOAD_TIMESTAMP')
ORDER BY TABLE_NAME, ORDINAL_POSITION;
