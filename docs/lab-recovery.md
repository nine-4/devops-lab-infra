# Local DevOps Lab Recovery Runbook

## Scope

This runbook covers the existing Floci/K3s-based, three-cluster
DevOps lab:

- devops-mgmt: Argo CD management cluster
- devops-nonprod: DEV and UAT namespaces
- devops-prod: simulated PROD environment

These are local K3s clusters simulating EKS, not AWS-managed EKS.

Never use Terraform destroy, Docker volume prune, or force-recreate
as an automatic recovery action.

## 1. Resume the Lab

From the infrastructure repository:

    ./scripts/lab-up.sh

The startup script verifies the recorded Docker volume identities
before starting existing containers. It refuses to create missing
containers or silently accept replaced volumes.

Inspect the resulting state:

    ./scripts/lab-status.sh

Current known limitation: Floci may report EKS clusters as CREATING
while their Kubernetes APIs and nodes are Ready.

The health check therefore reports DEGRADED (exit 1) even when
Kubernetes and Argo CD are operational.

Do not disregard other failures.

## 2. Initialize a New Terminal

Load the Floci credentials into the current shell:

    source scripts/lab-env.sh

The helper reads Terraform outputs without printing credentials.

These environment variables target the local emulator, not real AWS.
Clear them before switching to a real AWS environment:

    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    unset AWS_DEFAULT_REGION AWS_ENDPOINT_URL AWS_SESSION_TOKEN

## 3. Verify Persistent Storage

Run:

    ./scripts/lab-volume-baseline.sh --verify

The private baseline is stored at:

    ~/.local/state/devops-platform-lab/volume-baseline.tsv

It records Docker volume creation timestamps and verifies the
expected K3s volume attachments.

Never rerun --init merely to make a failed check pass.

A missing or changed volume requires investigation against the
protected recovery records.

Volume identities do not prove database integrity.

## 4. Restore Argo CD

Only proceed if the management Kubernetes API is reachable and
the Argo CD installation is confirmed missing.

Check first:

    ./scripts/bootstrap-argocd.sh --check

Inspect the management namespace and Application CRD:

    kubectl --context devops-mgmt get namespace argocd --ignore-not-found
    kubectl --context devops-mgmt get crd applications.argoproj.io --ignore-not-found

For a genuinely missing installation, run:

    ./scripts/bootstrap-argocd.sh --apply

The script installs Argo CD v3.5.3. It refuses to overwrite
detected existing or partial installations.

It currently downloads a version-tagged upstream manifest; an
independent manifest checksum is not yet enforced.

Verify the installation:

    kubectl --context devops-mgmt -n argocd get pods
    kubectl --context devops-mgmt -n argocd get deployments,statefulsets

All seven Argo CD components should become Ready.

## 5. Restore Workload Cluster Registrations

Start a local Argo CD server port-forward in another terminal:

    kubectl --context devops-mgmt -n argocd port-forward svc/argocd-server 18080:443 --address 127.0.0.1

Log in with the newly installed Argo CD admin credentials.

The CLI commands in this runbook use --grpc-web.

Check existing registrations:

    argocd cluster list --grpc-web

The registered workload endpoints previously used the Docker
network gateway 172.18.0.1 with ports 6502 (nonprod) and 6500
(PROD). Verify current networking rather than assuming these
addresses remain unchanged.

Use a temporary kubeconfig for registration. Modify the actual
cluster entry referenced by the context, not the context name.

For nonprod, after confirming the current gateway and port:

    (
      set -euo pipefail
      CONTEXT=devops-nonprod
      GATEWAY=172.18.0.1
      PORT=6502
      TMP_KUBECONFIG="$(mktemp)"
      trap 'rm -f -- "$TMP_KUBECONFIG"' EXIT
      cp "$HOME/.kube/config" "$TMP_KUBECONFIG"
      chmod 600 "$TMP_KUBECONFIG"
      ENTRY="$(kubectl --kubeconfig "$TMP_KUBECONFIG" --context "$CONTEXT" config view --minify -o jsonpath='{.contexts[0].context.cluster}')"
      test -n "$ENTRY"
      kubectl --kubeconfig "$TMP_KUBECONFIG" config set-cluster "$ENTRY" --server="https://$GATEWAY:$PORT" --tls-server-name=localhost
      kubectl --kubeconfig "$TMP_KUBECONFIG" --context "$CONTEXT" get --raw=/readyz
      argocd cluster add "$CONTEXT" --kubeconfig "$TMP_KUBECONFIG" --name "$CONTEXT" --grpc-web
    )

For PROD, use the same procedure with CONTEXT=devops-prod and
PORT=6500, after separately verifying its endpoint.

Cluster registration may create a highly privileged argocd-manager
ServiceAccount and RBAC resources. Review this access before
accepting the CLI confirmation.

Do not disable workload-cluster TLS verification.

Verify:

    argocd cluster list --grpc-web

The remote clusters should eventually report Successful after
Applications target them.

## 6. Restore the GitOps Applications

From devops-lab-gitops:

    kubectl --context devops-mgmt -n argocd apply -f argocd/root-app.yaml

Inspect the proposed changes before syncing:

    argocd app get devops-platform-apps --grpc-web
    argocd app diff devops-platform-apps --grpc-web

A diff exit code of 1 normally indicates differences exist.

Only after verifying the proposed child Applications, synchronize:

    argocd app sync devops-platform-apps --grpc-web

Inspect the child Applications independently:

    argocd app get devops-nonprod --grpc-web
    argocd app get devops-prod --grpc-web

Never synchronize a child Application without reviewing its
rendered manifests and proposed resource changes.

In the October 2026 recovery, Argo CD recreated Namespace/prod
from clusters/prod. The existing DEV and UAT namespaces were
already synchronized.

## 7. Temporary GitHub DNS Workaround

The backup ISP exposed a K3s DNS fallback problem.

K3s rejected Docker's 127.0.0.11 resolver for pod DNS and
selected 8.8.8.8 and Google's IPv6 resolver instead.

Those upstream resolvers were unreachable from CoreDNS.

The management cluster currently has a temporary coredns-custom
ConfigMap forwarding github.com queries to WSL DNS at
10.255.255.254.

Its source is:

    kubernetes/recovery/coredns-github-temporary.yaml

The ConfigMap was applied using:

    kubectl --context devops-mgmt apply -f kubernetes/recovery/coredns-github-temporary.yaml

This workaround restores GitHub DNS resolution without modifying
the K3s-managed main CoreDNS ConfigMap.

The WSL resolver address may change after a restart.

Rollback only after verifying an alternative working DNS path.
First inspect the live coredns-custom ConfigMap and ensure it
contains no unrelated customizations. If this workaround is its
only configuration, it may be deleted using:

    kubectl --context devops-mgmt -n kube-system delete configmap coredns-custom

Also remove the temporary manifest in a subsequent Git change
when the workaround is retired.

Do not remove the workaround while the default upstream DNS
path remains broken.

## 8. Create an Encrypted Recovery Checkpoint

Set WINDOWS_BACKUP_DIR to an existing backup directory mounted
under /mnt/c, then run:

    ./scripts/backup-lab.sh "$WINDOWS_BACKUP_DIR"

The script:

- Verifies persistent Docker volume identities.
- Captures consistent online SQLite backups for all three clusters.
- Preserves K3s server files and credentials.
- Includes Floci metadata, Compose configuration, and Terraform state.
- Includes the private volume baseline and uncommitted recovery tools.
- Encrypts the archive using GPG AES-256.
- Verifies decryption and archive readability.
- Copies the encrypted archive to Windows and checks both copies.

Never commit backup archives, Terraform state, K3s tokens, or
unencrypted recovery files to Git.

Backup copies on WSL and Windows reside on the same physical PC.
They do not protect against complete hardware loss.

The backup has not yet undergone a full restoration rehearsal,
and all captured platform components are not one atomic snapshot.

## 9. Recovery Acceptance Criteria

Before declaring the lab recovered:

- Three original Docker volume identities verified.
- Three Kubernetes APIs and nodes Ready.
- DEV, UAT, and PROD namespaces present.
- Argo CD server and controllers Ready.
- All three Argo CD Applications Synced and Healthy.
- All three Argo CD cluster connections Successful.
- Encrypted backup verified and copied to a second location.

The full WSL shutdown/resume acceptance test remains a separate
milestone. Do not perform it until a verified checkpoint exists.
