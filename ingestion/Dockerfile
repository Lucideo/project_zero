FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:0.13.1 /uv /bin/

WORKDIR /docker_app

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

COPY . .
RUN uv sync --locked --no-dev

ENV PATH="/docker_app/.venv/bin:$PATH"
CMD ["python3", "src/ingestion/main.py"]

# ENTRYPOINT ["uv", "run"]
# CMD ["python3", "src/ingestion/main.py"]