select
    p.OGC_FID as id,
    p.Code as code_plate,
    p.PlateName as name,
    p.geom
from {{ source('tectonic_plates', 'plates') }} p