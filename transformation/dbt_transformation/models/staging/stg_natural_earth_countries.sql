select
    name as country_name,
    case
        when iso_a3_eh = '-99' then left(name, 3)
        when (iso_a3_eh = 'AUS' and name != 'Australia') then left(name, 3)
        else iso_a3_eh
    end as country_iso3,
    continent as continent,
    region_un as un_region,
    subregion as subregion,
    geom
from st_read({{ source('countries', 'natural_earth_countries') }})