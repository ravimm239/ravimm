{% macro centralize_test_failures(results) %}
    {% if execute %}
        {%- set test_status = namespace(stat="") -%}
        {%- set test_results = [] -%}
        {%- for result in results -%}
            {%- if result.node.resource_type == "test" and result.status != "skipped" and (
                result.node.config.get("store_failures")
                or flags.STORE_FAILURES
            ) -%}
                {%- do test_results.append(result) -%}
            {%- endif -%}
        {%- endfor -%}

            {% for result in test_results %}
                {%- set stat -%}
                    {{result.status}}
                {%- endset -%}

                {%- set test_status.stat -%}
                    {{test_status.stat}}{{stat}}{{ "," if not loop.last }}
                {%- endset -%}
            {% endfor %}        

        {% if test_results and (('fail' in test_status.stat) or ('warn' in test_status.stat)) %}  
   
            {% set job_name = test_results[0].node.file_key_name.split(".")[1] %}

            {% set src_name = namespace(val="") %}
            {% set stage = namespace(val="") %}

            {% for node in graph.nodes.values() %}
                {%- set table_name = node.unique_id.split(".")[-1] -%}
                {%- if job_name == table_name -%}
                    {% set src_name.val = node.config.src_name %}
                    {% set stage.val = node.config.stage %}
                {%- endif -%}
            {%- endfor -%}
            -- To fetch audit Id
             {% set v_audit_table_name = (
                env_var("DBT_SF_SILVER_DB")
                ~ "."
                ~ env_var("DBT_SF_SILVER_FPA_DATA")
                ~ "."
                ~ "ADT_FPA_AUDIT_" ~ src_name.val
            ) %}

            {%- call statement("audit_id_query", fetch_result=True) -%}
                select nvl(max(id), 0) as audit_id
                from {{ v_audit_table_name }}
                where upper(job_name) = upper('{{job_name}}')
            {%- endcall -%}

            {%- set v_audit_id = load_result("audit_id_query")["data"][0][0] -%}
            -- To fetch load_id
            {%- call statement("max_load_id", fetch_result=True) -%}
                select max(nvl(load_id, 0))  as load_id
                from {{ v_audit_table_name }}
                where
                    upper(job_name) = upper('{{job_name}}')
                    and lower(status) = 'success'
            {%- endcall -%}
            {%- set loadid = load_result("max_load_id")["data"][0][0] -%}
       
            {% set load_id = 1 if loadid is none else loadid %}
           
            {% set central_err_tbl = (
                env_var("DBT_SF_SILVER_DB")
                ~ "."
                ~ env_var("DBT_SF_SILVER_FPA_DATA")
                ~ "."
                ~ "ADT_FPA_ERR_DETAIL_" ~ src_name.val
            ) %}
 insert into {{ central_err_tbl }}
 (audit_id,Job_name,data_source,process_type,stage,severity,error_type,error_detail,INSERT_TS,  load_id,EXTRACT_TS,integration_id)
  select audit_id,Job_name,data_source,process_type,stage,severity,error_type,
  case when error_type ='null_check' then
          to_varchar(error_detail)||' || '|| listagg(Column_name,' and ') WITHIN GROUP (ORDER BY Column_name)|| ' is/are null'
           when error_type <>'null_check'  then
           to_varchar(error_detail)||' || '||replace(error_type,'_',' ')||' failed.'  end as error_detail,
          INSERT_TS,
           load_id,
          EXTRACT_TS,integration_id
         from(
  {% for result in test_results %}
            select
               {{v_audit_id}} as audit_id,
          substring('{{ result.node.file_key_name }}',8,len('{{ result.node.file_key_name }}')) as Job_name,
          '{{src_name.val}}' as data_source,
          '{{ stage.val}}' ||' Table Validation' as process_type,
          '{{ stage.val}}' as stage,
          'Critical' as severity,
        --   SUBSTRING('{{ result.node.name }}', 1, POSITION( '_'||trim('{{ result.node.file_key_name }}','models.') IN '{{ result.node.name }}') - 1) as error_type,
          '{{result.node.test_metadata.name}}' as error_type,
          '{{ result.node.column_name }}' as Column_name,
          object_construct_keep_null(*) as error_detail,
        --  '{{ result.node.name }}' as test_name,
           current_timestamp as INSERT_TS,
           {{load_id}} as load_id,
          current_timestamp as EXTRACT_TS,
            '' as integration_id
   from {{ result.node.relation_name }}
   {{ "union all" if not loop.last }}
 {% endfor %}
  )
         group by audit_id,Job_name,data_source,process_type,stage,
          severity,error_type,error_detail,INSERT_TS,load_id,EXTRACT_TS,integration_id
            ;

            -- To drop the error tables dbt has created on run time
            {% for result in test_results %}
                drop table if exists {{ result.node.relation_name }};
            {% endfor %}

        {%- set error =[] -%}                
               {% for result in test_results %}
               {%- if  result.status == "fail" -%}
            {%- set msg -%}
                    {{result.node.test_metadata.name}}
                {%- endset -%}
               
                {%- set error -%}
                {% if msg not in error %}
                {%- do error.append(msg)%}
                 {%- endif -%}
                {%- endset -%}
            {%- endif -%}
            {% endfor %}
{{log(error)}}
    {%- set error_type_msg  -%}          
            {{ error|join(' and ') }}          
             {%- endset -%}


            {% if (('fail' in test_status.stat) ) %}
                {% set status = insert_data_into_audit_table(
                    "UPD",
                    job_name,
                    src_name.val,
                    "Failed",
                    error_type_msg ~ " val failed",
                    stage.val,
                    "",
                    "",
                ) %}
            {% endif %}
        {% endif %}
    {% endif %}
{% endmacro %}