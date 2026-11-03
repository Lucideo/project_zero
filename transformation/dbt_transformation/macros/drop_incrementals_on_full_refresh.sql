/* 
* On --full-refresh, duckdb's incremental materialization builds `<model>__dbt_tmp` and renames it,
* which DuckDB's iceberg extension can't do. Dropping the selected incremental models up front
* makes dbt take the "table doesn't exist" path instead, which creates the table directly.
*/
{% macro drop_incrementals_on_full_refresh() %}
  {% if execute and flags.FULL_REFRESH %}
    {% for node in graph.nodes.values()
        if node.resource_type == 'model'
        and node.config.materialized == 'incremental'
        and node.config.full_refresh is not false
        and node.unique_id in selected_resources %}
      {% set relation = adapter.get_relation(node.database, node.schema, node.alias) %}
      {% if relation is not none %}
        {% do log('Full refresh: dropping ' ~ relation, info=true) %}
        {# drop_relation_if_exists() adds CASCADE, which iceberg tables don't support. #}
        {% do run_query('drop table if exists ' ~ relation) %}
        {% do adapter.cache_dropped(relation) %}
      {% endif %}
    {% endfor %}
  {% endif %}
{% endmacro %}
