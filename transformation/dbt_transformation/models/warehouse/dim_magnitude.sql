select
    magtype,
    name,
    description,
    typical_magnitude_range,
    typical_distance_range
from {{ ref("stg_magtype") }}