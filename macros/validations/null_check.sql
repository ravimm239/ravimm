null_check
{% macro test_null_check(model, column_name) %}
    {% if execute %}
        select *
        from {{ model }}
        where
            trim({{ column_name }}) is null or length(trim({{ column_name }})) = 0
    {% endif %}
{% endmacro %}