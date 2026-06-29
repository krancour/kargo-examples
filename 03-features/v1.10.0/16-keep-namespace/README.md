# 16 — `kargo.akuity.io/keep-namespace` annotation

## What this validates

Bug fix [akuity/kargo#5763](https://github.com/akuity/kargo/issues/5763)
(merged as commit `1a9620a26`). The `kargo.akuity.io/keep-namespace: "true"`
annotation prevents Kargo from cascading-deleting the Project's namespace
when the `Project` resource is deleted.

The annotation works on either:

- the `Namespace` itself (this example), or
- the `Project` resource (commented in the manifest, swap if preferred).

Useful when the Project namespace pre-existed Kargo and contains
unrelated workloads you don't want pulled down with the Project.

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- No other prerequisites.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/16-keep-namespace/kargo.yaml
```

## Trigger

Wait for the Project to reach a Ready state (a few seconds), then
deliberately delete it:

```bash
kubectl get project kargo-demo-30
kubectl delete project kargo-demo-30
```

## Expected outcome

Immediately after the delete:

```bash
kubectl get ns kargo-demo-30
kubectl -n kargo-demo-30 get configmap my-other-app-config
```

- The Namespace `kargo-demo-30` still exists.
- The unrelated ConfigMap `my-other-app-config` still exists.
- The Kargo CRDs (Warehouse, Stage, etc.) have been removed by Project
  deletion's normal cascade.

You can re-create the Project in the same namespace if desired:

```bash
kubectl apply -f 03-features/16-keep-namespace/kargo.yaml
```

…and Kargo will adopt the existing Namespace rather than creating a new
one.

## Cleanup

If you actually want the Namespace gone:

```bash
kubectl annotate ns kargo-demo-30 kargo.akuity.io/keep-namespace-
kubectl delete ns kargo-demo-30
```

(Note the trailing `-` on the annotation key — that's how `kubectl
annotate` removes an annotation.)

## Troubleshooting

- **Namespace was deleted anyway** — the annotation must be present at
  the moment the Project is deleted. If you applied the manifest, then
  removed the annotation before deleting the Project, the namespace
  cascade-deletes normally. Re-add and re-test.
- **Project deletion hangs** — unrelated; usually a finalizer on the
  Project waiting on something. Check
  `kubectl get project kargo-demo-30 -o yaml` for `finalizers:` and
  recent events.
- **Project apply fails: "namespace already exists"** — the management
  controller is correctly refusing to overwrite a namespace that wasn't
  created by Kargo, unless the namespace already carries the
  `kargo.akuity.io/keep-namespace` annotation (or an explicit
  project-association annotation). The manifest pre-annotates the
  namespace, so this should not happen with this example as-shipped.
