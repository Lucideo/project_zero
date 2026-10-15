{{ config(materialized='incremental', unique_key='id') }}

select
    e.id,
    e.country_iso3,
    e.id_plate,
    e.id_boundary,
    e.approx_km_to_boundary,
    e.place,
    case when e.approx_km_to_country > 200 then 1 else 0 end as international_water,

    e.match_type as location_match_type,
    e.approx_km_to_country,

    e.longitude,
    e.latitude,
    e.depth_km,
    {{ classify_quake_depth('e.depth_km') }} as depth_class,

    e.datetime,
    e.date,
    e.datetime_update,
    e.date_update,

    e.magnitude,
    e.magnitude_type,
    {{ classify_quake_magnitude('e.magnitude') }} as magnitude_class,

    e.felt,
    e.cdi,
    e.mmi,
    e.alert,
    e.tsunami,
    e.significance as significance_score,
    case when significance > 600 then 1 else 0 end as is_significant,

    e.net_contributor,
    case when e.status = 'reviewed' then 1 else 0 end as is_reviewed,

    e.number_stations,
    e.distance_nearest_station,
    e.rms,
    e.azimuthal_gap,

    e.usgs_url,
    e.geojson_url
from
    {{ ref("stg_earthquakes") }} e
{% if is_incremental() %}
    where e.datetime_update > (select max(datetime_update) from {{ this }})
{% endif%}