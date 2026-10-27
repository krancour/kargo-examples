# Kargo 1.12 Feature Validation — Setup Guide

Four of the six v1.12 examples are "zero-fork": no GitHub fork, no Git
credentials, and no `00-common` resources. Example 03 needs a fork and the
shared GitHub credentials; example 05 needs Argo CD; example 04 needs
cert-manager; example 02 needs the controller's metrics turned on. Each
example's own `README.md` has per-example **Trigger** and **Expected
outcome** sections; this page only covers the shared plumbing.

## Step 1 — Prerequisites on the cluster

These mirror the kargo repo's `hack-install-*` Makefile targets. All three
are needed by at least one example, and the Kargo chart expects
cert-manager.

```bash
helm upgrade cert-manager cert-manager --repo https://charts.jetstack.io \
  --version 1.19.3 --install --create-namespace --namespace cert-manager \
  --set crds.enabled=true --wait

helm upgrade argocd argo-cd --repo https://argoproj.github.io/argo-helm \
  --version 9.4.3 --install --create-namespace --namespace argocd \
  --set 'configs.secret.argocdServerAdminPassword=$2a$10$5vm8wXaSdbuff0m9l21JdevzXBzJFPCi8sy6OOnpZMAG.fOXL7jvO' \
  --set 'configs.params."application\.namespaces"=*' \
  --set server.service.type=NodePort --set server.service.nodePortHttp=30080 \
  --wait

helm upgrade argo-rollouts argo-rollouts --repo https://argoproj.github.io/argo-helm \
  --version 2.40.6 --install --create-namespace --namespace argo-rollouts --wait
```

Argo CD is admin/admin at <http://localhost:30080>.

## Step 2 — Kargo

Install the chart under test with the API on NodePort 30081, TLS off,
admin/admin, and **controller metrics enabled** (example 02 depends on it;
the chart default is off):

```bash
helm upgrade kargo oci://ghcr.io/akuity/kargo-charts/kargo --version 1.12.0 \
  --install --create-namespace --namespace kargo \
  --set api.host=localhost:30081 --set api.tls.enabled=false \
  --set api.service.type=NodePort --set api.service.nodePort=30081 \
  --set 'api.adminAccount.passwordHash=$2a$10$Zrhhie4vLz5ygtVSaif6o.qN36jgs6vjtMBdM6yrU1FOeiAAMMxOm' \
  --set api.adminAccount.tokenSigningKey=iwishtowashmyirishwristwatch \
  --set controller.metrics.enabled=true \
  --wait
```

If you use the Tilt dev stack instead (`make hack-tilt-up`), add
`controller.metrics.enabled: true` to `hack/tilt/values.dev.yaml` before
bringing it up, or example 02 has nothing to scrape.

> ✅ **You can now run: 01, 02, 04, 05, 06.**

## Step 3 — Fork and credentials (only needed for 03)

Example 03 opens and merges a pull request on your fork of
[krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops)
and then deletes the PR's source branch. It needs the shared GitHub
credentials from `00-common/kargo.yaml` (a GitHub App with `Contents: Read
& write` and `Pull requests: Read & write` on the fork):

```bash
kubectl apply -f 00-common/kargo.yaml   # once per cluster
```

> ✅ **You can now run: 03.**

## Running any example

All commands assume your working directory is the root of this repository
(`kargo-examples`). Substitute `<github-username>` at apply time rather than
editing files in place. If your fork is not named `kargo-demo-gitops`, map
the repository name in the same pipe:

```bash
GH_USER=<your-github-username>
sed "s|<github-username>|$GH_USER|g" 03-features/v1.12.0/NN-<name>/kargo.yaml | kubectl apply -f -

# fork named differently, e.g. kargo-demo-gitops-2:
sed -e "s|<github-username>/kargo-demo-gitops.git|$GH_USER/kargo-demo-gitops-2.git|g" \
    -e "s|<github-username>|$GH_USER|g" \
  03-features/v1.12.0/NN-<name>/kargo.yaml | kubectl apply -f -
```

Apply `argocd.yaml` first when an example has one. Force Warehouse
discovery whenever you want a promotion to fire immediately:

```bash
kubectl -n kargo-demo-NN annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Getting an API token (only needed for `curl` verifications)

```bash
KARGO_TOKEN=$(curl -s -X POST http://localhost:30081/v1beta1/login \
  -H "Authorization: Bearer admin" | jq -r .idToken)
```

## Cleanup

Each example lives in its own `kargo-demo-NN` namespace:

```bash
kubectl delete -f 03-features/v1.12.0/NN-<name>/kargo.yaml
kubectl delete -f 03-features/v1.12.0/NN-<name>/argocd.yaml   # if present
```
