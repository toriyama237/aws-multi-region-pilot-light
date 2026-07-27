# Cost analysis

Monthly figures, on-demand pricing for eu-west-1 and eu-west-3 as of mid 2026, 730 hours per month, rounded to the nearest half dollar. These are estimates from public pricing; every resource carries Project and DrPattern tags precisely so the real bill can be checked against this table with one Cost Explorer filter. Data transfer and LCU figures assume demo traffic and will grow with load.

## Primary region, eu-west-1

| Resource | Sizing | Monthly cost (USD) |
| -------- | ------ | ------------------ |
| Application Load Balancer | 1, low LCU | 22.0 |
| EC2 API instances | 2 x t3.micro | 16.5 |
| EBS root volumes | 2 x 8 GB gp3 | 1.5 |
| NAT gateway | 1, light processing | 35.5 |
| RDS PostgreSQL primary | db.t3.micro, single AZ | 13.0 |
| RDS storage and backups | 20 GB gp3, 7 day retention | 3.0 |
| KMS key | 1 customer managed | 1.0 |
| Secrets Manager | 1 secret | 0.5 |
| S3 assets | a few GB | 0.5 |
| Total | | about 93.5 |

## Secondary region, eu-west-3, the pilot light

| Resource | Sizing | Monthly cost (USD) |
| -------- | ------ | ------------------ |
| Application Load Balancer | 1, near zero LCU | 19.5 |
| EC2 API instances | 0 | 0.0 |
| NAT gateway | 1, near zero processing | 32.0 |
| RDS read replica | db.t3.micro | 15.5 |
| RDS replica storage | 20 GB gp3, 7 day retention | 3.0 |
| KMS key | 1 customer managed | 1.0 |
| Secrets Manager | replica secret | 0.5 |
| S3 replica and inter-region transfer | a few GB at 0.02 USD per GB | 1.0 |
| Total | | about 72.5 |

## Global

| Resource | Monthly cost (USD) |
| -------- | ------------------ |
| Route 53 hosted zone | 0.5 |
| Route 53 health check, HTTPS and fast interval options | 3.5 |
| SNS and CloudWatch alarm | 0.5 |
| Total | about 4.5 |

Grand total: about 170 USD per month, of which the DR posture (everything outside the primary region) is about 77.

## What the alternatives would cost

Same workload, same regions, secondary region only:

| Pattern | Secondary region monthly cost | RTO order of magnitude |
| ------- | ----------------------------- | ---------------------- |
| Backup and restore | about 3 (snapshots and S3 only) | Hours |
| Pilot light, this repository | about 72 | 10 to 15 minutes measured target |
| Warm standby, 1 instance running | about 81 | A few minutes |
| Active-active, full mirror plus Aurora Global Database | 150 and up, plus engineering time for write conflicts | Near zero |

## The honest part

At this scale the numbers make pilot light look unimpressive: 72 versus 81 dollars for warm standby is noise, because a t3.micro costs 8 dollars and the standing cost is dominated by the ALB and the NAT gateway, which the pattern keeps warm anyway.

The pattern is chosen for how it scales, not for what it saves on a demo. Compute grows with traffic; the warm parts do not. Replace the fleet with ten m5.large and the primary compute line becomes about 780 USD per month while the pilot light secondary still runs zero instances. At that scale:

| Pattern | Secondary region, production scale | Fraction of primary |
| ------- | ---------------------------------- | ------------------- |
| Pilot light | about 150 (ALB, NAT, replica on matching storage) | roughly 15 percent |
| Warm standby at 30 percent fleet | about 400 | roughly 40 percent |
| Active-active | about 1000 | roughly 100 percent |

The other lever worth naming: the 51.5 USD of ALB and NAT in the secondary exist only to shorten RTO. A team comfortable running terraform apply during an incident could create both at failover time and cut the pilot light to the replica alone, about 20 USD per month, in exchange for 5 to 10 more minutes of RTO and the risk of an apply failing mid-incident. This repository keeps them warm and pays for the calmer runbook.
