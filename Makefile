### ingestion and transformation apps ###
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

### seaweed and polaris ###
-include .env
export

# set up seaweed
AWS_CLI_ADMIN := docker run --rm --network project-zero \
	-e AWS_ACCESS_KEY_ID=$(ADMIN_KEY) -e AWS_SECRET_ACCESS_KEY=$(ADMIN_SECRET) \
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

# set up polaris
polaris_db_up:
	$(COMPOSE) --profile polaris_db up -d --wait
	$(COMPOSE) --profile polaris_db_bootstrap --profile polaris_db run --rm polaris-bootstrap

polaris_up:
	$(COMPOSE) --profile polaris --profile seaweed --profile polaris_db up -d --wait

polaris_health:
	@curl -s http://localhost:8182/q/health | jq .status

# create and list polaris catalog
TOKEN := $(shell curl -s $(POLARIS_ENDPOINT_URL)/api/catalog/v1/oauth/tokens \
  -H "Polaris-Realm: $(POLARIS_REALM)" \
  -d grant_type=client_credentials -d client_id=${POLARIS_ROOT} -d client_secret=${POLARIS_ROOT_SECRET} \
  -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)

polaris_create_catalog:
	@curl -X POST $(POLARIS_ENDPOINT_URL)/api/management/v1/catalogs \
	-H "Authorization: Bearer $(TOKEN)" -H "Polaris-Realm: $(POLARIS_REALM)" \
	-H "Content-Type: application/json" -d @infra_seaweed_polaris/catalog.json

polaris_list_catalog:
	@curl -s $(POLARIS_ENDPOINT_URL)/api/management/v1/catalogs -H "Authorization: Bearer $(TOKEN)" -H "Polaris-Realm: $(POLARIS_REALM)"

# set polaris credentials for dbt
MGMT := $(POLARIS_ENDPOINT_URL)/api/management/v1

POLARIS_API := curl -sS --fail-with-body \
	-H "Authorization: Bearer $(TOKEN)" -H "Polaris-Realm: $(POLARIS_REALM)" \
	-H "Content-Type: application/json"

polaris_set_dbt_credentials:
	@$(POLARIS_API) -X POST $(MGMT)/principals \
		-d '{"principal": {"name": "$(POLARIS_PRINCIPAL)"}}' | jq .credentials
	@$(POLARIS_API) -X POST $(MGMT)/principal-roles \
		-d '{"principalRole": {"name": "$(POLARIS_PRINCIPAL_ROLE)"}}'
	@$(POLARIS_API) -X PUT $(MGMT)/principals/$(POLARIS_PRINCIPAL)/principal-roles \
		-d '{"principalRole": {"name": "$(POLARIS_PRINCIPAL_ROLE)"}}'
	@$(POLARIS_API) -X POST $(MGMT)/catalogs/$(POLARIS_CATALOG)/catalog-roles \
		-d '{"catalogRole": {"name": "$(POLARIS_CATALOG_ROLE)"}}'
	@$(POLARIS_API) -X PUT $(MGMT)/catalogs/$(POLARIS_CATALOG)/catalog-roles/$(POLARIS_CATALOG_ROLE)/grants \
		-d '{"grant": {"type": "catalog", "privilege": "CATALOG_MANAGE_CONTENT"}}'
	@$(POLARIS_API) -X PUT $(MGMT)/principal-roles/$(POLARIS_PRINCIPAL_ROLE)/catalog-roles/$(POLARIS_CATALOG) \
		-d '{"catalogRole": {"name": "$(POLARIS_CATALOG_ROLE)"}}'

# smoke_test
run_smoke_test_s3:
	python3 -m venv smoke_test/.venv
	smoke_test/.venv/bin/pip install -r smoke_test/requirements.txt
	smoke_test/.venv/bin/python3 smoke_test/bronze.py
run_smoke_test_polaris:
	python3 -m venv smoke_test/.venv
	smoke_test/.venv/bin/pip install -r smoke_test/requirements.txt
	smoke_test/.venv/bin/python3 smoke_test/silver.py

d_analysis::
	smoke_test/.venv/bin/python3 scripts/analysis.py