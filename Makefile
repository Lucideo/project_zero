-include .env
export

###
# ingestion and transformation apps
###
COMPOSE := docker compose
BUILD ?=
build_ingestion:
	$(COMPOSE) --profile ingestion build
build_transformation:
	$(COMPOSE) --profile transformation build
run_ingestion:
	$(COMPOSE) run --rm $(BUILD) ingestion
run_transformation:
	$(COMPOSE) run --rm $(BUILD) transformation

###
# run lakehouse
###
# $(MAKE) re-reads the Makefile per step, so TOKEN is fetched after polaris is up
lakehouse_setup:
	$(MAKE) seaweed_up
	$(MAKE) create_bucket
	$(MAKE) polaris_db_up
	$(MAKE) polaris_up
	$(MAKE) polaris_create_catalog
	$(MAKE) polaris_set_dbt_credentials
	${MAKE} polaris_setup_namespaces

###
# wipe lakehouse and applications
###
wipe_environment:
	$(COMPOSE) --profile seaweed --profile polaris --profile polaris_db down -v

###
# run tests
###
run_smoke_test_s3:
	python3 -m venv smoke_test/.venv
	smoke_test/.venv/bin/pip install -r smoke_test/requirements.txt
	smoke_test/.venv/bin/python3 smoke_test/bronze.py
run_smoke_test_polaris:
	python3 -m venv smoke_test/.venv
	smoke_test/.venv/bin/pip install -r smoke_test/requirements.txt
	smoke_test/.venv/bin/python3 smoke_test/silver.py
run_smoke_test_duckdb_gold:
	python3 -m venv smoke_test/.venv
	smoke_test/.venv/bin/pip install -r smoke_test/requirements.txt
	smoke_test/.venv/bin/python3 smoke_test/duckdb_gold.py

run_ingestion_local_test:
	cd ingestion && \
	BRONZE_BUCKET_URL=${BRONZE_BUCKET_URL} DLT_S3_ACCESS_KEY=${DLT_S3_ACCESS_KEY} DLT_S3_SECRET_KEY=${DLT_S3_SECRET_KEY} S3_ENDPOINT_URL=${S3_ENDPOINT_URL_HOST} \
	uv run src/ingestion/main.py
VAR_LOCAL_TEST := STATIC_DATA_PATH=${CURDIR}/data/static_data/ DUCKDB_FILE_PATH=. DBT_DUMP_PATH=data/dbt_data_dump DBT_LOG_PATH=data/dbt_data_dump/logs DBT_TARGET_PATH=data/dbt_data_dump/target S3_ENDPOINT=${S3_ENDPOINT_HOST} \
	POLARIS_PRINCIPAL_CLIENT_ID=${POLARIS_PRINCIPAL_CLIENT_ID} POLARIS_PRINCIPAL_CLIENT_SECRET=${POLARIS_PRINCIPAL_CLIENT_SECRET} POLARIS_ENDPOINT_URL=${POLARIS_ENDPOINT_URL_HOST} POLARIS_CATALOG=${POLARIS_CATALOG}
run_transformation_local_test:
	cd transformation/dbt_transformation && \
	${VAR_LOCAL_TEST} uv run dbt deps && \
	${VAR_LOCAL_TEST} uv run dbt build

###
# seaweed and polaris
###

# set up seaweed
AWS_CLI_ADMIN := docker run --rm --network project-zero \
	-e AWS_ACCESS_KEY_ID=$(S3_ADMIN_KEY) -e AWS_SECRET_ACCESS_KEY=$(S3_ADMIN_SECRET) \
	-e AWS_DEFAULT_REGION=us-east-1 \
	amazon/aws-cli \
	--endpoint-url http://s3:8333
seaweed_up:
	$(COMPOSE) --profile seaweed up -d --wait

# manage seaweed buckets
create_bucket:
	$(AWS_CLI_ADMIN) s3 mb s3://bronze && $(AWS_CLI_ADMIN) s3 mb s3://silver && $(AWS_CLI_ADMIN) s3 mb s3://gold
delete_bucket:
	$(AWS_CLI_ADMIN) s3 rb s3://bronze --force && $(AWS_CLI_ADMIN) s3 rb s3://silver --force && $(AWS_CLI_ADMIN) s3 rb s3://gold --force
s3_ls:
	$(AWS_CLI_ADMIN) s3 ls ${LS_PATH} --recursive
s3_rm:
	$(AWS_CLI_ADMIN) s3 rm ${RM_PATH} --recursive

# set up polaris
polaris_db_up:
	$(COMPOSE) --profile polaris_db up -d --wait
	$(COMPOSE) --profile polaris_db_bootstrap --profile polaris_db run --rm polaris-bootstrap
polaris_up:
	$(COMPOSE) --profile polaris --profile seaweed --profile polaris_db up -d --wait
polaris_health:
	@curl -s http://localhost:8182/q/health | jq .status

# create and list polaris catalog
TOKEN := $(shell curl -s $(POLARIS_ENDPOINT_URL_HOST)/api/catalog/v1/oauth/tokens \
  -H "Polaris-Realm: $(POLARIS_REALM)" \
  -d grant_type=client_credentials -d client_id=${POLARIS_ROOT} -d client_secret=${POLARIS_ROOT_SECRET} \
  -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)
polaris_create_catalog:
	@curl -X POST $(POLARIS_ENDPOINT_URL_HOST)/api/management/v1/catalogs \
	-H "Authorization: Bearer $(TOKEN)" -H "Polaris-Realm: $(POLARIS_REALM)" \
	-H "Content-Type: application/json" -d @infra_seaweed_polaris/catalog.json
polaris_list_catalog:
	@curl -s $(POLARIS_ENDPOINT_URL_HOST)/api/management/v1/catalogs -H "Authorization: Bearer $(TOKEN)" -H "Polaris-Realm: $(POLARIS_REALM)"

# set polaris credentials for dbt
POLARIS_API := curl -sS --fail-with-body \
	-H "Authorization: Bearer $(TOKEN)" -H "Polaris-Realm: $(POLARIS_REALM)" \
	-H "Content-Type: application/json"
polaris_set_dbt_credentials:
	@$(POLARIS_API) -X POST $(POLARIS_ENDPOINT_URL_HOST)/api/management/v1/principals \
		-d '{"principal": {"name": "$(POLARIS_PRINCIPAL)"}}' | jq .credentials
	@$(POLARIS_API) -X POST $(POLARIS_ENDPOINT_URL_HOST)/api/management/v1/principal-roles \
		-d '{"principalRole": {"name": "$(POLARIS_PRINCIPAL_ROLE)"}}'
	@$(POLARIS_API) -X PUT $(POLARIS_ENDPOINT_URL_HOST)/api/management/v1/principals/$(POLARIS_PRINCIPAL)/principal-roles \
		-d '{"principalRole": {"name": "$(POLARIS_PRINCIPAL_ROLE)"}}'
	@$(POLARIS_API) -X POST $(POLARIS_ENDPOINT_URL_HOST)/api/management/v1/catalogs/$(POLARIS_CATALOG)/catalog-roles \
		-d '{"catalogRole": {"name": "$(POLARIS_CATALOG_ROLE)"}}'
	@$(POLARIS_API) -X PUT $(POLARIS_ENDPOINT_URL_HOST)/api/management/v1/catalogs/$(POLARIS_CATALOG)/catalog-roles/$(POLARIS_CATALOG_ROLE)/grants \
		-d '{"grant": {"type": "catalog", "privilege": "CATALOG_MANAGE_CONTENT"}}'
	@$(POLARIS_API) -X PUT $(POLARIS_ENDPOINT_URL_HOST)/api/management/v1/principal-roles/$(POLARIS_PRINCIPAL_ROLE)/catalog-roles/$(POLARIS_CATALOG) \
		-d '{"catalogRole": {"name": "$(POLARIS_CATALOG_ROLE)"}}'

# create schemas/namespaces in polaris catalog
polaris_setup_namespaces:
	@$(POLARIS_API) -X POST $(POLARIS_ENDPOINT_URL_HOST)/api/catalog/v1/$(POLARIS_CATALOG)/namespaces \
		-d '{"namespace": ["${POLARIS_NAMESPACE_SILVER}"], "properties": {"location": "s3://silver/${POLARIS_NAMESPACE_SILVER}/"}}'
	@$(POLARIS_API) -X POST $(POLARIS_ENDPOINT_URL_HOST)/api/catalog/v1/$(POLARIS_CATALOG)/namespaces \
		-d '{"namespace": ["${POLARIS_NAMESPACE_GOLD}"], "properties": {"location": "s3://gold/${POLARIS_NAMESPACE_GOLD}/"}}'
