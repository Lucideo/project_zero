-include .env
export

COMPOSE := docker compose
BUILD ?= 

build_ingestion:
	$(COMPOSE) --profile ingestion build $(BUILD)

build_transformation:
	$(COMPOSE) --profile transformation build $(BUILD)

run_ingestion:
	$(COMPOSE) --profile ingestion up -d $(BUILD)
	$(COMPOSE) --profile ingestion logs

run_transformation:
	$(COMPOSE) --profile transformation up -d $(BUILD)
	$(COMPOSE) --profile transformation logs