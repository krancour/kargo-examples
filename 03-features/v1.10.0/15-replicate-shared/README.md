# 15 — Shared resource replication via `kargo.akuity.io/replicate-to`

## What this validates

PR [akuity/kargo#5789](https://github.com/akuity/kargo/pull/5789) — Secrets
and ConfigMaps in the shared resources namespace can opt into automatic
replication into every Project namespace by carrying the annotation
`kargo.akuity.io/replicate-to: "*"` (today `"*"` is the only supported
value).

The replication reconciler:

- Copies the resource into each Project namespace.
- Strips noisy annotations (`kubectl.kubernetes.io/last-applied-…`) before
  hashing/replicating.
- Stamps the replica with `kargo.akuity.io/replicated-at: <UTC timestamp>`.
- Re-reconciles when the source changes (hash-based dirty check).

> ⚠️ **Gotcha specific to Secrets**: the Secret-specific adapter
> ([pkg/controller/management/replication/secret.go](../../pkg/controller/management/replication/secret.go)'s
> `shouldReconcile`) silently skips any Secret that lacks a
> `kargo.akuity.io/cred-type` label. The intent is to keep the reconciler
> out of random, non-credential Secrets that happen to live in
> `kargo-shared-resources`. Values Kargo recognizes are `git`, `image`,
> `helm`, and `generic`. ConfigMaps have no such gate.

This example creates one shared Secret, one Project, and a single-stage
pipeline that reads two fields out of the replicated Secret to prove it's
usable by name from the Project namespace.

## Prerequisites

- A running Kargo control plane with the management controller running
  (Tilt: `make hack-tilt-up`).
- The shared resources namespace must match the management controller's
  configured `SHARED_RESOURCES_NAMESPACE` env var. In the chart this maps
  to the value `controller.sharedResourcesNamespace` (default
  `kargo-shared-resources`). The Tilt dev stack honors that default.
- No image credentials beyond outbound HTTPS to `public.ecr.aws`.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster (creates the
                                       # kargo-shared-resources namespace
                                       # and other shared resources)
```

## Apply

```bash
kubectl apply -f 03-features/15-replicate-shared/kargo.yaml
```

## Trigger

The replication reconciler runs on Secret/ConfigMap events plus its own
periodic resync. Within seconds of `kubectl apply`, the replica should
exist:

```bash
kubectl -n kargo-demo-29 get secrets -o wide
```

If you want to also see the promotion read it, force discovery:

```bash
kubectl -n kargo-demo-29 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. A Secret named `shared-config` exists in **both**
   `kargo-shared-resources` (the source) and `kargo-demo-29` (the
   replica).
2. The replica carries the annotation
   `kargo.akuity.io/replicated-at: <RFC 3339 UTC timestamp>`.
3. Inspect the Stage:
   ```bash
   kubectl -n kargo-demo-29 get stage test -o yaml \
     | yq '.metadata.annotations'
   ```
   The `set-metadata` step writes the Secret's contents into the Stage's
   metadata block, so you'll see `greeting: "Hello from the shared
   config secret!"` and the `apiBaseURL`.
4. Edit the source Secret's `greeting` value and re-apply →
   the replica updates within a reconcile cycle.

## Troubleshooting

- **No replica appears in the project namespace** — check the management
  controller logs:
  `kubectl -n kargo logs deploy/kargo-management-controller`.
  Common causes: `SHARED_RESOURCES_NAMESPACE` env var isn't set; the
  source Secret is in a namespace other than the configured one; the
  controller doesn't have RBAC to write Secrets in project namespaces.
- **Step fails with `secret not found`** — name resolution looks in the
  Project namespace. Check `kubectl -n kargo-demo-29 get secret
  shared-config` exists.
- **Annotation `replicate-to` set to anything other than `*`** — only
  `*` is currently supported. Other values are ignored (no replication).
- **Replica gets out of date when the source changes** — verify the
  source mutation actually changed the hashed content. Annotations under
  `kubectl.kubernetes.io/last-applied-configuration` are excluded from
  the hash, so updates that ONLY change that won't trigger replication.
