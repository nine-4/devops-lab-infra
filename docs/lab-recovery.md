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

From the infrastructure repository, run:

    ./scripts/lab-up.sh

No fresh backup is needed immediately before ordinary or unexpected
WSL shutdown. Existing Docker volumes are intended to persist.

The startup script verifies recorded volume identities, existing
containers, safe Floci settings, and EKS authentication webhook
endpoints before starting the existing Kubernetes containers.

It must not create, recreate, or prune infrastructure.

Inspect the resulting state with:

    ./scripts/lab-status.sh

Floci may still report EKS clusters as CREATING while Kubernetes is
operational. This produces known DEGRADED warnings (exit code 1).
Other failures must be investigated separately.

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

### EKS Authentication Webhook Recovery

During the October 2026 shutdown/resume test, K3s retained the old
Floci webhook IP address 172.18.0.2 after Docker reassigned IPs.

The resulting Kubernetes authentication error was Unauthorized,
although native K3s administrative access remained operational.

The approved webhook endpoint is:

    http://floci:4566/_floci/eks/token-webhook

Verify the existing webhook configurations using:

    ./scripts/verify-eks-webhooks.sh

This is a read-only check and also works with stopped containers.

If validation fails, do not automatically rewrite configuration files
or recreate containers. Inspect the Docker network and actual webhook
endpoints, verify the original volume identities, and preserve the
original configurations before considering a manual repair.

The verified repair changed the exact stale endpoint in each existing
K3s container to the Floci hostname. Each container was restarted
individually using docker restart --timeout 90.

After each restart, the original container and volume identities were
verified, followed by native Kubernetes API readiness and external
EKS-token authentication.

Any future manual repair must be performed one cluster at a time.
Do not overwrite unknown webhook configurations.

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

## 7. DNS Recovery and Retired GitHub Workaround

External DNS resolution previously failed when K3s selected
upstream DNS resolvers that were unreachable from CoreDNS.

A temporary coredns-custom ConfigMap forwarded GitHub DNS queries
to the WSL DNS resolver at 10.255.255.254.

Subsequent tests confirmed normal CoreDNS forwarding and direct
DNS queries to Google's public DNS servers.

The temporary ConfigMap was removed on October 12, 2026.

Subsequent verification confirmed:

- Internal Kubernetes DNS resolution works.
- GitHub resolves through CoreDNS without the temporary rule.
- Argo CD's repository server can access GitHub over HTTPS.

The historical recovery manifest remains at:
kubernetes/recovery/coredns-github-temporary.yaml

Do not automatically reapply it. The WSL DNS address may change.
The K3s-managed main CoreDNS ConfigMap must not be manually edited.

The original failure conditions have not been reproduced, so
compatibility under different network conditions remains unverified.

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

After startup, verify:

- All three original Docker volume identities match the baseline.
- All Kubernetes APIs respond and nodes report Ready.
- External EKS-token authentication works in all three clusters.
- DEV, UAT, and PROD namespaces remain present.
- Argo CD components are Ready.
- All three Argo CD Applications are Synced and Healthy.
- All three Argo CD cluster connections report Successful.
- GitHub DNS and repository access work.
- No unexpected infrastructure recreation has occurred.

The first controlled WSL shutdown/resume test preserved every
recorded Docker volume and Kubernetes resource identity.

External authentication initially required manual webhook repair.

The final automated WSL cold-start acceptance test passed.
After reopening WSL, ./scripts/lab-up.sh started the six
existing containers and recovered all three Kubernetes APIs
with working EKS authentication. No manual webhook repair,
container recreation, or new pre-shutdown backup was needed.

All three original Docker volume identities and all ten
tracked Kubernetes resource UIDs matched the original baseline.
All seven Argo CD pods were Ready, all three registered cluster
connections reported Successful, and all three Applications
reported Synced and Healthy. GitHub repository connectivity
from the Argo CD repo-server was also verified.

The known Floci CREATING warnings may remain.

Encrypted backups must be maintained for disaster recovery,
but full backup restoration has not yet been rehearsed.
