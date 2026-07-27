# Failover runbook

This document is written to be executed at 3 am by someone who did not build the system. Read it once now, not for the first time during an incident.

## What happens without you

Route 53 probes the primary ALB on https://.../health every 10 seconds from multiple locations. After 2 consecutive failures, roughly 30 seconds, DNS resolution for the public domain flips to the secondary ALB. Nobody triggers this and nobody can forget to do it.

At that moment the secondary region receives traffic but cannot serve it: the Auto Scaling group is at zero and the database is a read replica. The gap between the DNS flip and the end of this runbook is user-visible downtime. That gap is the RTO.

## Decision: is this a failover situation

Promote only when the primary region is genuinely unable to serve and is not about to recover. Promotion is one way: once the replica is standalone, the old primary keeps accepting whatever writes still reach it, and reconciling the two databases afterwards is manual work.

| Situation | Action |
| --------- | ------ |
| Primary health check failing, AWS reports a regional or AZ-wide issue | Fail over now. |
| Primary health check failing, cause unknown, more than 15 minutes of investigation without progress | Fail over. The RPO cost of waiting usually exceeds the cost of a failback later. |
| Single instance or deployment issue in the primary | Do not fail over. Fix in place, the ASG and the ALB already isolate instance failures. |
| RDS primary down but EC2 fine | Judgment call. Failing over the whole stack is simpler than running the app cross-region against the replica. |

## Failover procedure

Prerequisites: AWS CLI authenticated against the account, Terraform initialized in terraform/ so outputs resolve.

### Scripted path

```bash
./scripts/failover.sh
```

The script prints what it is about to do, asks you to type PROMOTE, then times every step. Expect the database promotion to take 5 to 10 minutes and the instances 3 to 5 minutes, in parallel.

### Manual path, if the script is unavailable

1. Promote the replica. This is the only destructive step.

```bash
aws rds promote-read-replica \
  --db-instance-identifier notes-replica \
  --region eu-west-3
```

2. Scale the secondary ASG. Do not wait for the promotion to finish first.

```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name notes-secondary \
  --desired-capacity 2 \
  --region eu-west-3
```

3. Watch both converge.

```bash
aws rds wait db-instance-available \
  --db-instance-identifiers notes-replica --region eu-west-3
aws elbv2 describe-target-health \
  --target-group-arn <secondary target group ARN> --region eu-west-3
```

## Verification

The public URL never changes. Confirm the secondary is serving:

```bash
curl -si https://<domain>/health | grep -i x-serving-region
```

The header must show the secondary region. Then write something and read it back, a failover that serves stale reads but loses writes is not done:

```bash
curl -s -X POST https://<domain>/notes \
  -H 'Content-Type: application/json' \
  -d '{"title": "failover drill", "body": "written on the secondary"}'
```

## Data loss assessment

Replication is asynchronous, so writes committed on the primary in the last seconds before the failure may be missing. After every failover, compare the most recent rows against application logs or client reports and record the measured RPO in the drill log below.

## Failback

Failback is a project, not a step, which is one of the honest costs of pilot light. Once the old primary region is healthy:

1. Create a new read replica in the original region, sourced from the promoted instance.
2. Wait for it to catch up, then schedule a short write freeze.
3. Promote the new replica, point Terraform's primary at it, and apply.
4. Scale the original region up, scale the other down to zero, restore the DNS primary and secondary roles.

None of this is urgent. The system runs correctly from the secondary region for as long as needed, at roughly the same cost as before.

## Drill log

Run a full drill at least quarterly. An untested runbook is a hypothesis.

| Date | Trigger | DNS flip | DB promotion | First healthy instance | Total RTO | Measured RPO | Notes |
| ---- | ------- | -------- | ------------ | ---------------------- | --------- | ------------ | ----- |
| | | | | | | | |
