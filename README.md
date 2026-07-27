# AWS Multi-Region Pilot Light

A reference implementation of the pilot light disaster recovery pattern on AWS, built around a deliberately simple notes API so that all the value sits in the architecture and the trade-off analysis, not in the business code.

This repository contains the application, the full Terraform codebase for two AWS regions, the failover runbook, and a complete Well-Architected review covering the six pillars.

## Status

Work in progress. The sections below will be filled in as the implementation lands, feature branch by feature branch.

## Planned contents

- A minimal CRUD API (FastAPI) with health endpoints designed for DNS failover
- Terraform for two regions: VPC, ALB, Auto Scaling, RDS PostgreSQL with a cross-region read replica, S3 with cross-region replication
- Route 53 health checks and failover routing
- A documented and scripted failover procedure with measured RTO and RPO
- A Well-Architected review of the six pillars applied to this concrete architecture

## Why pilot light

The secondary region is not an active mirror. The data layer replicates continuously, the compute layer is scaled to zero. This buys a much lower standby cost than warm standby or active-active, in exchange for a higher recovery time. That trade-off, with real numbers, is the point of this project.

## License

MIT. See [LICENSE](LICENSE).
