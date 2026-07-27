#!/usr/bin/env bash
# Local failover drill.
#
# Reproduces the whole pilot light pattern on a laptop with Docker, no
# AWS account needed: a writable PostgreSQL primary, an asynchronous
# streaming replica (the local stand-in for the RDS cross-region
# replica), and two instances of the real API, one per simulated
# region. It then kills the primary database, promotes the replica and
# measures how long the data layer takes to accept writes again, plus
# whether any pre-disaster write was lost.
#
# What this validates: the application code, the health check
# semantics that drive DNS failover, and the promotion mechanics.
# What it cannot validate: Route 53 itself, RDS promotion duration
# (minutes on AWS, instant here) and everything IAM. Those need the
# real deployment.
#
# Requirements: docker, python3 with venv, curl. Ports 5541, 5542,
# 8001, 8002 must be free.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d /tmp/pilot-drill.XXXXXX)
NET="pilot-drill-$$"
PRIMARY_PG="pg-primary-$$"
REPLICA_PG="pg-replica-$$"
APP_PIDS=()

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

cleanup() {
  log "Cleaning up"
  for pid in "${APP_PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  docker rm -f "$PRIMARY_PG" "$REPLICA_PG" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

log "Preparing python environment"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" -q install -r "$ROOT/app/requirements.txt"

log "Starting the primary database (simulated primary region)"
docker network create "$NET" >/dev/null
cat > "$WORK/init-replication.sh" <<'EOF'
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "CREATE ROLE repl WITH REPLICATION LOGIN PASSWORD 'replpass';"
echo "host replication repl all scram-sha-256" >> "$PGDATA/pg_hba.conf"
EOF
chmod +x "$WORK/init-replication.sh"
docker run -d --name "$PRIMARY_PG" --network "$NET" -p 5541:5432 \
  -e POSTGRES_USER=notes_admin -e POSTGRES_PASSWORD=drillpass -e POSTGRES_DB=notes \
  -v "$WORK/init-replication.sh":/docker-entrypoint-initdb.d/init-replication.sh:ro \
  postgres:16 -c wal_level=replica -c max_wal_senders=10 >/dev/null
until docker exec "$PRIMARY_PG" pg_isready -U notes_admin -q; do sleep 1; done

log "Starting the streaming replica (simulated secondary region)"
docker run -d --name "$REPLICA_PG" --network "$NET" -p 5542:5432 \
  -e PGPASSWORD=replpass postgres:16 bash -c "
until pg_basebackup -h $PRIMARY_PG -U repl -D /var/lib/postgresql/data -R -X stream; do
  rm -rf /var/lib/postgresql/data/*; sleep 2
done
chown -R postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data
exec gosu postgres postgres" >/dev/null
until docker exec "$REPLICA_PG" psql -U notes_admin -d notes -tAc "SELECT pg_is_in_recovery()" 2>/dev/null | grep -q t; do sleep 1; done
log "Replication is streaming"

start_app() { # port, pg_port, region
  (cd "$ROOT/app" && DB_HOST=127.0.0.1 DB_PORT="$2" DB_NAME=notes \
    DB_USER=notes_admin DB_PASSWORD=drillpass DB_SSLMODE=disable APP_REGION="$3" \
    "$WORK/venv/bin/uvicorn" notes_api.main:app --host 127.0.0.1 --port "$1" \
    > "$WORK/app-$3.log" 2>&1) &
  APP_PIDS+=($!)
}

log "Starting both regional API instances with the real application code"
start_app 8001 5541 eu-west-1
start_app 8002 5542 eu-west-3
until curl -sf http://127.0.0.1:8001/health >/dev/null; do sleep 1; done
until curl -sf http://127.0.0.1:8002/health >/dev/null; do sleep 1; done
log "Both regions healthy. The secondary serves reads from its replica."

log "Nominal phase: writing through the primary region"
for i in 1 2 3; do
  curl -sf -o /dev/null -X POST http://127.0.0.1:8001/notes \
    -H 'Content-Type: application/json' \
    -d "{\"title\": \"note $i before disaster\", \"body\": \"payload\"}"
done
curl -sf -o /dev/null -X POST http://127.0.0.1:8001/notes \
  -H 'Content-Type: application/json' \
  -d '{"title": "last write before disaster", "body": "if this survives, RPO is zero"}'
sleep 1
# The API answers on a single line, so count occurrences, not lines.
REPLICATED=$(curl -sf http://127.0.0.1:8002/notes | grep -o '"title"' | wc -l)
log "Secondary region sees $REPLICATED notes through replication"

log "DISASTER: killing the primary database"
T0=$(date +%s.%N)
docker kill "$PRIMARY_PG" >/dev/null

PRIMARY_HEALTH=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1:8001/health)
log "Primary region /health now answers HTTP $PRIMARY_HEALTH (Route 53 would fail over on this)"

log "Promoting the replica (stand-in for aws rds promote-read-replica)"
docker exec "$REPLICA_PG" psql -U notes_admin -d notes -c "SELECT pg_promote();" >/dev/null

until curl -s --max-time 3 -o /dev/null -w '%{http_code}' \
  -X POST http://127.0.0.1:8002/notes \
  -H 'Content-Type: application/json' \
  -d '{"title": "first write after failover", "body": "served by the secondary"}' | grep -q 201; do
  sleep 0.3
done
T1=$(date +%s.%N)

NOTES=$(curl -sf http://127.0.0.1:8002/notes)
TOTAL=$(echo "$NOTES" | grep -o '"title"' | wc -l)
SURVIVED=$(echo "$NOTES" | grep -o 'last write before disaster' | wc -l)
# LC_ALL pins the decimal separator; a French locale rejects "1.4".
RTO=$(LC_ALL=C awk -v a="$T0" -v b="$T1" 'BEGIN { printf "%.1f", b - a }')

echo
echo "================= DRILL RESULTS ================="
echo "Data layer RTO (kill to first accepted write): ${RTO}s (local; add RDS promotion time on AWS)"
if [[ "$SURVIVED" -eq 1 && "$TOTAL" -eq 5 ]]; then
  echo "RPO: zero data loss, all 4 pre-disaster notes survived, 5 total after the post-failover write"
else
  echo "RPO: DATA LOSS DETECTED, expected 5 notes with the last pre-disaster write, got $TOTAL"
  exit 1
fi
echo "Primary /health during the outage: HTTP $PRIMARY_HEALTH (503 expected, the DNS failover trigger)"
echo "================================================="
