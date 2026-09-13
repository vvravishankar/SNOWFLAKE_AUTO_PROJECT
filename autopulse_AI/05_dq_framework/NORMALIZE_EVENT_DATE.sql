-- ============================================================================
-- AUTOPULSE AI | DQ
-- Function: NORMALIZE_EVENT_DATE
-- Purpose: Normalize legacy two-digit event years without changing existing logic.
-- Execution: SQL UDF
-- ============================================================================
--
-- PRODUCTION NOTES
-- - Logic is intentionally unchanged from the supplied implementation.
-- - NULL input remains NULL.
-- - Years 0-99 are shifted forward by 2000.
-- - All other dates are returned unchanged.
-- - This function is referenced by the DQ framework during CLEAN loading.
-- - Keep this function deterministic and free of external dependencies.
--
-- Deployment:
--   CREATE OR REPLACE FUNCTION ...
--
-- ============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE AUTOPULSE_WH;

CREATE OR REPLACE FUNCTION AUTOPULSE_AI.DQ.NORMALIZE_EVENT_DATE(P_DATE DATE)
RETURNS DATE
LANGUAGE SQL
AS
$$
    CASE
        WHEN P_DATE IS NULL
            THEN NULL

        WHEN YEAR(P_DATE) BETWEEN 0 AND 99
            THEN DATE_FROM_PARTS(
                YEAR(P_DATE) + 2000,
                MONTH(P_DATE),
                DAY(P_DATE)
            )

        ELSE P_DATE
    END
$$;
