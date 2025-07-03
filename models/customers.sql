{{ config(
    materialized='table',
    src_name='CUSTOMERS',
    stage='BRONZE',
    ops_upd='UPD',
    ops_ins='INS',
    status_success='Success',
    status_start='Started',
    status_fail='Failed',
    proc_typ_msg_start='Started validation checks for Customers Table',
    proc_typ_msg_success='Validation checks for Customers Table completed successfully',
    integration_id='',
    flag='Y',

    pre_hook="{% set status = insert_data_into_audit_table(
        model.config.ops_ins,
        model.name,
        model.config.src_name,
        model.config.status_start,
        model.config.proc_typ_msg_start,
        model.config.stage,
        model.config.integration_id,
        model.config.flag
    ) %}",
    post_hook=["{% set status = insert_data_into_audit_table(
        model.config.ops_upd,
        model.name,
        model.config.src_name,
        model.config.status_success,
        model.config.proc_typ_msg_success,
        model.config.stage,
        model.config.integration_id,
        '') %}"]
) }}


WITH customers_raw AS (
    SELECT * FROM {{ source('insurance', 'raw_customers') }}
)

SELECT * FROM customers_raw
