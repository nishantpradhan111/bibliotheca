# Assignment Requirements Readiness

This matrix maps the Cloud Computing assignment requirements to the repository
and the current live deployment. Live evidence below was collected on
2026-11-21 in AWS account `072718160501`, region `us-east-1`, cluster
`digital-library-dev`.

| Requirement | Repository implementation | Current verification |
|---|---|---|
| a. Provision infrastructure with IaC | [Terraform](./infra/) defines VPC, EKS, RDS, DynamoDB, S3, SQS, Lambda, ECR, IAM, and EMR. [Kubernetes resources](./k8s/) are reconciled by Argo CD; the ALB is controller-created from the Ingress. | EKS is ACTIVE, the ALB is active, and the expected AWS resources are present in `us-east-1`. Terraform `fmt` passes; `validate` remains blocked by provider schema handshake failures. |
| b. Eight services and REST, gRPC, and event messaging | Seven REST APIs, the frontend, and Notification Lambda are separate runtimes. Member serves gRPC; Reservation/Lending use REST and transactional Kafka outboxes; Notification uses SQS/Lambda/SES. | All seven public `/ready` and `/metrics` proxy endpoints returned HTTP 200. Kafka/Flink domain-event confirmation remains outstanding. |
| c. Managed Kubernetes, two HPAs, and load testing | EKS manifests define Catalog and Reservation HPAs; [k6 script](./scripts/k6/reservation-load.js) uses existing records and read-only requests. | Live k6 passed with 24,816 requests, 8,272 iterations, 40 max VUs, 0.00% failures, and p95 306.57 ms. Catalog and Reservation both scaled 1→2 and returned to 1 after the 180-second stabilization window. |
| d. GitOps deployment | [Argo CD Applications](./argocd/) watch the app and platform Kustomize trees. The platform tree installs the AWS Load Balancer Controller through an Argo CD child Application. | All five Argo Applications are Synced/Healthy, including the repaired ApplicationSet controller. Historical bootstrap used direct applies, so the strict historical claim still requires qualification. |
| e. Flink windowed analytics | [Usage Analytics](./services/usage-analytics/) reads the shared event envelope, aggregates one-minute event-time windows, deduplicates event IDs in a window, and writes a results topic. | Verified live on EMR/YARN: the consumer group reached zero lag, results contained 2 reservations, 1 checkout, 1 return, 2 unique members, and 4 events, and S3 contained completed checkpoint metadata. The bounded demo job was stopped and EMR returned to WAITING. |
| f. ZooKeeper concept | Reservation coordinates per-book allocation with ZooKeeper in Kubernetes and an in-memory lock locally. | All three ZooKeeper pods are Running; cross-replica locking and failure recovery still need a recorded demo. |
| g. Three storage products | Services use PostgreSQL, DynamoDB, and S3; Terraform and runtime adapters are in [infra](./infra/) and the service folders. | RDS, three DynamoDB tables, and the private S3 bucket are live in `us-east-1`; the Books/Copies tables are now 50/50 provisioned for the sustained demo. Capture final cover PUT/GET screenshots. |
| h. Prometheus, Grafana, and centralized logs | [Observability manifests](./k8s/platform/) define service scrape health, pod readiness, RPS, 5xx rate, success rate, p95 latency, replicas, HPA state, restarts, memory, and CPU. Fluent Bit forwards app logs; the optional EMR bootstrap forwards Flink/YARN logs to CloudWatch. | Prometheus, Grafana, Fluent Bit, metrics-server, and all API metrics endpoints are healthy. Grafana/CloudWatch screenshots remain final presentation evidence. |

## Local checks completed

- Python tests in the `deeplearning` Anaconda environment: root demo controls 10 passed; Member 21 passed and 1 skipped; Catalog config 5 passed; Reservation 6 passed; Lending 11 passed; Availability 5 passed; Fine 5 passed; Notification 4 passed.
- Docker Desktop's Linux engine is available and `docker compose config` passes.
- Compose configuration, frontend syntax, Kustomize app/platform rendering, and k6 script inspection pass.
- Terraform `fmt -check` passes. `terraform validate` and `terraform test` cannot load the AWS and archive provider schemas.

## Current live deployment evidence

The `library-deployer` profile identifies account `072718160501`. The live
cluster `digital-library-dev` is ACTIVE on EKS `1.37`, with one Ready worker.
The public ALB is active at
`k8s-library-libraryp-5f1873da46-493571967.us-east-1.elb.amazonaws.com`.
All seven API Deployments, frontend, Kafka, three ZooKeeper pods, Prometheus,
Grafana, metrics-server, Fluent Bit, and the AWS Load Balancer Controller are
Running. The four Argo Applications are Synced/Healthy.

The Argo ApplicationSet CRD was missing and caused a controller crash loop. The
official Argo CD v3.6.2 CRD was installed as a platform bootstrap repair; the
controller now has zero restarts and is Ready. Record this bootstrap exception
in the GitOps evidence because the CRD was repaired outside the application
Kustomize tree.

## AWS inventory and deployment gate

The `library-deployer` profile identifies the account configured in the ignored
Terraform variables file. A read-only inventory on 19 November 2026 found an
ACTIVE EKS 1.35 cluster, one ACTIVE `t3.small` node group, an EMR cluster in
`WAITING`, an available `db.t4g.micro` RDS instance, three DynamoDB tables,
Digital Library ECR repositories, a Notification Lambda, and SQS/DLQ in
`us-east-1`. No ALB was found. The same inventory found no matching EKS, EMR,
RDS, DynamoDB, or ECR resources in `ap-south-1`.

Older inventory notes in this file refer to `ap-south-1`; they are historical
only. The current target is `us-east-1`, and the live workload evidence above is
current. No Terraform apply was run during this audit; the targeted DynamoDB
capacity change was applied to the existing tables and is now represented in
Terraform.

## Submission artifact still requiring team input

The assignment requires `task_divison.txt`. It is intentionally not fabricated:
the repository does not contain the team members' student IDs and names. Add
the real roster and assign the verified areas (Terraform/storage, EKS/GitOps,
REST/gRPC, notification, ZooKeeper, Kafka/Flink, and observability) before
submission.
