# DevOps Lab Infrastructure

Infrastructure-as-Code repository for my production-inspired DevOps learning environment.

The goal of this project is to learn how infrastructure, container registries, Kubernetes, CI/CD, and GitOps fit together through hands-on implementation rather than only studying the tools individually.

Infrastructure is defined with Terraform first, verified through command-line tools, and then inspected through graphical interfaces where useful.

## Learning Workflow

The project follows this operating model:

```text
Infrastructure as Code
        |
        v
CLI verification and troubleshooting
        |
        v
GUI inspection
```

Persistent infrastructure changes should be defined in code rather than manually created through graphical interfaces.

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

Future stages will introduce:

* Jenkins
* SonarQube
* Trivy
* Argo CD
* Kustomize
* Monitoring and alerting

## Why Floci?

The primary lab runs locally inside WSL2 to minimize cloud cost.

Floci provides AWS-compatible local APIs that allow Terraform and the AWS CLI to interact with locally emulated AWS services.

The important abstraction is:

```text
Terraform
    |
    v
AWS Provider
    |
    v
Floci AWS-compatible APIs
```

This allows the Terraform configuration to use normal AWS resource types while the infrastructure is implemented locally.

For EKS emulation, Floci creates a local k3s Kubernetes cluster backed by Docker.

This is useful for learning AWS-style infrastructure workflows, but it is not equivalent to running a real AWS-managed EKS control plane.

A later milestone may validate the architecture against actual AWS infrastructure for short-lived testing.

## Repository Structure

Current proof-of-concept layout:

```text
terraform/
└── poc/
    ├── versions.tf
    ├── provider.tf
    ├── network.tf
    ├── iam.tf
    ├── ecr.tf
    ├── eks.tf
    ├── outputs.tf
    └── .terraform.lock.hcl
```

### `versions.tf`

Defines:

* Supported Terraform version
* HashiCorp AWS Provider dependency and version constraint

### `provider.tf`

Configures the AWS provider to use the local Floci endpoints instead of real AWS APIs.

### `network.tf`

Creates the proof-of-concept network:

```text
VPC
├── Subnet A
└── Subnet B
```

Current CIDR layout:

```text
VPC       10.10.0.0/16
Subnet A  10.10.1.0/24
Subnet B  10.10.2.0/24
```

### `iam.tf`

Creates the IAM resources required by the local EKS proof of concept:

* EKS cluster role
* EKS administrative IAM user
* IAM access key

The generated credentials are sensitive and are stored in Terraform state, which is excluded from Git.

### `ecr.tf`

Creates the ECR repository used for the application container:

```text
devops-lab-app
```

The local PoC uses Floci's path-style ECR URI:

```text
localhost:5100/000000000000/us-east-1/devops-lab-app
```

The repository is configured with `force_delete = true` because this is a disposable local environment and should be completely removable with Terraform.

### `eks.tf`

Creates the logical EKS cluster:

```text
devops-poc
```

The cluster references the Terraform-managed IAM role and subnets.

Floci implements the local EKS cluster using k3s.

### `outputs.tf`

Provides useful values such as:

* ECR repository URL
* EKS cluster name
* Generated IAM access key

Sensitive outputs are marked as sensitive.

## Proof-of-Concept Architecture

Milestone 6 validated the following path:

```text
Terraform
    |
    v
Floci
    |
    +--> VPC
    |
    +--> Subnets
    |
    +--> IAM
    |
    +--> ECR
    |      |
    |      v
    |   Application image
    |
    └--> EKS
           |
           v
          k3s
           |
           v
       Kubernetes
           |
           v
    devops-lab-app
```

The Spring Boot application was successfully:

1. Built as a Docker image
2. Pushed to the Floci-backed ECR repository
3. Discovered through the AWS ECR API
4. Pulled by the k3s Kubernetes cluster
5. Deployed as a Kubernetes Deployment
6. Verified as `Running` and `Ready`
7. Tested through `/api/version`
8. Tested through `/actuator/health`

The deployed image was verified by immutable digest.

## Terraform Workflow

Initialize Terraform:

```bash
terraform init
```

Format:

```bash
terraform fmt
```

Validate:

```bash
terraform validate
```

Review the proposed infrastructure:

```bash
terraform plan -out=poc.tfplan
```

Apply the reviewed plan:

```bash
terraform apply poc.tfplan
```

Inspect managed resources:

```bash
terraform state list
```

Destroy the disposable environment:

```bash
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
```

Saved plan files are temporary execution artifacts and are not committed to Git.

## Git Safety

The repository intentionally excludes local Terraform state and sensitive runtime files.

Examples include:

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

The provider lock file is committed:

```text
.terraform.lock.hcl
```

because it records the selected provider versions and checksums required for reproducible Terraform initialization.

## Important PoC Findings

The proof of concept produced several useful operational lessons:

* EKS subnet references must correspond to actual infrastructure resources.
* Terraform configuration health and Kubernetes runtime health are different concerns.
* A recreated Kubernetes cluster can receive a different API endpoint, requiring kubeconfig to be refreshed.
* Floci EKS persistence can expose k3s networking issues after a full WSL/Docker restart.
* Floci's ECR hostname-style addressing was problematic in the local WSL environment.
* Path-style ECR addressing resolved the local registry namespace mismatch.
* ECR repositories containing images require explicit deletion behavior.
* Floci implementation details such as Docker containers and volumes are separate from Terraform-managed AWS resources.

These troubleshooting cases were part of validating the behavior of the local platform and helped define requirements for the permanent architecture.

## Current Status

### Milestone 6 — Complete

Validated:

* Terraform AWS provider with Floci
* VPC creation
* Multiple subnet creation
* IAM resources
* ECR repository
* Path-style ECR
* Docker image push
* ECR API image discovery
* EKS creation
* k3s-backed Kubernetes
* Kubernetes authentication
* Kubernetes Deployment
* ECR-to-Kubernetes image delivery
* Spring Boot application health
* Full Terraform teardown

The PoC infrastructure is currently destroyed when not needed.

## Next

The next milestone will evolve this proof of concept into a more permanent environment model supporting:

```text
DEV
UAT
PROD
```

The design will focus on realistic environment isolation, immutable artifact promotion, Kubernetes configuration management, and eventually GitOps with Argo CD.
