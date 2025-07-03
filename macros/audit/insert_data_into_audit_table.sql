{% macro insert_data_into_audit_table(
    p_load_type,
    p_job_name,
    p_src_name,
    p_status,
    p_proc_typ_p_msg,
    p_stage,
    p_integration_id,
    p_increment_flag
) %}

    {#
Parameters :
"p_load_type" will accept two values. "INS" for Creating a new audit . "UPD" for Updating process status. NULL value will be considered as INSERT ("INS").
"p_job_name" will have job (process) name for both Create & update audits. NULL value will be considered as "NA"
"p_src_name" will have Source value for both Create & Update Process
"p_status"  will have Status value for Update Process
"p_proc_typ_p_msg" will have process type for Create Process & it will have Message value for Update Process
"p_stage" will have stage value for both Create & Update Process. NULL value will be considered as "NA"
"p_integration_id" will have inegration value for Create Process & Not required for Update process (Can have Null or empty string)
"p_increment_flag"  will be used to populate loadid
#}
    -- Declare variables
    {% set v_table_name = "adt_fpa_audit" %}
    {#{% set audit_table_name = var(p_src_name)%}#}
   
    {% set v_audit_table = (
        env_var("DBT_SF_SILVER_DB")
        ~ "."
        ~ env_var("DBT_SF_SILVER_FPA_DATA")
        ~ "."
        ~ "ADT_FPA_AUDIT_" ~ p_src_name
    ) %}
    {% set v_load_type = "INS" if p_load_type is none else p_load_type %}
    {% set v_job_name = "NA" if p_job_name is none else p_job_name %}
    {% set v_stage = "NA" if p_stage is none else p_stage %}
    {% set v_increment_flag = "Y" if p_increment_flag is none else p_increment_flag %}
    {% set v_source = p_src_name if p_src_name is not none else null %}

    {% if execute %}

        {% if p_load_type.upper() == "INS" %}
            {% set v_process_type = (
                p_proc_typ_p_msg if p_proc_typ_p_msg is not none else null
            ) %}
            {% set v_integration_id = (
                p_integration_id if p_integration_id is not none else null
            ) %}

            -- Query to get AUDIT_ID
            {%- call statement("get_audit_id", fetch_result=True) -%}
                select nvl(max(id), 0) + 1 from {{ v_audit_table }}
            {%- endcall -%}
            {%- set v_audit_id = load_result("get_audit_id")["data"][0][0] -%}

            -- Query to get LOAD_ID based on Data Source
            {%- call statement("get_load_id", fetch_result=True) -%}
                select
                    decode(
                        '{{v_increment_flag}}',
                        'N',
                        nvl(max(load_id), 0),
                        nvl(max(load_id), 0) + 1
                    ) as load_id
                from {{ v_audit_table }}
                where data_source = '{{v_source}}' and lower(status) = 'success'
            {%- endcall -%}
            {%- set v_load_id = load_result("get_load_id")["data"][0][0] -%}

            -- Insert data into Audit table
            {%- set insert_query -%}
        Insert into {{v_audit_table}} (id , job_name , data_source , process_type , stage , start_ts , load_id, insert_ts , integration_id ) values
        ({{v_audit_id}},'{{v_job_name}}','{{v_source}}','{{v_process_type}}','{{v_stage}}',current_timestamp,{{v_load_id}},current_timestamp,'{{v_integration_id}}')
            {%- endset -%}
            {{ run_query(insert_query) }}
            {{ return("Audit created") }}

        {% elif p_load_type.upper() == "UPD" %}

            {% set v_status = p_status if p_status is not none else null %}
            {% set v_message = (
                p_proc_typ_p_msg if p_proc_typ_p_msg is not none else null
            ) %}

            -- Update Status, Message and End time in Audit table based on Job Name,
            -- Stage and Data Source
            {%- set update_query -%}
        update {{v_audit_table}}
        set status = '{{v_status}}',
            message = '{{v_message}}',
            end_ts = current_timestamp
        where (job_name = '{{v_job_name}}' and stage = '{{v_stage}}'
            and id = (select max(id) from {{v_audit_table}} where data_source = '{{v_source}}' ))
            {%- endset -%}
            {{ run_query(update_query) }}
            {{ return("Audit updated") }}

        {% else %} {{ exceptions.raise_compiler_error("Invalid Load Type") }}
        {# {{ return("Invalid Load Type") }} #}
        {% endif %}

    {% endif %}

{% endmacro %}