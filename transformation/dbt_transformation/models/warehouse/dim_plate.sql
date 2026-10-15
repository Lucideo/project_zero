select
    id,
    code_plate,
    name
from
    {{ ref('stg_plates') }}