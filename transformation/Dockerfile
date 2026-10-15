FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:0.13.1 /uv /bin/

WORKDIR /docker_app

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

COPY . .

ENV DBT_PROFILES_DIR="/docker_app/dbt_transformation"
ENV DBT_PROJECT_DIR="/docker_app/dbt_transformation"

RUN uv run dbt deps

ENV PATH="/docker_app/.venv/bin:$PATH"
ENTRYPOINT ["dbt"]
CMD ["build"]