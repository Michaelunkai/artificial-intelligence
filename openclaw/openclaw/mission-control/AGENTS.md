# Repository Guidelines

## Project Structure & Module Organization
- `backend/`: FastAPI service. Main app code lives in `backend/app/` with API routes in `backend/app/api/`, data models in `backend/app/models/`, schemas in `backend/app/schemas/`, and service logic in `backend/app/services/`.
- `backend/migrations/`: Alembic migrations (`backend/migrations/versions/` for generated revisions).
- `backend/tests/`: pytest suite (`test_*.py` naming).
- `backend/templates/`: backend-shipped templates used by gateway flows.
- `frontend/`: Next.js app. Routes under `frontend/src/app/`, shared components under `frontend/src/components/`, utilities under `frontend/src/lib/`.
- `frontend/src/api/generated/`: generated API client; regenerate instead of editing by hand.
- `docs/`: contributor and operations docs (start at `docs/README.md`).

## Build, Test, and Development Commands
- `make setup`: install/sync backend and frontend dependencies.
- `make check`: closest CI parity run (lint, typecheck, tests/coverage, frontend build).
- `docker compose -f compose.yml --env-file .env up -d --build`: run full stack.
- Fast local loop:
  - `docker compose -f compose.yml --env-file .env up -d db`
  - `cd backend && uv run uvicorn app.main:app --reload --port 8000`
  - `cd frontend && npm run dev`
- `make api-gen`: regenerate frontend API client (backend must be on `127.0.0.1:8000`).

## Coding Style & Naming Conventions
- Python: Black + isort + flake8 + strict mypy. Max line length is 100. Use `snake_case`.
- TypeScript/React: ESLint + Prettier. Components use `PascalCase`; variables/functions use `camelCase`.
- For intentionally unused destructured TS variables, prefix with `_` to satisfy lint config.

## Testing Guidelines
- Backend: pytest via `make backend-test`; coverage policy via `make backend-coverage` (writes `backend/coverage.xml` and `backend/coverage.json`).
- Frontend: vitest + Testing Library via `make frontend-test` (coverage in `frontend/coverage/`).
- Add or update tests whenever behavior changes.

## Commit & Pull Request Guidelines
- Follow Conventional Commits (seen in history), e.g. `feat: ...`, `fix: ...`, `docs: ...`, `test(core): ...`.
- Keep PRs focused and based on latest `master`.
- Include: what changed, why, test evidence (`make check` or targeted commands), linked issue, and screenshots/logs when UI or operator workflow changes.

## Security & Configuration Tips
- Never commit secrets. Copy from `.env.example` and keep real values in local `.env`.
- Report vulnerabilities privately via GitHub security advisories, not public issues.


## Obsidian Unified Memory Vault

All agents share a persistent memory vault at `F:\backup\obsidion`. Use it to store and retrieve learnings, error patterns, project decisions, and cross-session context.

### Reading Memory
- **Hot memory (fast cache):** Read `F:\backup\obsidion\_hot-memory.md` first for top 50 critical items
- **Master index:** Search `F:\backup\obsidion\_index.md` by type/tag/title
- **Direct search:** Use filesystem MCP tools to search `F:\backup\obsidion\` recursively

### Writing Memory
- Drop new notes into `F:\backup\obsidion\_inbox\` with YAML frontmatter (title, type, tags, source, agent, workspace, importance 1-10, created, updated)
- Use templates from `F:\backup\obsidion\templates\` for consistent formatting
- Use `[[wiki-links]]` to connect related notes
- Never duplicate - search existing notes first and update instead

### What to Save
- Error patterns and fixes, technical learnings, project decisions, user preferences, agent coordination context
- Do NOT save: ephemeral task state, code (commit it), secrets, duplicates

### Skills Available
- `/vault-save` â€” Save a note to the vault
- `/vault-search` â€” Search vault for existing knowledge

### MANDATORY: Before any significant task
1. Read `F:\backup\obsidion\_hot-memory.md` for critical context
2. Search vault for relevant prior knowledge
3. After completing task: save learnings to vault
