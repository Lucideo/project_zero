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