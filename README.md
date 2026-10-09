# DevOps Lab Infrastructure

Infrastructure-as-Code repository for the DevOps Platform Lab.

The goal of this project is to learn and demonstrate how infrastructure, Kubernetes, CI/CD, container registries, and GitOps fit together through a production-inspired hands-on environment.

The primary lab runs locally in WSL2 to minimize cloud cost while preserving workflows that resemble real infrastructure operations.

## Project Repositories

The project is separated into three primary repositories:

```text
devops-lab-app
    Application source, build configuration, and future CI pipeline

devops-lab-infra
    Terraform infrastructure and Kubernetes cluster provisioning

devops-lab-gitops
    Kubernetes desired state and environment-specific configuration
```

This separation keeps application code, infrastructure, and Kubernetes deployment state independently versioned.

## Operating Model

The project follows this workflow:

```text
Infrastructure as Code
        |
        v
CLI verification and troubleshooting
        |
        v
GUI inspection when useful
```

Persistent infrastructure changes should be defined in code rather than manually created through graphical interfaces.

The local runtime is intentionally disposable:

```text
Git + Terraform
      |
      | permanent source of truth
      v
terraform apply
      |
      v
Local platform
      |
      v
Lab work
      |
      v
terraform destroy
```

The platform should be reproducible from source rather than depending on long-lived local containers or Kubernetes state.

## Technology

Current infrastructure tooling includes:

* Terraform
* HashiCorp AWS Provider
* Floci
* AWS CLI
* Docker
* Kubernetes
* k3s
* kubectl
* Kustomize

Future stages will introduce:

* Jenkins
* SonarQube
* Trivy
* Argo CD
* Monitoring and alerting

## Platform Architecture

The current local platform contains three Kubernetes clusters:

```text
                         Shared ECR
                      devops-lab-app
                            |
              +-------------+-------------+
              |             |             |
              v             v             v
         devops-mgmt   devops-nonprod  devops-prod
              |             |             |
          Management      DEV / UAT       PROD
           tooling
```

The intended responsibilities are:

```text
devops-mgmt
    Management and platform tooling
    Argo CD will run here later

devops-nonprod
    DEV namespace
    UAT namespace

devops-prod
    PROD namespace
```

DEV and UAT share a non-production cluster.

Production uses a separate cluster to provide a stronger infrastructure and failure boundary.

## Network Architecture

Each cluster has its own logical VPC and two subnets.

```text
Management
VPC       10.10.0.0/16
Subnet A  10.10.1.0/24
Subnet B  10.10.2.0/24

Non-production
VPC       10.20.0.0/16
Subnet A  10.20.1.0/24
Subnet B  10.20.2.0/24

Production
VPC       10.30.0.0/16
Subnet A  10.30.1.0/24
Subnet B  10.30.2.0/24
```

In a larger real-world AWS environment, production and non-production could be isolated further through separate AWS accounts or organizational boundaries.

## Terraform Structure

```text
terraform/
├── modules/
│   └── eks-cluster/
│       ├── versions.tf
│       ├── variables.tf
│       ├── network.tf
│       ├── iam.tf
│       ├── eks.tf
│       └── outputs.tf
│
├── platform/
│   ├── versions.tf
│   ├── provider.tf
│   ├── main.tf
│   ├── iam.tf
│   ├── ecr.tf
│   ├── outputs.tf
│   └── .terraform.lock.hcl
│
└── poc/
    └── Milestone 6 proof-of-concept configuration
```

### Reusable EKS Module

`terraform/modules/eks-cluster` defines the reusable infrastructure required for one cluster:

```text
EKS cluster module
├── VPC
├── subnet A
├── subnet B
├── EKS IAM role
└── EKS cluster
```

The root platform configuration instantiates the same module three times:

```text
module.management
module.nonprod
module.prod
```

This avoids duplicating the cluster implementation.

## Shared ECR

The platform creates one application repository:

```text
devops-lab-app
```

The current Floci path-style repository URL follows this structure:

```text
localhost:5100/000000000000/us-east-1/devops-lab-app
```

The repository is shared between environments because the project follows a build-once artifact promotion model:

```text
Build image once
       |
       v
      DEV
       |
       v
      UAT
       |
       v
     PROD
```

The same immutable image or digest should eventually be promoted between environments rather than rebuilt separately.

`force_delete = true` is enabled because this is a disposable local lab and Terraform must be able to remove a repository containing test images.

## Floci

Floci provides AWS-compatible local APIs used by Terraform and the AWS CLI.

```text
Terraform / AWS CLI
        |
        v
http://localhost:4566
        |
        v
      Floci
```

Floci implements the local EKS clusters using k3s containers.

Docker is therefore used to inspect the emulator implementation layer, but Docker is not considered the normal administration interface for EKS.

In real AWS EKS, the managed control plane would normally be operated through AWS APIs, the AWS Console, and Kubernetes tools such as `kubectl`.

## Local Floci Runtime Configuration

The Floci UI/vendor stack is stored separately from this repository.

A local Compose override is currently used at:

```text
~/tools/floci-ui/docker-compose.local.yml
```

The required configuration is:

```yaml
services:
  floci:
    user: root
    environment:
      FLOCI_SERVICES_DOCKER_NETWORK: floci_default
      FLOCI_SERVICES_EKS_DOCKER_NETWORK: floci_default
      FLOCI_SERVICES_ECR_URI_STYLE: path
      FLOCI_SERVICES_EKS_DEFAULT_IMAGE: rancher/k3s:v1.34.11-k3s1
      FLOCI_SERVICES_EKS_KEEP_RUNNING_ON_SHUTDOWN: "true"
      FLOCI_SERVICES_ECR_KEEP_RUNNING_ON_SHUTDOWN: "false"
      FLOCI_STORAGE_PRUNE_VOLUMES_ON_DELETE: "false"
```

The k3s version is explicitly pinned rather than using `latest` so recreating the platform does not unexpectedly change Kubernetes versions.

`FLOCI_SERVICES_DOCKER_NETWORK` is explicitly set to `floci_default` so Docker-backed EKS/k3s containers share a reachable network with the Floci service. These settings help newly created k3s containers use the intended Docker network. Floci 2.0.1 can still select the bridge-network address when adopting surviving containers, leaving EKS reporting CREATING even when Kubernetes is healthy.

`FLOCI_STORAGE_PRUNE_VOLUMES_ON_DELETE` is now disabled to protect persistent k3s volumes during Floci lifecycle operations. `FLOCI_SERVICES_EKS_KEEP_RUNNING_ON_SHUTDOWN` is enabled so Floci does not intentionally remove running k3s containers during its normal shutdown.

EKS API ports such as `localhost:6500` are treated as ephemeral runtime details. Cluster names are the stable identifiers. If Floci recreates the underlying k3s containers, API ports and cluster certificate data can change, so kubeconfig should be refreshed with `aws eks update-kubeconfig`.

The current cluster nodes run:

```text
Kubernetes / k3s:
v1.34.11+k3s1

Container runtime:
containerd
```

## Starting Floci

From the Floci directory:

```bash
cd ~/tools/floci-ui

docker compose \
  -f docker-compose.yml \
  -f docker-compose.local.yml \
  up -d
```

Verify:

```bash
curl -sS http://localhost:4566/_floci/health | jq
```

## Lab Health Checks and Recovery

The lab uses a read-only health-check script:

```bash
./scripts/lab-status.sh
echo "Exit code: $?"
```

The script checks:

- Docker Engine availability
- Floci container and EKS service health
- Named k3s Docker volumes and their container attachments
- Kubernetes API readiness and node conditions
- Floci EKS lifecycle status
- DEV, UAT, and PROD namespaces
- Argo CD installation and Application resources

### Exit Codes

| Code | Result | Meaning |
| --- | --- | --- |
| 0 | HEALTHY | All required checks passed |
| 1 | DEGRADED | Warnings exist, but no required check failed |
| 2 | RECOVERY REQUIRED | Required resources are missing or unavailable |

Floci EKS status is checked separately from Kubernetes health.
A Floci status of `CREATING` does not necessarily mean Kubernetes is
unavailable. Kubernetes readiness must be verified independently.

The script does not create, restart, repair, or delete infrastructure.

### Current Recovery State

Following the October 2026 Floci recovery incident:

- The management and production k3s datastores were replaced.
- The non-production datastore retained its existing DEV and UAT namespaces.
- All three Kubernetes APIs recovered and their nodes became Ready.
- The management cluster requires Argo CD bootstrapping.
- The production cluster requires restoration of the PROD namespace.

These are recovery tasks, not normal startup operations.

### Initial Backup

An initial recovery checkpoint contains Kubernetes SQLite snapshots,
K3s server configuration and tokens, Floci metadata, and Terraform state.

The checkpoint was encrypted with GPG AES-256 and copied outside WSL
to the Windows filesystem. The two encrypted copies were verified
against matching SHA-256 checksums.

Backups must remain outside public Git repositories.

The initial backup has not yet passed a full restoration test.
Both copies currently reside on the same physical workstation.

### Known Limitations

The first version of `lab-status.sh` verifies named volume existence
and attachment but does not yet detect a volume silently replaced
under the same name.

Persistent volume identity checks, safe startup automation, and
restoration testing are planned for later recovery stages.

Normal startup and disaster recovery must remain separate workflows.
A degraded Floci status must never automatically trigger container
recreation, volume deletion, or Terraform destruction.

## Terraform Workflow

Enter the repository:

```bash
cd ~/projects/devops-platform-lab/devops-lab-infra
```

Provide local Floci bootstrap credentials:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566
```

Initialize:

```bash
terraform -chdir=terraform/platform init
```

Format:

```bash
terraform -chdir=terraform/platform fmt
```

Validate:

```bash
terraform -chdir=terraform/platform validate
```

Review the proposed infrastructure:

```bash
terraform -chdir=terraform/platform plan \
  -out=platform.tfplan
```

Apply the reviewed plan:

```bash
terraform -chdir=terraform/platform apply platform.tfplan
```

Inspect Terraform-managed objects:

```bash
terraform -chdir=terraform/platform state list
```

## Platform Outputs

Useful outputs include:

```text
cluster_names
cluster_endpoints
ecr_repository_url
vpc_ids
platform_admin_access_key_id
platform_admin_secret_access_key
```

The administrator secret access key is marked sensitive.

Terraform state may contain sensitive values and must never be committed to Git.

## Operator Identity

Terraform creates one local platform administrator:

```text
devops-platform-admin
```

The initial `test/test` Floci credentials are used only to bootstrap the platform.

After creation, AWS CLI and Kubernetes operations use the generated platform administrator identity.

```text
test/test
    |
    v
Terraform bootstrap
    |
    v
devops-platform-admin
    |
    +--> devops-mgmt
    +--> devops-nonprod
    +--> devops-prod
```

## Multi-Cluster kubectl Access

The kubeconfig contains separate contexts:

```text
devops-mgmt
devops-nonprod
devops-prod
```

Non-production should normally remain the default context:

```bash
kubectl config use-context devops-nonprod
```

For important operations, specify the target explicitly:

```bash
kubectl --context devops-prod get nodes
```

This reduces the risk of accidentally operating against the wrong cluster.

## Kubernetes Desired State

Terraform creates the Kubernetes infrastructure but does not own application Kubernetes resources.

Those are defined in the separate:

```text
devops-lab-gitops
```

repository.

The intended ownership model is:

```text
Terraform
    |
    v
Create Kubernetes infrastructure

GitOps repository
    |
    v
Define Kubernetes desired state

Argo CD
    |
    v
Reconcile desired state into Kubernetes
```

Jenkins will later perform continuous integration but should not directly deploy workloads with `kubectl apply`.

## Proof of Concept

`terraform/poc` contains the Milestone 6 proof of concept.

That configuration proved the initial end-to-end path:

```text
Terraform
   |
   v
Floci
   |
   +--> VPC
   +--> Subnets
   +--> IAM
   +--> ECR
   +--> EKS / k3s
             |
             v
       devops-lab-app
```

The PoC remains in the repository as historical learning material and a reference implementation.

## Current Status

Milestone 6 completed:

```text
Terraform + Floci proof of concept
ECR container image workflow
Single EKS/k3s cluster
Application deployment
Full Terraform teardown
```

Milestone 7 completed:

```text
Reusable Terraform EKS module
Shared ECR
Management cluster
Non-production cluster
Production cluster
Pinned Kubernetes/k3s version
Platform-wide IAM operator identity
Multi-cluster kubeconfig
Separate GitOps repository
Declarative DEV/UAT/PROD namespace definitions
Full destroy/recreate lifecycle acceptance test
```

Lifecycle acceptance verified:

```text
Terraform destroy:
18 resources destroyed
Terraform state empty
EKS resources removed
ECR repository removed
Platform IAM user removed
EKS/k3s containers removed
EKS/k3s volumes automatically pruned

Terraform recreate:
18 resources created
Shared ECR recreated
Management, non-production, and production EKS clusters recreated
Fresh k3s containers and volumes created
All three EKS clusters ACTIVE
All three Kubernetes nodes Ready
All Kubernetes /readyz checks passed
```

The Milestone 7 destroy/recreate test above was performed under the earlier volume-pruning configuration. It remains historical evidence of provisioning reproducibility, not a description of the current persistence policy.

The current lab prioritizes preservation of existing Kubernetes datastores. Intentional teardown and volume cleanup must be handled separately from ordinary startup and shutdown.

## Git Safety

Local and sensitive artifacts are excluded from source control, including:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars
*.tfvars.json
.env
.env.*
kubeconfig
```

Terraform provider lock files are committed:

```text
.terraform.lock.hcl
```

because they record the selected provider versions and checksums used for reproducible initialization.
