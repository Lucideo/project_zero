{{ config(materialized='incremental', unique_key='id') }}

-- Add earthquake coordinates (lon, lat, depth).
with quakes_dedup as (
    select
        e.*
    from
        {{ source('earthquakes', 'earthquakes') }} e
    {% if is_incremental() %}
        where e.properties__updated > (select coalesce(epoch_ms(max(datetime_update)), 0) from {{ this }})
    {% endif%}
    qualify row_number() over(partition by e.id order by e.properties__updated desc) = 1
),

quakes_geo_coord as (
    select
        e.*,
        max(case when c._dlt_list_idx = 0 then c.value end) as longitude,
        max(case when c._dlt_list_idx = 1 then c.value end) as latitude,
        max(case when c._dlt_list_idx = 2 then c.value end) as depth_km,
        ST_Point(longitude, latitude) as geo_point
    from quakes_dedup e
    join {{ source('earthquakes', 'earthquakes__geometry__coordinates') }} c on c._dlt_parent_id = e._dlt_id
    group by all
),

countries as (
    select * from {{ ref('stg_natural_earth_countries') }}
),

-- When epicenter is inside a country.
inside_country as (
    select
        q.id,
        c.country_iso3,
        0.0 as distance_degress,
        'inside' as match_type
    from quakes_geo_coord q 
    join countries c on ST_Contains(c.geom, q.geo_point)
),

-- When epicenter is near to country.
nearest_country as (
    select
        q.id,
        c.country_iso3,
        ST_Distance(c.geom, q.geo_point) as distance_degress,
        'nearest' as match_type
    from quakes_geo_coord q 
    cross join countries c
    where q.id not in (select id from inside_country)
    qualify row_number() over (partition by q.id order by distance_degress) = 1
),

matched_countries as (
    select * from inside_country
    union all
    select * from nearest_country
),

-- Epicenter's plate.
plates as (
    select 
        q.id, 
        p.id as id_plate,
    from quakes_geo_coord q
    join {{ ref('stg_plates') }} p on ST_Contains(p.geom, q.geo_point)
),

-- Epicenter's boundary.
boundaries as (
    select
        q.id,
        b.id as id_boundary,
        ST_Distance(b.geom, q.geo_point) as distance_degrees
    from quakes_geo_coord q 
    cross join {{ ref('stg_boundaries') }} b
    qualify row_number() over (partition by q.id order by distance_degrees) = 1
)

select
    q.id,
    m.country_iso3,
    p.id_plate,
    b.id_boundary,
    round(b.distance_degrees * 111, 1) as approx_km_to_boundary, -- rough deg→km
    q.properties__place as place,

    m.match_type,
    round(m.distance_degress * 111, 1) as approx_km_to_country, -- rough deg→km

    q.longitude,
    q.latitude,
    q.depth_km,
    
    epoch_ms(q.properties__time) as datetime,
    epoch_ms(q.properties__time)::date as date,
    epoch_ms(q.properties__updated) as datetime_update,
    epoch_ms(q.properties__updated)::date as date_update,
    
    q.properties__mag as magnitude,
    q.properties__mag_type as magnitude_type,

    -- Impact and significance.
    q.properties__felt as felt, -- Number of “Did You Feel It?” reports.
    q.properties__cdi as cdi, -- Community-reported intensity.
    q.properties__mmi as mmi, -- Maximum estimated instrumental intensity.
    q.properties__alert as alert, -- Alert level for estimated fatalities and losses.
    q.properties__tsunami as tsunami, -- Event was large and in an oceanic region.
    q.properties__sig as significance, -- Significance score that combines mag, MMI, felt and estimated impact.

    q.properties__net as net_contributor,
    q.properties__status as status,

    -- Location quality
    q.properties__nst as number_stations, -- Number of seismic stations used to locate the event.
    q.properties__dmin as distance_nearest_station, -- Horizontal distance from the epicenter to the nearest station, in degrees.
    q.properties__rms as rms, -- Root-mean-square travel-time residual, in seconds.
    q.properties__gap as azimuthal_gap, -- Largest azimuthal gap between neighbouring stations, in degrees.
    
    q.properties__url as usgs_url, -- Event webpage on USGS.
    q.properties__detail as geojson_url -- Event webpage on USGS.
from quakes_geo_coord q
left join matched_countries m using (id)
left join plates p using (id)
left join boundaries b using (id)