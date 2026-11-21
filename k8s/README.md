# Kubernetes deployment and GitOps

The application namespace is `library`. The live cluster is
`digital-library-dev` in `us-east-1`; its public ALB is
`k8s-library-libraryp-5f1873da46-493571967.us-east-1.elb.amazonaws.com`.
All application Deployments and platform workloads are currently Running, and
the Argo Applications are Synced/Healthy. The manifests currently track `main`:

- `argocd/application.yaml`: application Kustomize path `k8s`.
- `argocd/platform.yaml`: platform path `k8s/platform`.

API updates use Git commits and Argo reconciliation. Historical Kafka/ZooKeeper
bootstrap and monitoring direct applies remain a strict GitOps caveat. The
missing Argo ApplicationSet CRD was repaired using the official Argo CD v3.6.2
definition; the controller is now Ready with zero restarts. Disclose this
platform bootstrap repair when presenting strict GitOps history. The
platform tree now creates the AWS Load Balancer Controller service account and
an Argo CD child Application for the pinned Helm chart; the target ALB is
created from the Ingress after the controller is healthy. The ALB routes `/` to
the frontend and browser `/api/...` calls use its proxy.

## Images and deployment

The existing CI workflow tests source and validates manifests; image publication
and manifest updates are terminal steps. From the repository root, with Docker
Desktop using Linux containers and the existing AWS profile:

```powershell
powershell -ExecutionPolicy Bypass -File digital-library/scripts/publish-images.ps1 -Profile library-deployer
```

This builds/pushes seven API images plus the frontend into the ECR repositories
for the selected account, with immutable tags and recorded digests in `.local/images-TAG.json`.
It does not provision infrastructure or deploy pods. Prepare image/runtime values:

```powershell
powershell -ExecutionPolicy Bypass -File digital-library/scripts/configure-aws.ps1 -ImagesFile digital-library/.local/images-TAG.json
```

Review the changes, commit and push the manifests to the watched deployment
branch, then let Argo CD sync. Publishing to `main` alone does not deploy.
For a small service update, build/publish only affected services and update only
their digest references. The Notification Lambda ZIP is Terraform-managed;
Usage Analytics is a separate jar submitted to EMR.

## Database bootstrap and runtime contracts

For a fresh environment, use `scripts/bootstrap-database.sql` from inside the
VPC to create
restricted roles and grants in the shared `digitallibrary` database. The script
prompts for passwords. API workloads must not use the RDS master user.

| Secret | Key | PostgreSQL role |
|---|---|---|
| `member-database` | `DATABASE_URL` | `library_member` |
| `reservation-database` | `url` | `library_reservation` |
| `lending-database` | `url` | `library_lending` |
| `availability-database` | `url` | `library_availability` |
| `fine-database` | `url` | `library_fine` |

All services read the same database. URLs use
`postgresql+psycopg://ROLE:URL_ENCODED_PASSWORD@RDS_HOST:5432/digitallibrary?sslmode=verify-full&sslrootcert=/etc/rds-ca/global-bundle.pem`.
The public CA bundle is supplied by `rds-ca`, key `global-bundle.pem`. Supply
Secrets through the existing secret-delivery process; never commit passwords.
Member's init container and Reservation/Lending startup create their schemas;
Availability and Fine read the required shared tables through restricted roles.

Catalog's IRSA role provides scoped DynamoDB/S3 access. Notification uses its
own IRSA role with `sqs:SendMessage` and `notification-config` queue/region values.
The Lambda's consumer role does not grant the API publisher permissions.
`APP_ENV=aws` enables cloud mode; emulator endpoint overrides must be absent.

Services expose port 80 with named `http` ports. Container ports are Member 8001,
Catalog 8002, Reservation 8003, Notification 8004, Fine 8005, Lending 8006 and
Availability 8007. Member gRPC uses 50051. All seven APIs expose `/health`,
`/ready` and `/metrics`. Containers use non-root users, restricted capabilities,
read-only root filesystems and writable temporary volumes.

## Autoscaling and platform

Catalog and Reservation HPAs retain min/max 1/2 with a 60% CPU target and a
180-second scale-down stabilization window. Their Deployments omit `replicas`
so Argo CD does not undo HPA decisions. The demo proved both scale 1 -> 2 -> 1
while Argo stays Synced/Healthy. HPA does not add EKS nodes.

The platform tree includes Kafka, three ZooKeeper replicas, metrics-server,
Prometheus/Grafana, a PodMonitor/dashboard and Fluent Bit/CloudWatch forwarding.
Kafka's private EMR listener is exposed on NodePort 30094; no public broker access
is required. Flink runs on the existing EMR primary, not as an EKS Deployment.
See [monitoring access](../MONITORING.md) and [analytics](../services/usage-analytics/README.md).

Render locally without changing the cluster:

```powershell
kubectl kustomize k8s
kubectl kustomize k8s/platform
```

For live validation run `powershell -ExecutionPolicy Bypass -File scripts/demo.ps1`
from the repository root. Full evidence and caveats are in
[FINAL_VERIFICATION.md](../FINAL_VERIFICATION.md).
