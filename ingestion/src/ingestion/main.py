import dlt
from dlt.sources.rest_api import rest_api_source
from dlt.destinations import filesystem
from datetime import datetime, timezone
import os

def ms_to_iso(ms):
    return datetime.fromtimestamp(ms / 1000, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")

def main():
    print("Starting..\n")
    source = rest_api_source({
        "client": {
            "base_url": "https://earthquake.usgs.gov/fdsnws/event/1/",
            "paginator": "single_page",
        },
        "resources": [
            {
                "name": "earthquakes",
                "primary_key": "id",
                "endpoint": {
                    "path": "query",
                    "data_selector": "features",
                    "params": {
                        "format": "geojson",
                        # "reviewstatus": "reviewed",
                        "minmagnitude": "5",
                        # "minlatitude": "-56",
                        # "maxlatitude": "13",
                        # "minlongitude": "-82",
                        # "maxlongitude": "-34",
                        "starttime": "2020-01-01",
                        "updatedafter": {
                            "type": "incremental",
                            "cursor_path": "properties.updated",
                            "initial_value": 1577836800000,  # 2020-01-01 in ms
                            "convert": ms_to_iso,
                        },
                    }
                }
            }
        ]
    })

    destination_bucket = os.getenv("DESTINATION_BUCKET")
    if not destination_bucket:
        raise RuntimeError("DESTINATION_BUCKET environment variable is not set")

    pipeline = dlt.pipeline(
        pipeline_name = "earthquakes",
        destination = filesystem(bucket_url=destination_bucket),
        dataset_name = "usgs_earthquakes"
    )

    full = os.getenv('LOAD_MODE', 'incremental').lower() == 'full'

    print(f'Load mode full: {full}')
    
    load_info = pipeline.run(
        source, 
        loader_file_format="parquet",
        refresh="drop_sources" if full else None
    )

    print("\nload_info: ", load_info)
    row_counts = pipeline.last_trace.last_normalize_info.row_counts
    print("\nNew earthquakes:", row_counts.get("earthquakes", 0))
    print("\n..Ending")

if __name__ == "__main__":
    main()