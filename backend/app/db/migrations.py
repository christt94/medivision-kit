"""Explicit migration registry for the local SQLite installation.

The original release used ``create_all`` only. Future schema changes should be
added as numbered functions here so desktop upgrades can run before startup.
"""

from sqlalchemy import text

from app.db import models  # noqa: F401 - registers all models with metadata
from app.db.database import Base, engine


async def run_migrations() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(text("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """))
        result = await conn.execute(text("SELECT version FROM schema_migrations"))
        versions = {row[0] for row in result.fetchall()}
        if 1 not in versions:
            await conn.execute(text("INSERT INTO schema_migrations (version) VALUES (1)"))
