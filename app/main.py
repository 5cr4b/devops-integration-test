import logging
import os
import sys
import time

import psycopg
import redis


LOG_FORMAT = "%(asctime)s %(levelname)s %(message)s"
TEST_KEY = "test-key"
TEST_VALUE = "test-value"


def env(name: str, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if value is None:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def retry(operation_name: str, operation, attempts: int = 30, delay_seconds: int = 2):
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            logging.info("Starting %s attempt %s/%s", operation_name, attempt, attempts)
            return operation()
        except Exception as exc:  # noqa: BLE001 - log and retry transient startup failures.
            last_error = exc
            logging.warning("%s attempt %s failed: %s", operation_name, attempt, exc)
            if attempt < attempts:
                time.sleep(delay_seconds)
    raise RuntimeError(f"{operation_name} failed after {attempts} attempts") from last_error


def validate_postgres() -> None:
    host = env("POSTGRES_HOST")
    port = int(env("POSTGRES_PORT", "5432"))
    database = env("POSTGRES_DB", "app")
    user = env("POSTGRES_USER", "app")
    password = env("POSTGRES_PASSWORD")

    def work() -> None:
        logging.info("Connecting to PostgreSQL at %s:%s/%s", host, port, database)
        with psycopg.connect(
            host=host,
            port=port,
            dbname=database,
            user=user,
            password=password,
            connect_timeout=5,
        ) as connection:
            with connection.cursor() as cursor:
                logging.info("Creating PostgreSQL validation table if needed")
                cursor.execute(
                    """
                    CREATE TABLE IF NOT EXISTS integration_validation (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL
                    )
                    """
                )
                logging.info("Writing PostgreSQL validation record")
                cursor.execute(
                    """
                    INSERT INTO integration_validation (key, value)
                    VALUES (%s, %s)
                    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
                    """,
                    (TEST_KEY, TEST_VALUE),
                )
                logging.info("Reading PostgreSQL validation record")
                cursor.execute(
                    "SELECT value FROM integration_validation WHERE key = %s",
                    (TEST_KEY,),
                )
                row = cursor.fetchone()
                if row is None or row[0] != TEST_VALUE:
                    raise RuntimeError(f"PostgreSQL validation failed: expected {TEST_VALUE}, got {row}")
                connection.commit()
        logging.info("PostgreSQL validation succeeded")

    retry("PostgreSQL validation", work)


def validate_redis() -> None:
    host = env("REDIS_HOST")
    port = int(env("REDIS_PORT", "6379"))
    password = env("REDIS_PASSWORD")

    def work() -> None:
        logging.info("Connecting to Redis at %s:%s", host, port)
        client = redis.Redis(
            host=host,
            port=port,
            password=password,
            socket_connect_timeout=5,
            socket_timeout=5,
            decode_responses=True,
        )
        logging.info("Writing Redis validation record")
        client.set(TEST_KEY, TEST_VALUE)
        logging.info("Reading Redis validation record")
        value = client.get(TEST_KEY)
        if value != TEST_VALUE:
            raise RuntimeError(f"Redis validation failed: expected {TEST_VALUE}, got {value}")
        logging.info("Redis validation succeeded")

    retry("Redis validation", work)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
    logging.info("Starting integration validation workload")

    if os.getenv("FORCE_FAIL", "false").lower() == "true":
        logging.error("FORCE_FAIL=true was set; intentionally failing workload")
        return 1

    try:
        validate_postgres()
        validate_redis()
    except Exception:
        logging.exception("Integration validation failed")
        return 1

    logging.info("Integration validation completed successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main())
