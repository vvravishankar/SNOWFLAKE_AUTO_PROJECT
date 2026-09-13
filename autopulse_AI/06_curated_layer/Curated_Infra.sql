-- ============================================================================
-- AUTOPULSE AI | CURATED LAYER
-- Production Dynamic Table Pipeline
-- ============================================================================
--
-- Architecture:
--   RAW -> DQ Streams/Tasks -> CLEAN -> CURATED Dynamic Tables
--
-- Dynamic table dependency chain:
--   CLEAN
--      |
--      +--> VEHICLE_BATTERY_360
--                |
--                +--> VEHICLE_EVENT_CONTEXT
--                           |
--                           +--> VEHICLE_BATTERY_RCA
--                                      |
--                                      +--> VEHICLE_BATTERY_PREDICTION
--
-- Production design:
--   * Curated datasets are maintained declaratively by Snowflake.
--   * Existing INSERT statements are replaced by SELECT definitions.
--   * REFRESH_MODE = FULL is used intentionally because the supplied logic
--     contains CURRENT_TIMESTAMP() in the SELECT list and complex joins/
--     aggregations/window functions. This preserves the existing output logic
--     while avoiding an unsupported incremental-refresh definition.
--   * TARGET_LAG is staged through the dependency chain.
--   * Existing regular CURATED tables must be dropped before these dynamic
--     tables are created.
--
-- IMPORTANT:
--   The original VEHICLE_BATTERY_360 DDL declared CITY, but its INSERT/SELECT
--   logic did not populate CITY. To preserve the supplied transformation
--   logic exactly, CITY is not added to the dynamic-table projection here.
--
-- ============================================================================


-- ============================================================================
-- STEP 1: REMOVE EXISTING REGULAR CURATED TABLES
-- ============================================================================
--
-- Do NOT use CASCADE here. If a semantic view, agent, or other object depends
-- on one of these tables, Snowflake should stop and expose that dependency
-- rather than silently removing downstream objects.
--
-- ============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE AUTOPULSE_WH;

DROP TABLE IF EXISTS AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_PREDICTION;
DROP TABLE IF EXISTS AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_RCA;
DROP TABLE IF EXISTS AUTOPULSE_AI.CURATED.VEHICLE_EVENT_CONTEXT;
DROP TABLE IF EXISTS AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_360;


-- ============================================================================
-- STEP 2: VEHICLE_BATTERY_360
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_360
TARGET_LAG = '1 MINUTES'
WAREHOUSE = AUTOPULSE_WH
REFRESH_MODE = FULL
AS
SELECT
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
    BATTERY_AH,
    AMP_HOURS,
    TERMINAL,
    SIZE_LENGTH_CM,
    MFG_YEAR,
    BATTERY_TYPE,
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
    VEHICLE_AGE,
    BATTERY_AGE,
    CREATED_AT
FROM
(
    SELECT
        v.CAR_ID,
        v.VIN,
        v.MODEL_YEAR,
        v.VEHICLE_CONFIG,
        v.DOORS,
        v.STATE,
        v.STATE_AB,
        v.COUNTRY,
        v.PART_NUMBER,
        v.BATTERY_SERIAL_NUMBER,

        p.AH AS BATTERY_AH,
        p.AMP_HOURS,
        p.TERMINAL,
        p.SIZE_LENGTH_CM,
        p.MFG_YEAR,

        bt.NAME AS BATTERY_TYPE,
        bs.NAME AS SUPPLIER,

        p.TEMP_RANGE_CELSIUS,
        p.TEMP_RANGE_FAHRENHEIT,
        p.VOLTAGE_RANGE,
        p.RECOMMENDED_CHARGING_VOLTAGE_RANGE,
        p.RECOMMENDED_CHARGING_CURRENT_RANGE,
        p.OVERCHARGE_PROTECTION,
        p.OVERCURRENT_PROTECTION,
        p.DISCHARGE_CURRENT,
        p.CUT_OFF_VOLTAGE,

        YEAR(CURRENT_DATE()) - v.MODEL_YEAR AS VEHICLE_AGE,
        YEAR(CURRENT_DATE()) - p.MFG_YEAR AS BATTERY_AGE,

        CURRENT_TIMESTAMP() AS CREATED_AT,

        ROW_NUMBER() OVER
        (
            PARTITION BY v.CAR_ID, v.PART_NUMBER
            ORDER BY
                p.MFG_YEAR DESC,
                p.AH DESC,
                p.PART_ID ASC
        ) AS RN

    FROM AUTOPULSE_AI.CLEAN.VEHICLES_CLEAN v

    LEFT JOIN AUTOPULSE_AI.CLEAN.PART_BATTERY_CLEAN p
        ON v.PART_NUMBER = p.PART_NUMBER

    LEFT JOIN AUTOPULSE_AI.CLEAN.BATTERY_TYPE_CLEAN bt
        ON p.TYPE = bt.ID

    LEFT JOIN AUTOPULSE_AI.CLEAN.BATTERY_SUPPLIER_CLEAN bs
        ON p.SUPPLIER = bs.ID
)
WHERE RN = 1;


-- ============================================================================
-- STEP 3: VEHICLE_EVENT_CONTEXT
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_EVENT_CONTEXT
TARGET_LAG = '2 MINUTES'
WAREHOUSE = AUTOPULSE_WH
REFRESH_MODE = FULL
AS
SELECT
    e.CAR_ID,
    e.VIN,
    e.MODEL_YEAR,
    e.VEHICLE_CONFIG,
    e.DOORS,
    e.STATE,
    e.STATE_AB,
    e.CITY,
    e.COUNTRY,
    TO_VARCHAR(e.ZIP) AS ZIP,

    e.LONGITUDE,
    e.LATITUDE,
    e.DES_LONG,
    e.DEST_LAT,
    e.DIST_IN_M,

    e.PART_NUMBER,
    e.BATTERY_SERIAL_NUMBER,

    b.BATTERY_AH,
    b.AMP_HOURS,
    b.BATTERY_TYPE,
    b.SUPPLIER,
    b.MFG_YEAR,
    b.TERMINAL,
    b.SIZE_LENGTH_CM,

    b.TEMP_RANGE_CELSIUS,
    b.TEMP_RANGE_FAHRENHEIT,
    b.VOLTAGE_RANGE,
    b.RECOMMENDED_CHARGING_VOLTAGE_RANGE,
    b.RECOMMENDED_CHARGING_CURRENT_RANGE,
    b.OVERCHARGE_PROTECTION,
    b.OVERCURRENT_PROTECTION,
    b.DISCHARGE_CURRENT,
    b.CUT_OFF_VOLTAGE,

    e.DATE_VALUES,
    e.AVG_TEMP_F,
    e.AVG_WIND_SPEED_MPH,
    e.TOT_PRECIPITATION_IN,
    e.TOT_SNOWFALL_IN,

    e.DTC_ERROR_CODE,
    d.ERROR_CODE,
    d.DESCRIPTION,

    z.CITY AS ZIP_CITY,
    z.STATE AS ZIP_STATE,
    z.LATITUDE AS ZIP_LATITUDE,
    z.LONGITUDE AS ZIP_LONGITUDE,

    CURRENT_TIMESTAMP() AS CREATED_AT

FROM AUTOPULSE_AI.CLEAN.VEHICLE_EVENTS_CLEAN e

LEFT JOIN (
    SELECT *
    FROM AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_360
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CAR_ID, PART_NUMBER
        ORDER BY MFG_YEAR DESC, BATTERY_AH DESC
    ) = 1
) b
    ON e.CAR_ID = b.CAR_ID
   AND e.PART_NUMBER = b.PART_NUMBER

LEFT JOIN AUTOPULSE_AI.CLEAN.ZIP_CODE_INFO_CLEAN z
    ON TO_VARCHAR(e.ZIP) = z.ZIP

LEFT JOIN AUTOPULSE_AI.CLEAN.DTC_BATTERY_ERROR_CODES_CLEAN d
    ON TO_VARCHAR(e.DTC_ERROR_CODE) = d.ERROR_ID;


-- ============================================================================
-- STEP 4: VEHICLE_BATTERY_RCA
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_RCA
TARGET_LAG = '3 MINUTES'
WAREHOUSE = AUTOPULSE_WH
REFRESH_MODE = FULL
AS
SELECT
    E.CAR_ID,
    E.VIN,
    E.PART_NUMBER,
    E.BATTERY_SERIAL_NUMBER,

    MAX(P.AH) AS BATTERY_AH,
    MAX(BT.NAME) AS BATTERY_TYPE,
    MAX(S.NAME) AS SUPPLIER,

    MAX(P.MFG_YEAR) AS MFG_YEAR,

    YEAR(MAX(E.DATE_VALUES)) - MAX(P.MFG_YEAR)
        AS BATTERY_AGE,

    YEAR(MAX(E.DATE_VALUES)) - MAX(E.MODEL_YEAR)
        AS VEHICLE_AGE,

    COUNT(*) AS TOTAL_EVENTS,

    SUM(
        CASE
            WHEN E.DTC_ERROR_CODE = 1 THEN 1
            ELSE 0
        END
    ) AS DTC_ERROR_EVENTS,

    ROUND(
        100.0 *
        SUM(
            CASE
                WHEN E.DTC_ERROR_CODE = 1 THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS ERROR_RATE_PCT,

    MIN(E.DATE_VALUES) AS FIRST_EVENT_DATE,
    MAX(E.DATE_VALUES) AS LAST_EVENT_DATE,

    SUM(E.DIST_IN_M) AS TOTAL_DISTANCE_MILES,

    ROUND(AVG(E.DIST_IN_M), 2)
        AS AVG_DISTANCE_MILES,

    ROUND(AVG(E.AVG_TEMP_F), 2)
        AS AVG_TEMP_F,

    ROUND(MIN(E.AVG_TEMP_F), 2)
        AS MIN_TEMP_F,

    ROUND(MAX(E.AVG_TEMP_F), 2)
        AS MAX_TEMP_F,

    ROUND(AVG(E.AVG_WIND_SPEED_MPH), 2)
        AS AVG_WIND_SPEED_MPH,

    ROUND(SUM(E.TOT_PRECIPITATION_IN), 2)
        AS TOTAL_PRECIPITATION_IN,

    ROUND(SUM(E.TOT_SNOWFALL_IN), 2)
        AS TOTAL_SNOWFALL_IN,

    CURRENT_TIMESTAMP() AS CREATED_AT

FROM AUTOPULSE_AI.CURATED.VEHICLE_EVENT_CONTEXT E

LEFT JOIN AUTOPULSE_AI.CLEAN.PART_BATTERY_CLEAN P
    ON E.PART_NUMBER = P.PART_NUMBER

LEFT JOIN AUTOPULSE_AI.CLEAN.BATTERY_TYPE_CLEAN BT
    ON P.TYPE = BT.ID

LEFT JOIN AUTOPULSE_AI.CLEAN.BATTERY_SUPPLIER_CLEAN S
    ON P.SUPPLIER = S.ID

GROUP BY
    E.CAR_ID,
    E.VIN,
    E.PART_NUMBER,
    E.BATTERY_SERIAL_NUMBER;


-- ============================================================================
-- STEP 5: VEHICLE_BATTERY_PREDICTION
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_PREDICTION
TARGET_LAG = '4 MINUTES'
WAREHOUSE = AUTOPULSE_WH
REFRESH_MODE = FULL
AS
SELECT
    R.CAR_ID,
    R.VIN,
    R.PART_NUMBER,
    R.BATTERY_SERIAL_NUMBER,

    CURRENT_DATE() AS PREDICTION_DATE,
    CURRENT_TIMESTAMP() AS PREDICTION_TIMESTAMP,

    CASE
        WHEN R.DTC_ERROR_EVENTS >= 3
             AND R.ERROR_RATE_PCT >= 75
            THEN 90.00

        WHEN R.DTC_ERROR_EVENTS >= 2
             AND R.ERROR_RATE_PCT >= 50
            THEN 70.00

        WHEN R.DTC_ERROR_EVENTS >= 1
             AND R.ERROR_RATE_PCT >= 25
            THEN 45.00

        WHEN R.DTC_ERROR_EVENTS >= 1
            THEN 25.00

        ELSE 5.00
    END AS FAILURE_PROBABILITY_PCT,

    CASE
        WHEN R.DTC_ERROR_EVENTS >= 3
             AND R.ERROR_RATE_PCT >= 75
            THEN 1

        WHEN R.DTC_ERROR_EVENTS >= 2
             AND R.ERROR_RATE_PCT >= 50
            THEN 1

        ELSE 0
    END AS PREDICTED_FAILURE_FLAG,

    CASE
        WHEN R.DTC_ERROR_EVENTS >= 3
             AND R.ERROR_RATE_PCT >= 75
            THEN 'CRITICAL'

        WHEN R.DTC_ERROR_EVENTS >= 2
             AND R.ERROR_RATE_PCT >= 50
            THEN 'HIGH'

        WHEN R.DTC_ERROR_EVENTS >= 1
             AND R.ERROR_RATE_PCT >= 25
            THEN 'MEDIUM'

        ELSE 'LOW'
    END AS RISK_LEVEL,

    CASE
        WHEN R.DTC_ERROR_EVENTS >= 3
             AND R.ERROR_RATE_PCT >= 75
            THEN 30

        WHEN R.DTC_ERROR_EVENTS >= 2
             AND R.ERROR_RATE_PCT >= 50
            THEN 60

        WHEN R.DTC_ERROR_EVENTS >= 1
             AND R.ERROR_RATE_PCT >= 25
            THEN 120

        ELSE 365
    END AS PREDICTED_FAILURE_DAYS,

    R.BATTERY_AGE,
    R.VEHICLE_AGE,
    R.TOTAL_EVENTS,
    R.DTC_ERROR_EVENTS,
    R.ERROR_RATE_PCT,
    R.TOTAL_DISTANCE_MILES,
    R.AVG_TEMP_F,

    NULL AS RCA_PRIMARY_CAUSE,
    NULL AS RCA_SEVERITY,

    'RULE_BASED_BATTERY_RISK' AS MODEL_NAME,
    'V2.0' AS MODEL_VERSION,

    CURRENT_TIMESTAMP() AS CREATED_AT

FROM AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_RCA R;


-- ============================================================================
-- STEP 6: VERIFICATION
-- ============================================================================

SHOW DYNAMIC TABLES IN SCHEMA AUTOPULSE_AI.CURATED;

SELECT
    TABLE_NAME,
    TABLE_TYPE
FROM AUTOPULSE_AI.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CURATED'
ORDER BY TABLE_NAME;

-- Detailed dynamic-table status.
SHOW DYNAMIC TABLES LIKE 'VEHICLE_BATTERY_360'
    IN SCHEMA AUTOPULSE_AI.CURATED;

SHOW DYNAMIC TABLES LIKE 'VEHICLE_EVENT_CONTEXT'
    IN SCHEMA AUTOPULSE_AI.CURATED;

SHOW DYNAMIC TABLES LIKE 'VEHICLE_BATTERY_RCA'
    IN SCHEMA AUTOPULSE_AI.CURATED;

SHOW DYNAMIC TABLES LIKE 'VEHICLE_BATTERY_PREDICTION'
    IN SCHEMA AUTOPULSE_AI.CURATED;


-- ============================================================================
-- OPERATIONS
-- ============================================================================
--
-- Suspend:
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_360 SUSPEND;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_EVENT_CONTEXT SUSPEND;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_RCA SUSPEND;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_PREDICTION SUSPEND;
--
-- Resume:
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_360 RESUME;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_EVENT_CONTEXT RESUME;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_RCA RESUME;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_PREDICTION RESUME;
--
-- Manual refresh:
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_360 REFRESH;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_EVENT_CONTEXT REFRESH;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_RCA REFRESH;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_PREDICTION REFRESH;
--   ALTER DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_QUALITY_SCORECARD REFRESH;
--
-- ============================================================================


-- ============================================================================
-- STEP 7: VEHICLE_QUALITY_SCORECARD
-- ============================================================================
-- Consumed by the Streamlit dashboard Vehicle Quality page.
-- Derives a 0-100 quality score and A-F grade from RCA + Prediction data.
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE AUTOPULSE_AI.CURATED.VEHICLE_QUALITY_SCORECARD
TARGET_LAG = '5 MINUTES'
WAREHOUSE = AUTOPULSE_WH
REFRESH_MODE = FULL
AS
SELECT
    P.CAR_ID,
    P.VIN,
    R.PART_NUMBER,
    R.BATTERY_SERIAL_NUMBER,
    B.STATE,
    R.BATTERY_TYPE,
    R.SUPPLIER,
    R.MFG_YEAR,
    R.BATTERY_AGE,
    R.VEHICLE_AGE,
    R.TOTAL_EVENTS,
    R.DTC_ERROR_EVENTS,
    R.ERROR_RATE_PCT,
    R.AVG_TEMP_F,
    R.TOTAL_DISTANCE_MILES,
    P.FAILURE_PROBABILITY_PCT,
    P.PREDICTED_FAILURE_FLAG,
    P.RISK_LEVEL,
    P.PREDICTED_FAILURE_DAYS,

    -- Quality score: 100 minus penalty factors
    GREATEST(0, LEAST(100, ROUND(
        100
        - (COALESCE(R.ERROR_RATE_PCT, 0) * 0.5)
        - (CASE WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 3 THEN 25
                WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 2 THEN 15
                WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 1 THEN 5
                ELSE 0 END)
        - (CASE WHEN COALESCE(R.BATTERY_AGE, 0) >= 10 THEN 10
                WHEN COALESCE(R.BATTERY_AGE, 0) >= 5 THEN 5
                ELSE 0 END)
        - (CASE WHEN COALESCE(R.AVG_TEMP_F, 60) < 20 OR COALESCE(R.AVG_TEMP_F, 60) > 100 THEN 5
                ELSE 0 END)
    , 1))) AS QUALITY_SCORE,

    -- Letter grade
    CASE
        WHEN GREATEST(0, LEAST(100, ROUND(
            100
            - (COALESCE(R.ERROR_RATE_PCT, 0) * 0.5)
            - (CASE WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 3 THEN 25
                    WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 2 THEN 15
                    WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 1 THEN 5
                    ELSE 0 END)
            - (CASE WHEN COALESCE(R.BATTERY_AGE, 0) >= 10 THEN 10
                    WHEN COALESCE(R.BATTERY_AGE, 0) >= 5 THEN 5
                    ELSE 0 END)
            - (CASE WHEN COALESCE(R.AVG_TEMP_F, 60) < 20 OR COALESCE(R.AVG_TEMP_F, 60) > 100 THEN 5
                    ELSE 0 END)
        , 1))) >= 90 THEN 'A'
        WHEN GREATEST(0, LEAST(100, ROUND(
            100
            - (COALESCE(R.ERROR_RATE_PCT, 0) * 0.5)
            - (CASE WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 3 THEN 25
                    WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 2 THEN 15
                    WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 1 THEN 5
                    ELSE 0 END)
            - (CASE WHEN COALESCE(R.BATTERY_AGE, 0) >= 10 THEN 10
                    WHEN COALESCE(R.BATTERY_AGE, 0) >= 5 THEN 5
                    ELSE 0 END)
            - (CASE WHEN COALESCE(R.AVG_TEMP_F, 60) < 20 OR COALESCE(R.AVG_TEMP_F, 60) > 100 THEN 5
                    ELSE 0 END)
        , 1))) >= 70 THEN 'B'
        WHEN GREATEST(0, LEAST(100, ROUND(
            100
            - (COALESCE(R.ERROR_RATE_PCT, 0) * 0.5)
            - (CASE WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 3 THEN 25
                    WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 2 THEN 15
                    WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 1 THEN 5
                    ELSE 0 END)
            - (CASE WHEN COALESCE(R.BATTERY_AGE, 0) >= 10 THEN 10
                    WHEN COALESCE(R.BATTERY_AGE, 0) >= 5 THEN 5
                    ELSE 0 END)
            - (CASE WHEN COALESCE(R.AVG_TEMP_F, 60) < 20 OR COALESCE(R.AVG_TEMP_F, 60) > 100 THEN 5
                    ELSE 0 END)
        , 1))) >= 50 THEN 'C'
        WHEN GREATEST(0, LEAST(100, ROUND(
            100
            - (COALESCE(R.ERROR_RATE_PCT, 0) * 0.5)
            - (CASE WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 3 THEN 25
                    WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 2 THEN 15
                    WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 1 THEN 5
                    ELSE 0 END)
            - (CASE WHEN COALESCE(R.BATTERY_AGE, 0) >= 10 THEN 10
                    WHEN COALESCE(R.BATTERY_AGE, 0) >= 5 THEN 5
                    ELSE 0 END)
            - (CASE WHEN COALESCE(R.AVG_TEMP_F, 60) < 20 OR COALESCE(R.AVG_TEMP_F, 60) > 100 THEN 5
                    ELSE 0 END)
        , 1))) >= 30 THEN 'D'
        ELSE 'F'
    END AS QUALITY_GRADE,

    -- Risk factors as a comma-separated string
    ARRAY_TO_STRING(ARRAY_COMPACT(ARRAY_CONSTRUCT(
        CASE WHEN COALESCE(R.ERROR_RATE_PCT, 0) >= 50 THEN 'HIGH_ERROR_RATE' END,
        CASE WHEN COALESCE(R.DTC_ERROR_EVENTS, 0) >= 3 THEN 'FREQUENT_DTC' END,
        CASE WHEN COALESCE(R.BATTERY_AGE, 0) >= 10 THEN 'AGED_BATTERY' END,
        CASE WHEN COALESCE(R.AVG_TEMP_F, 60) < 20 THEN 'EXTREME_COLD' END,
        CASE WHEN COALESCE(R.AVG_TEMP_F, 60) > 100 THEN 'EXTREME_HEAT' END,
        CASE WHEN P.RISK_LEVEL IN ('CRITICAL', 'HIGH') THEN 'HIGH_FAILURE_RISK' END
    )), ', ') AS RISK_FACTORS,

    CURRENT_TIMESTAMP() AS CREATED_AT

FROM AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_PREDICTION P

LEFT JOIN AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_RCA R
    ON P.CAR_ID = R.CAR_ID
   AND P.PART_NUMBER = R.PART_NUMBER

LEFT JOIN AUTOPULSE_AI.CURATED.VEHICLE_BATTERY_360 B
    ON P.CAR_ID = B.CAR_ID
   AND P.PART_NUMBER = B.PART_NUMBER;
