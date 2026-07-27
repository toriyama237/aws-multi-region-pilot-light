# Notes API

A small CRUD service over PostgreSQL. It is intentionally boring: the whole point of this repository is the multi-region architecture wrapped around it, so the application stays minimal and identical in both regions.

## Endpoints

| Method | Path | Purpose |
| ------ | ---- | ------- |
| GET | /healthz | Liveness. Answers as long as the process runs, never touches the database. |
| GET | /health | Readiness. Runs SELECT 1 against PostgreSQL and returns 503 if it fails. This is the endpoint the ALB target group and, indirectly, the Route 53 health check observe. |
| POST | /notes | Create a note. |
| GET | /notes | List notes, newest first, with limit and offset. |
| GET | /notes/{id} | Fetch one note. |
| PUT | /notes/{id} | Update a note. |
| DELETE | /notes/{id} | Delete a note. |

Every response carries an X-Serving-Region header. During a failover drill this is the quickest way to prove that traffic moved to the secondary region without changing the URL.

## Configuration

All configuration comes from the environment. The Terraform user data injects the right values per region.

| Variable | Required | Description |
| -------- | -------- | ----------- |
| DB_HOST | yes | PostgreSQL endpoint for the local region. |
| DB_PORT | no | Defaults to 5432. |
| DB_NAME | no | Defaults to notes. |
| DB_USER | yes | Database user. |
| DB_PASSWORD | yes | Database password, sourced from Secrets Manager at boot. |
| DB_SSLMODE | no | Defaults to require. Only the local drill, where PostgreSQL runs in plain containers, relaxes it. |
| APP_REGION | no | Region label surfaced in responses, defaults to unknown. |

## Health check design

The readiness probe deliberately couples instance health to database reachability. An instance that cannot reach its data layer should not receive traffic, and in the primary region a fully broken data layer should eventually surface as a failed Route 53 health check and trigger the DNS failover. Liveness stays independent of the database so that an RDS incident does not make the process restart in a loop.

## Running locally

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DB_HOST=localhost DB_USER=notes DB_PASSWORD=notes APP_REGION=local
uvicorn notes_api.main:app --host 0.0.0.0 --port 8000
```

## Tests

```bash
pip install pytest httpx
pytest tests/
```

The test suite covers the API contract and the health endpoint semantics with a stubbed database. Data access itself is exercised against the real RDS instance once deployed.
