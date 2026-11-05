import os
import duckdb

conn = duckdb.connect()

conn.sql("INSTALL httpfs; LOAD httpfs; INSTALL iceberg; LOAD iceberg;")

# s3 secret
print('Creating s3 secret..')
conn.sql(f"""
CREATE SECRET (TYPE s3, KEY_ID '{os.environ["DUCKDB_S3_ACCESS_KEY"]}', SECRET '{os.environ["DUCKDB_S3_SECRET_KEY"]}',
    ENDPOINT '{os.environ["S3_ENDPOINT_HOST"]}', URL_STYLE 'path', USE_SSL false, REGION '{os.environ["AWS_REGION"]}')
""")

# polaris secret
print('Creating polaris secret..')
conn.sql(f"""
CREATE SECRET polaris (TYPE iceberg, CLIENT_ID '{os.environ["POLARIS_PRINCIPAL_CLIENT_ID"]}', CLIENT_SECRET '{os.environ["POLARIS_PRINCIPAL_CLIENT_SECRET"]}',
    OAUTH2_SERVER_URI '{os.environ["POLARIS_ENDPOINT_URL_HOST"]}/api/catalog/v1/oauth/tokens',
    OAUTH2_SCOPE 'PRINCIPAL_ROLE:ALL')
""")

# attach catalog
catalog_name = os.environ['POLARIS_CATALOG']
print(f'Attaching {catalog_name} catalog..')
conn.sql(f"""
    ATTACH {catalog_name} AS lakehouse (TYPE iceberg, ENDPOINT '{os.environ["POLARIS_ENDPOINT_URL_HOST"]}/api/catalog',
        SECRET polaris, ACCESS_DELEGATION_MODE 'none')
""")

source_bucket_url = os.environ['BRONZE_BUCKET_URL']
namespace = os.environ['POLARIS_NAMESPACE_SILVER']

raw_parquet_path = f'{source_bucket_url}/raw_data.parquet'

print('Creating schema..')
conn.sql(f"CREATE SCHEMA IF NOT EXISTS lakehouse.{namespace}") # create schema/namespace
print('Creating table..')
conn.sql(f"DROP TABLE IF EXISTS lakehouse.{namespace}.earthquakes")
conn.sql(f"CREATE TABLE lakehouse.{namespace}.earthquakes AS SELECT * FROM read_parquet('{raw_parquet_path}')")
print('Querying created table..')
conn.sql(f"SELECT * FROM lakehouse.{namespace}.earthquakes limit 5").show()

conn.sql(f'DROP TABLE lakehouse.{namespace}.earthquakes')
