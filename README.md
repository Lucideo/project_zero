# USGS Earthquake Data pipeline + Lakehouse

An end-to-end data pipeline that ingests earthquake events from the [USGS Earthquake API](https://earthquake.usgs.gov/fdsnws/event/1/), lands them as raw parquet and models them into an iceberg based star schema following the medallion architecture (bronze > silver > gold).

The project runs fully local on Docker, using open-source components that mirror AWS managed services. That makes the same design portable to the cloud later with minimal changes.

## Architecture

| Role | Local | Cloud equivalent (planned) |
|---|---|---|
| Object storage | SeaweedFS (S3 API) | Amazon S3 |
| Iceberg catalog | Apache Polaris (Iceberg REST catalog) | AWS Glue Data Catalog |
| Ingestion | dlt in a Docker container | dlt on AWS Lambda |
| Transformation | dbt-duckdb in a Docker container | dbt-duckdb on Fargate / Lambda |
| Query interface | DuckDB | Amazon Athena |
| Orchestrator | Airflow (planned) | Step Functions + EventBridge Scheduler |

---

### Layers

| Layer  | Bucket          | Format          | Written by | Contents |
| ------ | --------------- | --------------- | ---------- | -------- |
| Bronze | `s3://bronze`   | Parquet         | dlt        | Raw USGS GeoJSON features (`usgs_earthquakes/earthquakes`, `earthquakes__geometry__coordinates`) |
| Silver | `s3://silver`   | Iceberg (Polaris) | dbt      | Cleaned and typed staging models (`stg_boundaries`, `stg_date`, `stg_earthquakes`, `stg_magtype`, `stg_natural_earth_countries`, `stg_plates`) |
| Gold   | `s3://gold`     | Iceberg (Polaris) | dbt      | Dimensional model: `fact_earthquakes`, `dim_date`, `dim_location`, `dim_magnitude`, `dim_plate`, `dim_boundary` |

Besides the API data, the transformation layer enriches events with static reference data in [data/static_data/](data/static_data/):
- **Natural Earth countries**: maps each event to a country or flags it as international waters (> 200 km from land).
- **Tectonic plates and boundaries**: assigns each event to a plate and the nearest plate boundary.
- **Magnitude type seed** ([geojson_magtype_description.csv](transformation/dbt_transformation/seeds/geojson_magtype_description.csv)): descriptions of USGS magnitude types.

---

## Tech stack

- **Ingestion**: [dlt](https://dlthub.com/) `rest_api_source` > filesystem destination (Parquet on S3)
- **Transformation**: [dbt-core](https://www.getdbt.com/) + [dbt-duckdb](https://github.com/duckdb/dbt-duckdb) with the `spatial`, `httpfs` and `iceberg` extensions
- **Object storage**: [SeaweedFS](https://github.com/seaweedfs/seaweedfs) (S3-compatible API)
- **Table format / catalog**: [Apache Iceberg](https://iceberg.apache.org/) + [Apache Polaris](https://polaris.apache.org/) (REST catalog, Postgres-backed)
- **Query engine**: DuckDB
- **Packaging**: Docker / Docker Compose, Python managed with [uv](https://docs.astral.sh/uv/)
- **Planned**: Airflow (orchestration), Terraform (cloud infra)

---

## Iceberg workarounds (dbt-duckdb + Polaris)

- **No rename in the same transaction.** DuckDB's Iceberg extension can't rename a table in the same transaction that created it, and dbt-duckdb's default `table` materialization builds a `__dbt_tmp` table and then renames it. Models in `staging` and `warehouse` therefore use a custom `iceberg_table` materialization ([iceberg_table.sql](transformation/dbt_transformation/macros/materializations/iceberg_table.sql)). It drops the existing table and recreates it with `CREATE TABLE AS` instead of renaming, so a table is briefly missing while it's rebuilt.
- **Full refresh of incremental models.** For the same reason, an `on-run-start` hook ([drop_incrementals_on_full_refresh.sql](transformation/dbt_transformation/macros/drop_incrementals_on_full_refresh.sql)) drops incremental models (e.g. `fact_earthquakes`) before a `--full-refresh`, so dbt creates them directly.
- **No geometry type in Iceberg v2.** Polaris creates Iceberg v2 tables, and v2 has no geometry type. Silver models store shapes as WKB in a `geom_wkb` (`BLOB`) column. Use `ST_GeomFromWKB(geom_wkb)` to get the geometry back when querying or doing spatial joins. This also keeps the tables readable by Glue and Athena in the future cloud setup.
- **Schema name prefix.** DuckDB prefixes every namespace with `main_` (e.g. `main_usgs_gold`). The [generate_schema_name](transformation/dbt_transformation/macros/generate_schema_name.sql) macro overrides this so models land in `usgs_silver` and `usgs_gold`.

---

## Roadmap

- [ ] Orchestrate ingestion and transformation with **Airflow**
- [ ] Cloud deployment with **Terraform**:
  - Lambda (dlt) → S3 bronze
  - Fargate / Lambda (dbt-duckdb) → S3 + Iceberg + Glue Catalog
  - Athena as the query interface
  - Step Functions + EventBridge Scheduler for orchestration

---

## Repository layout

```
.
├── compose.yaml                       # ingestion + transformation services (includes infra compose)
├── Makefile                           # all setup / run / test entry points
├── .env.example                       # environment template
├── infra_seaweed_polaris/
│   ├── compose_seaweed_polaris.yaml   # SeaweedFS (master, volume, filer, s3) + Polaris + Postgres
│   ├── s3.json                        # SeaweedFS S3 identities and bucket permissions
│   └── catalog.json                   # Polaris "usgs" catalog definition
├── ingestion/                         # dlt pipeline (src/ingestion/main.py) + Dockerfile
├── transformation/
│   ├── Dockerfile
│   └── dbt_transformation/            # dbt project
│       ├── models/staging/            # silver models (stg_*)
│       ├── models/warehouse/          # gold models (dim_*, fact_earthquakes)
│       ├── macros/                    # Iceberg workarounds + classification helpers
│       └── seeds/                     # Magtype description csv
├── smoke_test/                        # S3 and Polaris connectivity python checks
└── data/
    ├── static_data/                   # country and tectonic plate GeoJSON (mounted volume)
    └── dbt_data_dump/                 # dbt logs and target artifacts (mounted volume)
```

---

## Prerequisites

- Docker with Docker Compose v2
- `make`, `curl`, `jq`
- Python 3 (for the smoke tests)
- [uv](https://docs.astral.sh/uv/) (only for the local, non-container test runs)

---

## How to run

1. Create the `.env` file:
   ```bash
   cp .env.example .env
   ```
2. Start and configure the lakehouse (SeaweedFS, buckets, Polaris, catalog, dbt principal, namespaces):
   ```bash
   make lakehouse_setup
   ```
   > lakehouse_setup only needs to run once. To start over from scratch, run make wipe_environment first.
3. Copy the `client_id` and `client_secret` printed in the step 2 logs into `.env`, as `POLARIS_PRINCIPAL_CLIENT_ID` and `POLARIS_PRINCIPAL_CLIENT_SECRET`. They are printed only once, so save them right away.
   > If credential goes missing, wipe the environment. Look Useful commands section for help.
4. Build and run ingestion (USGS API > bronze):
   ```bash
   make build_ingestion
   make run_ingestion
   ```
5. Build and run transformation (bronze > silver > gold):
   ```bash
   make build_transformation
   make run_transformation
   ```

> Pass `BUILD=--build` to rebuild the image as part of a run, e.g. `make run_ingestion BUILD=--build`.

### Load modes

Ingestion is **incremental** by default. dlt tracks the USGS `updated` timestamp as a cursor, so each run only fetches events created or updated since the last run (starting from 2020-01-01, magnitude ≥ 5).

To reload everything from scratch, set `LOAD_MODE=full` in `.env`. dlt drops its source state and re-ingests the full history.

### dbt targets

`TARGET_ENV` selects the dbt profile target:
- `dev` (default): `dev.duckdb`, 1 thread
- `prod`: `warehouse.duckdb`, 4 threads

Both targets write their Iceberg tables to the same Polaris catalog.

---

## How to test

1. Create `.env` and start the lakehouse (steps 1–3 above).
2. Run the S3 and Polaris smoke tests:
   - `run_smoke_test_s3` writes a sample USGS CSV feed as Parquet to `s3://bronze/raw_data.parquet` and reads it back.
   - `run_smoke_test_polaris` attaches the Polaris catalog through DuckDB, creates an Iceberg table from that Parquet file and queries it. Run it after the S3 test, because it depends on that file.
   > s3 smoke test leaves files on bronze and silver buckets, it's recommended to remove them. See Useful commands section for help.
3. Run ingestion and transformation from the host (outside Docker) using uv:
   - `make run_ingestion_local_test`
   - `make run_transformation_local_test`
4. Run the Duckdb gold layer smoke test:
   - `make run_smoke_test_duckdb_gold` 

---

## Useful commands

| Command | What it does |
| ------- | ------------ |
| `make seaweed_up` | Start SeaweedFS only |
| `make create_bucket` / `make delete_bucket` | Create / force-delete the bronze, silver and gold buckets |
| `make s3_ls LS_PATH=s3://bronze` | List objects in a bucket recursively |
| `make s3_rm RM_PATH=s3://bronze/<myfileorfolder>` | Remove objects in a bucket recursively |
| `make polaris_db_up` | Setup container and bootstrap postgres for polaris |
| `make polaris_up` | Setup polaris container |
| `make polaris_health` | Check Polaris health status |
| `make polaris_create_catalog` | Setup catalog on polaris from infra_seaweed_polaris/catalog.json |
| `make polaris_list_catalog` | List Polaris catalogs |
| `make polaris_set_dbt_credentials` | Create the dbt principal, roles and grants (prints new credentials) |
| `make polaris_setup_namespaces` | Create the `usgs_silver` and `usgs_gold` namespaces |
| `make wipe_environment` | Stop and wipe containers and volumes |

### Service endpoints (from the host)

| Service | URL |
| ------- | --- |
| SeaweedFS S3 API | http://localhost:8333 |
| SeaweedFS master | http://localhost:9333 |
| SeaweedFS filer | http://localhost:8888 |
| Polaris REST catalog | http://localhost:8181 |
| Polaris health / management | http://localhost:8182/q/health |

---

## Access control

### S3 (SeaweedFS)

There are 3 buckets: `bronze`, `silver` and `gold`. Identities are defined in [infra_seaweed_polaris/s3.json](infra_seaweed_polaris/s3.json):

| Identity    | bronze      | silver      | gold        |
| ----------- | ----------- | ----------- | ----------- |
| `lab_admin` | admin       | admin       | admin       |
| `dlt`       | read/write  | —           | —           |
| `duckdb` (dbt) | read/write | read/write | read/write |
| `polaris`   | —           | read/write  | read/write  |

### Polaris

- Catalog `usgs` (type `INTERNAL`) manages the `silver` and `gold` buckets, defined in [infra_seaweed_polaris/catalog.json](infra_seaweed_polaris/catalog.json).
- Principal `dbt-duckdb` > principal role `dbt-duckdb-role` > catalog role `usgs-admin` with the `CATALOG_MANAGE_CONTENT` privilege.
- `POLARIS_PRINCIPAL_CLIENT_ID` and `POLARIS_PRINCIPAL_CLIENT_SECRET` are generated when the principal is created (`make polaris_set_dbt_credentials` or `make lakehouse_setup`). They are printed only once, so save them right away.
- Polaris runs with `stsUnavailable: true` and `access_delegation_mode: none`. Clients use their own S3 credentials instead of vended credentials, because SeaweedFS has no STS.

> All credentials in `.env.example` and `s3.json` are local development defaults. Change them before exposing any service outside your machine.