# Digital Library

This repository contains a Digital Library application and its AWS deployment
configuration. The current live target is AWS account `072718160501`, region
`us-east-1`, EKS cluster `digital-library-dev`, with an active public ALB at
`k8s-library-libraryp-5f1873da46-493571967.us-east-1.elb.amazonaws.com`.
All seven APIs, the frontend, Kafka, ZooKeeper, Prometheus, Grafana, Fluent Bit,
and the AWS Load Balancer Controller are currently running. The app has seven
REST APIs, a Member gRPC endpoint, a web frontend, and a separate Kafka/Flink
analytics job.

## Live demo after deployment

With `.local/kubeconfig` available, run the tracked presenter from the
repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/demo.ps1
```

To launch Grafana with a local port-forward and open the dashboard in your
browser, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/launch-grafana.ps1
```

The dashboard opens at `http://127.0.0.1:13000/d/library-services-live`.
The port-forward remains active after the launcher exits. Stop it with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/launch-grafana.ps1 -Stop
```

The launcher uses the repository kubeconfig and the temporary TLS workaround
required by the current local environment. Remove the
`--insecure-skip-tls-verify=true` argument from the script after the local EKS
certificate trust issue is fixed.

To run the read-only Reservation k6 load test, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-reservation-k6.ps1
```

The runner uses the documented fixture IDs by default. Override them when
needed:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-reservation-k6.ps1 `
  -BaseUrl "http://PUBLIC-ALB-DNS" `
  -BookId "BOOK_UUID" `
  -MemberId "MEMBER_UUID"
```

The runner starts Grafana at
`http://127.0.0.1:13000/d/library-services-live` before k6 begins, so you can
watch request rate, latency, errors, CPU, and HPA replica metrics during the
load test. Use `-NoGrafana` if Grafana is already running or should not be
opened.

Use `-DryRun` to verify the setup without starting k6.

It prints the actual API status codes, pod/container inventory, Ingress/ALB,
HPAs, and Argo CD status. To run the sustained read-only load test, supply the
isolated fixture IDs:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/demo.ps1 `
  -BookId 78b082b2-5f62-49a3-8f9d-f0b4e656ae09 `
  -MemberId f2573e6a-5119-4cdc-a63d-1b64fec78ab6 `
  -RunLoad
```

The script is read-only except for the explicitly requested k6 traffic and does
not create or delete business records.
runs no cleanup. Flink and autoscaling take several minutes; they do not
provision new instances or change HPA limits.

| Step | Demonstrates |
|---|---|
| 1. REST APIs and private S3 | All 23 business endpoints, validation, FIFO holds, checkout/return and byte-for-byte private cover storage |
| 2. Member gRPC and ZooKeeper | Real eligibility RPCs and the reservation lock path |
| 3. Positive overdue fines | Fine code over loopback HTTP using temporary SQLite; production loan dates remain untouched |
| 4. Automatic email delivery | Checkout/return and explicit intake through SQS, Lambda and SES; duplicate-ID suppression |
| 5. Prometheus | Seven healthy scrape targets, request rates, latency, CPU and HPA metrics |
| 6. Kafka and Flink | Bounded EMR/YARN run consumed Kafka events, emitted a separate results-topic aggregate, and wrote an S3 checkpoint |
| 7. Autoscaling | Both HPAs scale 1 -> 2 -> 1 under sustained read-only HTTP load, while Argo CD remains Synced/Healthy |

The tracked presenter does not create business records or run the Flink job. The
Flink source/build instructions and its current live verification status are in
[Usage Analytics](services/usage-analytics/README.md).

The repository contains a **historical** audit report with 146 functional HTTP
checks, 37,956 load requests and 79 assertions. It does not establish that AWS
resources currently exist or that the report belongs to your account. See
[FINAL_VERIFICATION.md](FINAL_VERIFICATION.md) for its scope and caveats.

## Services and behavior

| Service | Responsibility |
|---|---|
| Member | Register/get/update/list members; answer gRPC checkout eligibility |
| Catalog | Books, physical copies, private cover uploads/downloads |
| Reservation | READY/WAITLISTED FIFO holds, cancellation and promotion |
| Lending | Checkout, due dates, idempotent returns and automatic loan notifications |
| Availability | Derive copy availability from Catalog, reservations and loans |
| Fine | Read loan timestamps and calculate fines; does not modify loans |
| Notification | Queue explicit/automatic events through SQS -> Lambda -> SES |
| Usage Analytics | Kafka input -> one-minute Flink aggregates -> Kafka results |

The frontend proxies `/api/...` to internal routes such as `/members`, `/books`,
`/reservations` and `/loans`. The app does not require an Idempotency-Key
header. Reservations use READY and WAITLISTED states.

`LoanIssued` and `LoanReturned` notifications use the member's stored email,
with a stable UUIDv5 per loan/event pair. Repeated or concurrent returns emit one
return event. Intake accepts optional `event_id`; older explicit requests without
it keep random IDs. The existing Lambda/DynamoDB consumer suppresses repeated IDs
within its retention window. Publishing is best-effort after commit: failures are
logged and do not fail the committed loan operation. There is no durable outbox;
crashes or failed publishes can lose events. Tests use labeled SES simulator
addresses, not real recipients. SES sender/recipient restrictions still apply.

Reservation and Lending now store analytics events in transactional SQL outboxes
and publish the shared JSON envelope to Kafka; Flink accepts that envelope and
deduplicates repeated outbox event IDs within a window. This source path has
local unit coverage, but needs a live Kafka/EMR run in the target account before
it can be called deployment-verified. HPA load uses read-only requests and proves
scaling, not business-endpoint capacity.

## Deployment and limits

The manifests target the existing `us-east-1` EKS cluster and Argo CD. Do not
create a second cluster. Publishing to Git alone does not provision AWS
resources; infrastructure changes require a reviewed Terraform plan. The Argo
ApplicationSet CRD was repaired with the official Argo CD v3.6.2 definition; the
controller is now Ready with zero restarts. Disclose this platform bootstrap
repair alongside the historical direct-apply caveat.

## Local development and tests

From `digital-library`, Docker Desktop with Linux containers can run the seven
APIs, a local Kafka broker, and PostgreSQL/DynamoDB/MinIO emulators:

```powershell
docker compose up --build -d --wait --wait-timeout 600
python scripts/smoke_test.py
```

Run `node frontend/server.js` separately for the local frontend. Local Compose
starts Kafka but not Flink; Flink is built and submitted to the optional EMR
cluster. Service unit tests live under each service's `tests/`.
Presenter-control tests run from the repository root without AWS:

```powershell
python -m unittest discover -s tests -v
```

## Essential documentation

| Document | Purpose |
|---|---|
| [Verification](FINAL_VERIFICATION.md) | Assignment evidence, CLI checks and remaining caveats |
| [Assignment readiness](ASSIGNMENT_READINESS.md) | Requirement-by-requirement implementation and live verification status |
| [Architecture](ARCHITECTURE_DESIGN.md) | System overview and design rationale |
| [Architecture views](ARCHITECTURE_VIEWS.md) | Allocation, module, and component-and-connector diagrams |
| [Monitoring](MONITORING.md) | Prometheus/Grafana access and credential retrieval |
| [Infrastructure](infra/README.md) | Terraform resources, state and limits |
| [Kubernetes/GitOps](k8s/README.md) | Image publication, database bootstrap, Secrets and deployment |
| [Usage Analytics](services/usage-analytics/README.md) | Event contract, build and EMR submission |
