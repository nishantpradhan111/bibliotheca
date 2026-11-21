# AWS infrastructure

Terraform defines AWS infrastructure for this application. The current target is
account `072718160501`, region `us-east-1`, with an ACTIVE EKS cluster,
available storage services, ECR repositories, and an active ALB. Reconcile the
existing resources with Terraform state before any plan or apply; no Terraform
apply is implied by the live Kubernetes evidence.

## Resource ownership

| Files | Resources |
|---|---|
| `main.tf`, `variables.tf` | Providers, validated inputs, naming and tags |
| `network.tf` | VPC, public/private/database subnets across two AZs, routing, NAT and gateway endpoints |
| `eks.tf` | EKS, access entry, node roles and fixed one-node managed group |
| `storage.tf` | Private RDS PostgreSQL, DynamoDB Books/Copies and notification-deduplication tables, private S3 |
| `catalog_iam.tf` | Catalog IRSA and scoped DynamoDB/S3 permissions |
| `messaging.tf` | SQS/DLQ, Lambda, API publisher role, SES delivery permissions |
| `streaming.tf` | Optional EMR/Flink primary, private Kafka connectivity, CloudWatch log shipping, and checkpoint permissions |
| `ecr.tf` | Private API/frontend ECR repositories |
| `outputs.tf` | Network, EKS, database, catalog, messaging, analytics and image identifiers |
| `tests/offline.tftest.hcl` | Mock-provider tests without AWS calls |

The existing AWS node group is `t3.small`; the Terraform target defaults to one
`t3.xlarge` worker for the APIs, Kafka, ZooKeeper, and observability. Changing
that instance type needs a reviewed plan and available EC2 quota. The existing
`m5.xlarge` EMR cluster is enabled and termination-protected by default; together
with the xlarge worker it uses **8 vCPUs**. Disable it only through the reviewed
two-step cleanup in the runbook. HPAs add pods only.

The EMR CloudWatch bootstrap/application settings may require replacing the
existing EMR cluster. Review the plan and the demo window before allowing that
replacement.

The target uses RDS PostgreSQL, DynamoDB and S3. Books and Copies are provisioned
at 50 read/50 write units, including the `book_id-index`, which is the capacity
used by the passing 40-VU demo. Choose a globally unique bucket
name for the target account; never assume the example or a previous account's
bucket exists. The bucket stores private covers and analytics artifacts,
checkpoints, and logs under separate prefixes.

## State and configuration

An ignored local Terraform state file is present, but its account and resource
ownership have not been verified. Preserve a backup and inspect its identity
only after AWS access works; do not use it or treat an empty state as permission
to recreate resources. State, plans, `.terraform/`, `.tfvars`, credentials and secrets remain ignored. Keep
`.terraform.lock.hcl` tracked. Required local inputs include account ID,
administrator IAM user/role ARN, supported EKS version, administrator egress CIDR,
intentional bucket name and SES sender. See `variables.tf` for validation/defaults.

Use a fresh plan for an infrastructure change and inspect its full effects;
earlier full plans proposed an unrelated EMR replacement. Do not reuse old saved
plans. Resource protection, snapshots and retained data require deliberate
handling. Demo cleanup does not destroy infrastructure or remove persistent data.
AWS resources begin billing when created; stopping pods does not stop EKS, NAT,
RDS, EMR or load-balancer charges. Plan a deployment window and cleanup window.

## Storage and identity

PostgreSQL is private/encrypted and uses shared database `digitallibrary`.
Bootstrap restricted service users and supply verified-TLS URLs and the public
RDS CA through the Kubernetes contracts in [k8s/README.md](../k8s/README.md).
Catalog's IRSA role is scoped to book/copy operations and private `covers/*`
objects. Notification has a separate scoped SQS publisher role. Lambda consumes
SQS, uses DynamoDB notification-ID deduplication and calls SES. EMR's role can
read/write its approved artifact/checkpoint/log prefixes in the target bucket.
The optional EMR bootstrap sends Flink/YARN logs to the retained
`/digital-library/analytics` CloudWatch log group for seven days.

S3 blocks public access, disables ACL-based ownership and uses encryption and a
TLS-only policy. RDS and applicable DynamoDB tables use deletion protection;
RDS requires a final snapshot on deletion. Terraform does not embed credentials.

## Local validation and deployment

From `infra`:

```powershell
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate -no-color
terraform test '-filter=tests\offline.tftest.hcl' -no-color
```

`fmt` passes. `validate` and the mocked test run remain blocked on this Windows
workstation because both the AWS and archive provider binaries fail the
Terraform plugin schema handshake, even after refreshing the generated provider
cache. The tests use mocked providers and are not proof of a real deployment.
The live demo separately verified actual services, storage, streaming, and
autoscaling; the bounded EMR/YARN Flink job produced results and checkpoint
metadata before cleanup.
Application/image preparation, database bootstrap and Argo CD deployment are
covered in [k8s/README.md](../k8s/README.md). Image publishing does not run a
Terraform apply or launch the Flink job.
