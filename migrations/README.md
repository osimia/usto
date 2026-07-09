# USTO Migrations

Production backend should use PostgreSQL migrations from this directory.

The current Go prototype still creates the demo SQLite schema in code so the existing web prototype keeps running. During Phase 1, move schema creation from `main.go` into SQL migrations and switch local development to PostgreSQL.

Recommended tool:

```bash
goose -dir migrations postgres "$DATABASE_URL" up
```
