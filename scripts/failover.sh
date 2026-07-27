#!/usr/bin/env bash
# Failover to the secondary region.
#
# DNS has already failed over on its own by the time a human runs this:
# Route 53 flips resolution as soon as the primary health check fails.
# What this script does is make the secondary region actually able to
# serve: promote the read replica to a standalone writable instance,
# then scale the API Auto Scaling group up from zero.
#
# Every step is timed and logged, because the point of a drill is to
# come out with a measured RTO, not a feeling.
#
# Usage:
#   ./scripts/failover.sh          interactive, asks for confirmation
#   ./scripts/failover.sh --yes    no confirmation, for drills

set -euo pipefail

TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
DESIRED_CAPACITY="${DESIRED_CAPACITY:-2}"

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

tf_output() {
  terraform -chdir="$TERRAFORM_DIR" output -raw "$1"
}

log "Reading Terraform outputs"
REPLICA_ID="$(tf_output replica_db_identifier)"
SECONDARY_ASG="$(tf_output secondary_asg_name)"
SECONDARY_ALB="$(tf_output secondary_alb_dns_name)"
API_URL="$(tf_output api_url)"

# The secondary region is not stored in outputs; derive it from where
# the replica actually lives so the script cannot target the wrong one.
SECONDARY_REGION="$(aws rds describe-db-instances \
  --query "DBInstances[?DBInstanceIdentifier=='$REPLICA_ID'].AvailabilityZone | [0]" \
  --output text 2>/dev/null | sed 's/[a-z]$//' || true)"
if [[ -z "$SECONDARY_REGION" || "$SECONDARY_REGION" == "None" ]]; then
  SECONDARY_REGION="${SECONDARY_REGION_OVERRIDE:-eu-west-3}"
fi

log "Replica to promote:      $REPLICA_ID ($SECONDARY_REGION)"
log "ASG to scale:            $SECONDARY_ASG -> $DESIRED_CAPACITY instances"
log "Public URL (unchanged):  $API_URL"

if [[ "${1:-}" != "--yes" ]]; then
  echo
  echo "Promotion is one way: the replica stops replicating and the old"
  echo "primary keeps drifting until failback. Type the word PROMOTE to go."
  read -r answer
  [[ "$answer" == "PROMOTE" ]] || { echo "Aborted."; exit 1; }
fi

START_TS=$(date +%s)

log "Step 1/3: promoting the read replica"
aws rds promote-read-replica \
  --db-instance-identifier "$REPLICA_ID" \
  --region "$SECONDARY_REGION" >/dev/null

# Scale-up does not wait for the promotion: instances boot in parallel
# with it, and their /health stays red until the database accepts
# writes... which is exactly the behaviour the target group expects.
log "Step 2/3: scaling the secondary Auto Scaling group"
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$SECONDARY_ASG" \
  --desired-capacity "$DESIRED_CAPACITY" \
  --region "$SECONDARY_REGION"

log "Waiting for the promoted instance to become available"
aws rds wait db-instance-available \
  --db-instance-identifiers "$REPLICA_ID" \
  --region "$SECONDARY_REGION"
PROMOTED_TS=$(date +%s)
log "Database promoted and available after $((PROMOTED_TS - START_TS))s"

log "Step 3/3: waiting for the secondary ALB to answer on /health"
DEADLINE=$((START_TS + 1800))
until curl -sk --max-time 5 "https://$SECONDARY_ALB/health" | grep -q '"ok"'; do
  if (( $(date +%s) > DEADLINE )); then
    log "Secondary did not become healthy within 30 minutes, investigate."
    exit 1
  fi
  sleep 10
done

END_TS=$(date +%s)
log "Secondary region is serving."
log "Measured RTO from promotion start: $((END_TS - START_TS))s"
log "Verify end to end: curl -si $API_URL/health | grep -i x-serving-region"
