select
    id,
    code_boundary,
    name,
    plate_a,
    name_plate_a,
    plate_b,
    name_plate_b,
    type
from
    {{ ref("stg_boundaries") }}