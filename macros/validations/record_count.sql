{% macro test_record_count(model, compare_model, source_custom_query,target_custom_query, where_condition={}, count_multiplier={}) %}

    {% set source_where = where_condition.base if (where_condition.base|length) else '' %}
    {% set target_where = where_condition.target if (where_condition.target|length) else '' %}
    {% set source_multiplier = count_multiplier.base if (count_multiplier.base|length)  else 1 %}
    {% set target_multiplier = count_multiplier.target if (count_multiplier.target|length)  else 1 %}

    {% if execute %}

        {% set source_where_builder = (
            ("where " ~ source_where) if source_where | length else ""
        ) %}

        {% set target_where_builder = (
            ("where " ~ target_where) if target_where | length else ""
        ) %}

        with
            base_model as (
                {% if target_custom_query | length %}
                select count as count_a from ( {{target_custom_query}} )
                {% else %}
                select ({{ target_multiplier }}* count(*)) as count_a
                from {{ compare_model }} {{ target_where_builder }}
                {% endif %}
            ),

            compare_model as (
                 {% if source_custom_query | length %}
                select count as count_b from ( {{source_custom_query}} )
                {% else %}
                select ({{ source_multiplier }}* count(*)) as count_b 
                from {{ model }} {{ source_where_builder }}

                {% endif %}
               
            ),

            final as (
                (
                    select count_a as num_of_rec,1 as rn
                    from base_model
                    minus
                    select count_b as num_of_rec,1 as rn
                    from compare_model
                )
                union all
                (
                    select count_b as num_of_rec,2 as rn
                    from compare_model
                    minus
                    select count_a as num_of_rec,2 as rn
                    from base_model
                )
            )

        select
            '{{compare_model | upper}}'  as source_table_name,
            '{{ model| upper}}' as target_table_name,
            'Source and target record counts are '
            || listagg(num_of_rec, ' and ') within group (
                order by num_of_rec
            ) as record_count_error_msg
        from final
        where num_of_rec > 0
        group by source_table_name, target_table_name

    {% endif %}

{% endmacro %}