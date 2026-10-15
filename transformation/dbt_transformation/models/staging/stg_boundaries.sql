with plate_name as (
    select distinct code_plate, name from {{ ref('stg_plates') }}
)

select 
    b.OGC_FID as id,
    b.Name as code_boundary,
    plate_a.name || '-' || plate_b.name as name,
    b.PlateA as plate_a,
    plate_a.name as name_plate_a,
    b.PlateB as plate_b,
    plate_b.name as name_plate_b,
    b.Type as type,
    b.geom
from {{ source('tectonic_plates', 'boundaries') }} b
left join plate_name plate_a on plate_a.code_plate = b.PlateA
left join plate_name plate_b on plate_b.code_plate = b.PlateB