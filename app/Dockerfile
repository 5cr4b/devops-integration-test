FROM python:3.12-slim@sha256:d764629ce0ddd8c71fd371e9901efb324a95789d2315a47db7e4d27e78f1b0e9 AS deps

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --target=/deps --requirement requirements.txt

FROM python:3.12-slim@sha256:d764629ce0ddd8c71fd371e9901efb324a95789d2315a47db7e4d27e78f1b0e9 AS runtime

LABEL org.opencontainers.image.title="integration-workload" \
      org.opencontainers.image.description="Validates PostgreSQL and Redis connectivity" \
      org.opencontainers.image.source="https://github.com/OWNER/devops-src-assignment"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/deps

WORKDIR /app

COPY --from=deps /deps /deps
COPY main.py .

USER 65532:65532

ENTRYPOINT ["python", "main.py"]
