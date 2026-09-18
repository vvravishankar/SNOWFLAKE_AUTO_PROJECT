select * from AUTOPULSE_AI.RAW.DTC_BATTERY_ERROR_CODES_RAW

select * from AUTOPULSE_AI.CLEAN.DATE_VALUES_YEAR_CLEAN

select * from AUTOPULSE_AI.CURATED.VEHICLE_EVENT_CONTEXT


USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE SECRET git_secret
    TYPE=PASSWORD
    USERNAME=vvravishankar
    PASSWORD=ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss
    COMMENT='GitHub PAT for Git integration - created by setup script';
