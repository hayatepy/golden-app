"""Isolate application persistence from the developer's local golden database."""

from collections.abc import Iterator
from pathlib import Path

import pytest
from hayate_sql.adapters import SQLiteDatabase

import storage


@pytest.fixture(scope="session", autouse=True)
def isolated_application_database(tmp_path_factory: pytest.TempPathFactory) -> Iterator[None]:
    database = SQLiteDatabase(tmp_path_factory.mktemp("golden-database") / "app.db")
    migrations = Path(__file__).resolve().parents[1] / "migrations"
    for migration in sorted(migrations.glob("*.sql")):
        database.raw.executescript(migration.read_text(encoding="utf-8"))

    storage._sqlite = database
    try:
        yield
    finally:
        storage._sqlite = None
        database.raw.close()
