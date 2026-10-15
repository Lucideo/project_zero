select
    country_iso3,
    country_name as country,
    continent,
    un_region,
    subregion
 from 
    {{ ref("stg_natural_earth_countries") }}