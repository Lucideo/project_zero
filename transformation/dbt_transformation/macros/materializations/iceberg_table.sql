/*
* Table materialization for models written to an attached Iceberg catalog (Polaris).
* The default duckdb `table` materialization builds `<model>__dbt_tmp` and renames it,
* but DuckDB's iceberg extension can't rename a table created in the same transaction.
* Here we drop the existing table (own transaction) and recreate it with CTAS instead.
*/
{% materialization iceberg_table, adapter="duckdb", supported_languages=['sql'] %}

  {%- set existing_relation = load_cached_relation(this) -%}
  {%- set target_relation = this.incorporate(type='table') -%}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}

  {% if existing_relation is not none %}
    {% call statement('drop_existing', auto_begin=False) -%}
      drop table if exists {{ existing_relation }}
    {%- endcall %}
    {% do adapter.cache_dropped(existing_relation) %}
  {% endif %}

  -- `BEGIN` happens here:
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {% call statement('main') -%}
    {{ create_table_as(False, target_relation, sql) }}
  {%- endcall %}

  {{ run_hooks(post_hooks, inside_transaction=True) }}

  -- `COMMIT` happens here
  {{ adapter.commit() }}

  {{ run_hooks(post_hooks, inside_transaction=False) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
