select
    p.OGC_FID as id,
    p.Code as code_plate,
    p.PlateName as name,
    ST_AsWKB(p.geom)::BLOB as geom_wkb -- Iceberg v2 has no geometry type.
from {{ source('tectonic_plates', 'plates') }} p