{% macro classify_quake_depth(column) %}
    case
        when {{ column }} < 70 then 'Shallow'
        when {{ column }} < 300 then 'Intermediate'
        when {{ column }} < 700 then 'Deep'
    end
{% endmacro %}