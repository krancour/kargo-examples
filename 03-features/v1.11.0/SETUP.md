# Kargo 1.11 Feature Validation — Setup Guide

Both v1.11 examples are "zero-fork": no GitHub fork, no Git credentials,
and no `00-common` resources are required. Each example's own `README.md`
has per-example **Trigger** and **Expected outcome** sections; this page
only covers the shared plumbing.

## Step 1 — Cluster and Kargo

Bring up (or confirm) a local Kargo dev stack:

```bash
make hack-tilt-up
```

The Tilt UI lives at <http://localhost:10350>, the Kargo UI at
<http://localhost:30082> (admin/admin), and the API at
<http://localhost:30081> (the dev stack runs the API with TLS disabled).

> ✅ **You can now run: 01.**

## Step 2 — Argo CD (only needed for 02)

Argo CD must be installed in the `argocd` namespace with admin/admin
available at <http://localhost:30080>. The Tilt stack installs it
automatically. If you're running Kargo some other way, install Argo CD
yourself and make sure the `kargo-controller` can talk to its API.

> ✅ **You can now run: 02.**

## Running any example

All commands in these examples assume your working directory is the root of
this repository (`kargo-examples`).

```bash
kubectl apply -f 03-features/v1.11.0/NN-<name>/argocd.yaml   # if present
kubectl apply -f 03-features/v1.11.0/NN-<name>/kargo.yaml
```

Force Warehouse discovery whenever you want a promotion to fire
immediately:

```bash
kubectl -n kargo-demo-NN annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Getting an API token (only needed for the `curl` verifications)

Some examples verify API responses directly. Mint an admin token:

```bash
KARGO_TOKEN=$(curl -s -X POST http://localhost:30081/v1beta1/login \
  -H "Authorization: Bearer admin" | jq -r .idToken)
```

(The admin password rides in the `Authorization` header; the response's
`idToken` is what subsequent requests use as their bearer token.)

## Cleanup

Each example lives in its own `kargo-demo-NN` namespace:

```bash
kubectl delete -f 03-features/v1.11.0/NN-<name>/kargo.yaml
kubectl delete -f 03-features/v1.11.0/NN-<name>/argocd.yaml   # if present
```
