{% macro classify_quake_magnitude(column) %}
    case
        when {{ column }} < 2 then 'Micro'
        when {{ column }} < 4 then 'Minor'
        when {{ column }} < 5 then 'Light'
        when {{ column }} < 6 then 'Moderate'
        when {{ column }} < 7 then 'Strong'
        when {{ column }} < 8 then 'Major'
        else 'Great'
    end
{% endmacro %}