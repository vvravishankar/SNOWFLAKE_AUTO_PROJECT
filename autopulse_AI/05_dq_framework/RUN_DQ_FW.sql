-- ============================================================================
-- AUTOPULSE AI | DQ FRAMEWORK
-- Procedure: RUN_DQ_FW (Run Data Quality Framework)
-- ============================================================================
--
-- Purpose:
--   Execute all active DQ rules for a given RAW source table, record
--   pass/fail results in DQ_RESULTS, and load DQ-approved records into
--   the corresponding CLEAN table.
--
-- Architecture:
--   Snowpipe -> RAW -> [DQ Stream triggers this procedure via Task]
--                          |
--                          +--> DQ_RULES      (rule definitions, 148 rules)
--                          +--> DQ_RESULTS     (per-rule pass/fail stats)
--                          +--> REJECTED_RECORDS (quarantine, future use)
--                          |
--                          +--> CLEAN table    (DQ-approved records)
--
-- Execution:
--   CALL AUTOPULSE_AI.DQ.RUN_DQ_FW('VEHICLES_RAW');
--
--   Accepts any of the 11 RAW table names:
--     BATTERY_COMPONENTS_RAW, BATTERY_SUPPLIER_RAW, BATTERY_TYPE_RAW,
--     DATE_VALUES_YEAR_RAW, DTC_BATTERY_ERROR_CODES_RAW, PART_BATTERY_RAW,
--     STATES_AND_ABBREVIATIONS_RAW, VEHICLES_RAW, VEHICLE_EVENTS_RAW,
--     WEATHER_DATA_RAW, ZIP_CODE_INFO_RAW
--
-- Processing logic:
--   1. Generate a unique RUN_ID from timestamp + table short code.
--   2. Fetch active rules from DQ_RULES for the given source table.
--   3. For each rule, count rows_checked vs rows_failed (today only).
--   4. Write per-rule results to DQ_RESULTS.
--   5. Build a combined pass-condition from all rules.
--   6. Delete today's snapshot from the CLEAN table (idempotent reload).
--   7. INSERT into CLEAN only records that pass all rules.
--      - VEHICLE_EVENTS_RAW gets special handling: DATE_VALUES is
--        normalized via NORMALIZE_EVENT_DATE() during the CLEAN load.
--   8. Return a summary string with RUN_ID, counts, and CLEAN row total.
--
-- Dependencies:
--   - AUTOPULSE_AI.DQ.DQ_RULES          (must be populated before first call)
--   - AUTOPULSE_AI.DQ.DQ_RESULTS        (write target)
--   - AUTOPULSE_AI.DQ.NORMALIZE_EVENT_DATE (UDF, used for VEHICLE_EVENTS)
--   - AUTOPULSE_AI.RAW.*_RAW            (source tables)
--   - AUTOPULSE_AI.CLEAN.*_CLEAN        (target tables)
--
-- Execution role:
--   Runs as OWNER (EXECUTE AS OWNER). The owning role must have
--   SELECT on RAW, INSERT/DELETE on CLEAN, and INSERT on DQ_RESULTS.
--
-- Language: JavaScript (Snowflake Scripting)
-- ============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE AUTOPULSE_WH;

CREATE OR REPLACE PROCEDURE AUTOPULSE_AI.DQ.RUN_DQ_FW(
    P_SOURCE_TABLE VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS
$$

var source_table_param = P_SOURCE_TABLE.toUpperCase().trim();


/*
 * ============================================================
 * VALIDATE SOURCE TABLE NAME
 * ============================================================
 */

if (!/^[A-Z0-9_]+$/.test(source_table_param)) {

    throw new Error(
        'Invalid source table name: ' + source_table_param
    );
}


/*
 * ============================================================
 * GENERATE RUN ID
 * ============================================================
 */

var run_ts_sql = `
    SELECT TO_VARCHAR(
        CURRENT_TIMESTAMP(),
        'YYYYMMDDHH24MISS'
    )
`;

var run_ts_stmt = snowflake.createStatement({
    sqlText: run_ts_sql
});

var run_ts_rs = run_ts_stmt.execute();

run_ts_rs.next();

var run_timestamp = run_ts_rs.getColumnValue(1);


/*
 * ============================================================
 * TABLE SHORT CODES
 * ============================================================
 */

var table_code_map = {

    'BATTERY_COMPONENTS_RAW': 'BC',
    'BATTERY_SUPPLIER_RAW': 'BS',
    'BATTERY_TYPE_RAW': 'BT',
    'DATE_VALUES_YEAR_RAW': 'DY',
    'DTC_BATTERY_ERROR_CODES_RAW': 'DTC',
    'PART_BATTERY_RAW': 'PB',
    'STATES_AND_ABBREVIATIONS_RAW': 'SA',
    'VEHICLES_RAW': 'VH',
    'VEHICLE_EVENTS_RAW': 'VE',
    'WEATHER_DATA_RAW': 'WD',
    'ZIP_CODE_INFO_RAW': 'ZIP'
};

var table_code = table_code_map[source_table_param];

if (table_code == null) {

    throw new Error(
        'No RUN_ID table code defined for ' +
        source_table_param
    );
}

var run_id = run_timestamp + '_' + table_code;


/*
 * ============================================================
 * TODAY'S LOAD CONDITION
 *
 * ONLY PROCESS RECORDS LOADED TODAY.
 *
 * This relies on SOURCE tables having:
 *
 *     LOAD_TIMESTAMP TIMESTAMP_NTZ
 *
 * ============================================================
 */

var today_condition = `
    LOAD_TIMESTAMP >= CURRENT_DATE()
    AND LOAD_TIMESTAMP < DATEADD(DAY, 1, CURRENT_DATE())
`;


/*
 * ============================================================
 * DETERMINE CLEAN TABLE
 * ============================================================
 */

var clean_table = source_table_param.replace(
    /_RAW$/,
    '_CLEAN'
);


/*
 * ============================================================
 * GET ACTIVE DQ RULES
 * ============================================================
 */

var rule_sql = `
    SELECT
        RULE_ID,
        RULE_NAME,
        SOURCE_TABLE,
        SOURCE_COLUMN,
        RULE_TYPE,
        RULE_SQL
    FROM AUTOPULSE_AI.DQ.DQ_RULES
    WHERE IS_ACTIVE = TRUE
      AND UPPER(SOURCE_TABLE) = ?
    ORDER BY RULE_ID
`;

var rule_stmt = snowflake.createStatement({
    sqlText: rule_sql,
    binds: [source_table_param]
});

var rule_rs = rule_stmt.execute();

var rule_count = 0;
var result_count = 0;

var rule_execution_error = false;

var pass_conditions = [];


/*
 * ============================================================
 * PROCESS EACH DQ RULE
 * ============================================================
 */

while (rule_rs.next()) {

    rule_count++;

    var rule_id = rule_rs.getColumnValue(1);
    var rule_name = rule_rs.getColumnValue(2);
    var source_table = rule_rs.getColumnValue(3);
    var source_column = rule_rs.getColumnValue(4);
    var rule_type = rule_rs.getColumnValue(5);
    var rule_condition = rule_rs.getColumnValue(6);

    var rows_checked = 0;
    var rows_failed = 0;
    var rows_passed = 0;

    var failure_percentage = 0;

    var status = 'PASS';

    var failure_summary = '';


    try {


        /*
         * ------------------------------------------------------
         * VALIDATE SOURCE COLUMN
         * ------------------------------------------------------
         */

        if (
            source_column != null &&
            String(source_column).trim() != ''
        ) {

            source_column =
                String(source_column)
                .toUpperCase()
                .trim();


            if (!/^[A-Z0-9_]+$/.test(source_column)) {

                throw new Error(
                    'Invalid SOURCE_COLUMN for rule ' +
                    rule_id
                );
            }
        }


        /*
         * ------------------------------------------------------
         * UNIQUE RULE
         * ------------------------------------------------------
         */

        if (rule_type == 'UNIQUE') {


            if (
                source_column == null ||
                String(source_column).trim() == ''
            ) {

                throw new Error(
                    'SOURCE_COLUMN is empty for UNIQUE rule ' +
                    rule_id
                );
            }


            /*
             * IMPORTANT:
             *
             * BOTH the outer table and duplicate
             * lookup are restricted to TODAY.
             */

            var unique_sql = `
                SELECT
                    COUNT(*) AS ROWS_CHECKED,

                    COALESCE(
                        SUM(
                            CASE
                                WHEN dup.${source_column} IS NULL
                                THEN 0
                                ELSE 1
                            END
                        ),
                        0
                    ) AS ROWS_FAILED

                FROM AUTOPULSE_AI.RAW.${source_table} r

                LEFT JOIN (

                    SELECT ${source_column}

                    FROM AUTOPULSE_AI.RAW.${source_table}

                    WHERE ${source_column} IS NOT NULL
                      AND ${today_condition}

                    GROUP BY ${source_column}

                    HAVING COUNT(*) > 1

                ) dup

                    ON r.${source_column} =
                       dup.${source_column}

                WHERE
                    ${today_condition}
            `;


            var unique_stmt =
                snowflake.createStatement({
                    sqlText: unique_sql
                });


            var unique_rs =
                unique_stmt.execute();


            if (unique_rs.next()) {

                rows_checked =
                    Number(
                        unique_rs.getColumnValue(1)
                    );

                rows_failed =
                    Number(
                        unique_rs.getColumnValue(2)
                    );
            }


            /*
             * CLEAN condition.
             *
             * Only evaluate duplicate values
             * within today's records.
             */

            pass_conditions.push(`
                (
                    ${source_column} IS NULL

                    OR

                    ${source_column} NOT IN (

                        SELECT ${source_column}

                        FROM AUTOPULSE_AI.RAW.${source_table}

                        WHERE ${source_column} IS NOT NULL
                          AND ${today_condition}

                        GROUP BY ${source_column}

                        HAVING COUNT(*) > 1
                    )
                )
            `);

        }


        /*
         * ------------------------------------------------------
         * STANDARD RULE
         * ------------------------------------------------------
         */

        else {


            if (
                rule_condition == null ||
                String(rule_condition).trim() == ''
            ) {

                throw new Error(
                    'RULE_SQL is empty for rule ' +
                    rule_id
                );
            }


            rule_condition =
                String(rule_condition).trim();


            /*
             * IMPORTANT:
             *
             * DQ NOW CHECKS ONLY TODAY'S RECORDS.
             */

            var standard_sql = `
                SELECT

                    COUNT(*) AS ROWS_CHECKED,

                    COALESCE(
                        SUM(
                            CASE

                                WHEN ${rule_condition}
                                THEN 0

                                ELSE 1

                            END
                        ),
                        0
                    ) AS ROWS_FAILED

                FROM AUTOPULSE_AI.RAW.${source_table}

                WHERE
                    ${today_condition}
            `;


            var standard_stmt =
                snowflake.createStatement({
                    sqlText: standard_sql
                });


            var standard_rs =
                standard_stmt.execute();


            if (standard_rs.next()) {

                rows_checked =
                    Number(
                        standard_rs.getColumnValue(1)
                    );

                rows_failed =
                    Number(
                        standard_rs.getColumnValue(2)
                    );
            }


            /*
             * --------------------------------------------------
             * DATE NORMALIZATION EXCEPTION
             * --------------------------------------------------
             */

            if (
                source_table_param ==
                    'VEHICLE_EVENTS_RAW'

                &&

                source_column ==
                    'DATE_VALUES'
            ) {

                /*
                 * Do not add DATE_VALUES to pass_conditions.
                 */

            }

        else {

                pass_conditions.push(
                    '(' + rule_condition + ')'
                );
            }
        }


        /*
         * ====================================================
         * CALCULATE RESULTS
         * ====================================================
         */

        rows_passed =
            rows_checked - rows_failed;


        if (rows_checked > 0) {

            failure_percentage =
                (rows_failed / rows_checked) * 100;
        }


        if (rows_failed > 0) {

            status = 'FAIL';

            failure_summary =
                rule_name +
                ': ' +
                rows_failed +
                ' rows failed out of ' +
                rows_checked +
                ' rows checked.';

        }

        else {

            status = 'PASS';

            failure_summary =
                rule_name +
                ': 0 rows failed out of ' +
                rows_checked +
                ' rows checked.';
        }


        /*
         * ====================================================
         * WRITE DQ RESULT
         * ====================================================
         */

        var result_id =
            run_id +
            '_' +
            rule_id +
            '_' +
            Date.now();


        var insert_sql = `
            INSERT INTO AUTOPULSE_AI.DQ.DQ_RESULTS
            (
                DQ_RESULT_ID,
                RUN_ID,
                RULE_ID,
                SOURCE_TABLE,
                SOURCE_COLUMN,
                CHECKED_AT,
                ROWS_CHECKED,
                ROWS_PASSED,
                ROWS_FAILED,
                STATUS,
                FAILURE_PERCENTAGE,
                FAILURE_SUMMARY
            )

            VALUES
            (
                ?,
                ?,
                ?,
                ?,
                ?,
                CURRENT_TIMESTAMP(),
                ?,
                ?,
                ?,
                ?,
                ?,
                ?
            )
        `;


        var insert_stmt =
            snowflake.createStatement({

                sqlText: insert_sql,

                binds: [

                    result_id,
                    run_id,
                    rule_id,
                    source_table,
                    source_column,

                    rows_checked,
                    rows_passed,
                    rows_failed,
                    status,
                    failure_percentage,
                    failure_summary
                ]
            });


        insert_stmt.execute();

        result_count++;
    }


    catch (err) {


        /*
         * ====================================================
         * RULE EXECUTION ERROR
         * ====================================================
         */

        rule_execution_error = true;


        var error_result_id =
            run_id +
            '_' +
            rule_id +
            '_ERROR_' +
            Date.now();


        var error_summary =
            rule_name +
            ': DQ execution error - ' +
            err.message;


        var error_insert_sql = `
            INSERT INTO AUTOPULSE_AI.DQ.DQ_RESULTS
            (
                DQ_RESULT_ID,
                RUN_ID,
                RULE_ID,
                SOURCE_TABLE,
                SOURCE_COLUMN,
                CHECKED_AT,
                ROWS_CHECKED,
                ROWS_PASSED,
                ROWS_FAILED,
                STATUS,
                FAILURE_PERCENTAGE,
                FAILURE_SUMMARY
            )

            VALUES
            (
                ?,
                ?,
                ?,
                ?,
                ?,
                CURRENT_TIMESTAMP(),
                0,
                0,
                0,
                'FAIL',
                0,
                ?
            )
        `;


        var error_stmt =
            snowflake.createStatement({

                sqlText: error_insert_sql,

                binds: [

                    error_result_id,
                    run_id,
                    rule_id,
                    source_table,
                    source_column,
                    error_summary
                ]
            });


        error_stmt.execute();

        result_count++;
    }
}


/*
 * ============================================================
 * NO RULES FOUND
 * ============================================================
 */

if (rule_count == 0) {

    throw new Error(
        'No active DQ rules found for table ' +
        source_table_param
    );
}


/*
 * ============================================================
 * DO NOT LOAD CLEAN IF RULE EXECUTION ERROR
 * ============================================================
 */

if (rule_execution_error) {

    return (

        'DQ completed with rule execution errors. ' +

        'CLEAN was NOT loaded. ' +

        'RUN_ID=' + run_id +

        ', SOURCE_TABLE=' +
        source_table_param +

        ', RULES_PROCESSED=' +
        rule_count +

        ', RESULTS_CREATED=' +
        result_count
    );
}


/*
 * ============================================================
 * BUILD ALL-RULES-PASS CONDITION
 * ============================================================
 */

var combined_condition;

if (pass_conditions.length == 0) {

    combined_condition = 'TRUE';

}

else {

    combined_condition =
        pass_conditions.join(
            '\nAND\n'
        );
}


/*
 * ============================================================
 * CLEAR TODAY'S CLEAN SNAPSHOT ONLY
 *
 * IMPORTANT:
 * We DO NOT delete historical CLEAN data.
 * ============================================================
 */

var delete_clean_sql = `
    DELETE FROM
        AUTOPULSE_AI.CLEAN.${clean_table}

    WHERE
        LOAD_TIMESTAMP >= CURRENT_DATE()
        AND LOAD_TIMESTAMP < DATEADD(DAY, 1, CURRENT_DATE())
`;


var delete_clean_stmt =
    snowflake.createStatement({
        sqlText: delete_clean_sql
    });


delete_clean_stmt.execute();


/*
 * ============================================================
 * LOAD CLEAN
 * ============================================================
 */

var clean_insert_sql;


if (
    source_table_param ==
    'VEHICLE_EVENTS_RAW'
) {


    clean_insert_sql = `

        INSERT INTO
            AUTOPULSE_AI.CLEAN.${clean_table}

        SELECT

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

            CASE

                WHEN DATE_VALUES IS NULL
                    THEN NULL

                WHEN YEAR(DATE_VALUES) < 2000
                    THEN
                        AUTOPULSE_AI.DQ.NORMALIZE_EVENT_DATE(
                            DATE_VALUES
                        )

                ELSE
                    DATE_VALUES

            END AS DATE_VALUES,

            AVG_TEMP_F,
            AVG_WIND_SPEED_MPH,
            TOT_PRECIPITATION_IN,
            TOT_SNOWFALL_IN,
            DTC_ERROR_CODE,
            SOURCE_FILE_NAME,
            LOAD_TIMESTAMP

        FROM
            AUTOPULSE_AI.RAW.${source_table_param}

        WHERE
            ${today_condition}

        AND
            ${combined_condition}
    `;
}

else if (
    source_table_param ==
    'DATE_VALUES_YEAR_RAW'
) {

    clean_insert_sql = `

        INSERT INTO
            AUTOPULSE_AI.CLEAN.${clean_table}
            (DATE_VALUES, YEAR, SOURCE_FILE_NAME, LOAD_TIMESTAMP)

        SELECT
            DATE_VALUES,
            YEAR(DATE_VALUES) AS YEAR,
            SOURCE_FILE_NAME,
            LOAD_TIMESTAMP

        FROM
            AUTOPULSE_AI.RAW.${source_table_param}

        WHERE
            ${today_condition}

        AND
            ${combined_condition}
    `;
}

else {


    clean_insert_sql = `

        INSERT INTO
            AUTOPULSE_AI.CLEAN.${clean_table}

        SELECT *

        FROM
            AUTOPULSE_AI.RAW.${source_table_param}

        WHERE
            ${today_condition}

        AND
            ${combined_condition}
    `;
}


var clean_insert_stmt =
    snowflake.createStatement({

        sqlText: clean_insert_sql
    });


clean_insert_stmt.execute();


/*
 * ============================================================
 * COUNT TODAY'S CLEAN RECORDS
 * ============================================================
 */

var clean_count_sql = `

    SELECT COUNT(*)

    FROM
        AUTOPULSE_AI.CLEAN.${clean_table}

    WHERE
        LOAD_TIMESTAMP >= CURRENT_DATE()
        AND LOAD_TIMESTAMP < DATEADD(DAY, 1, CURRENT_DATE())
`;


var clean_count_stmt =
    snowflake.createStatement({

        sqlText: clean_count_sql
    });


var clean_count_rs =
    clean_count_stmt.execute();


var clean_rows = 0;


if (clean_count_rs.next()) {

    clean_rows =
        Number(
            clean_count_rs.getColumnValue(1)
        );
}


/*
 * ============================================================
 * FINAL RESPONSE
 * ============================================================
 */

return (

    'DQ + CLEAN completed successfully. ' +

    'RUN_ID=' +
    run_id +

    ', SOURCE_TABLE=' +
    source_table_param +

    ', PROCESSING_DATE=' +
    run_timestamp.substring(0,8) +

    ', RULES_PROCESSED=' +
    rule_count +

    ', RESULTS_CREATED=' +
    result_count +

    ', CLEAN_TABLE=' +
    clean_table +

    ', CLEAN_ROWS_TODAY=' +
    clean_rows
);

$$;