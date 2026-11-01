import os
import duckdb

conn = duckdb.connect()

conn.sql("INSTALL httpfs; LOAD httpfs; INSTALL iceberg; LOAD iceberg;")

# s3 secrect
conn.sql(f"""
CREATE SECRET (TYPE s3, KEY_ID '{os.environ["DUCKDB_S3_ACCESS_KEY"]}', SECRET '{os.environ["DUCKDB_S3_SECRET_KEY"]}',
    ENDPOINT '{os.environ["S3_ENDPOINT_HOST"]}', URL_STYLE 'path', USE_SSL false, REGION '{os.environ["AWS_REGION"]}')
""")

# iceberg secret
conn.sql(f"""
CREATE SECRET polaris (TYPE iceberg, CLIENT_ID '{os.environ["POLARIS_PRINCIPAL_CLIENT_ID"]}', CLIENT_SECRET '{os.environ["POLARIS_PRINCIPAL_CLIENT_SECRET"]}',
    OAUTH2_SERVER_URI '{os.environ["POLARIS_ENDPOINT_URL_HOST"]}/api/catalog/v1/oauth/tokens',
    OAUTH2_SCOPE 'PRINCIPAL_ROLE:ALL')
""")

# attach catalog
conn.sql(f"""
    ATTACH 'usgs' AS silver (TYPE iceberg, ENDPOINT '{os.environ["POLARIS_ENDPOINT_URL_HOST"]}/api/catalog',
        SECRET polaris, ACCESS_DELEGATION_MODE 'none')
""")

raw_parquet_path = 's3://bronze/raw_data.parquet'

print('Creating schema..')
conn.sql("CREATE SCHEMA IF NOT EXISTS silver.usgs") # create schema/namespace
print('Creating table..')
conn.sql("DROP TABLE IF EXISTS silver.usgs.earthquakes")
conn.sql(f"CREATE TABLE silver.usgs.earthquakes AS SELECT * FROM read_parquet('{raw_parquet_path}')")
print('Querying created table..')
conn.sql("SELECT * FROM silver.usgs.earthquakes limit 5").show()