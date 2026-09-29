# 02 — Multiple authorized Stages on one Argo CD Application

## What this validates

PR [akuity/kargo#6398](https://github.com/akuity/kargo/pull/6398) — the
`kargo.akuity.io/authorized-stage` annotation on an Argo CD `Application`
now accepts a **comma-separated list** of `<project>:<stage>` entries, so
several Stages can each manage a distinct artifact within the same
Application. (A single `<project>:<stage>` value remains valid.)

This example runs both directions of the authorization check:

- `frontend` and `backend` are both listed in the annotation. Each updates
  a different Helm parameter of the same Application (`image.tag` and
  `metrics.image.tag` respectively) and both must succeed.
- `denied` is not listed. Its Promotions must fail with an authorization
  error.

## Prerequisites

- A running Kargo control plane (Tilt dev stack: `make hack-tilt-up`).
- Argo CD installed in the `argocd` namespace (the Tilt stack does this).
- No fork and no Git credentials — the Application deploys a public Helm
  chart directly.

## Apply

```bash
kubectl apply -f 03-features/v1.11.0/02-multi-authorized-stages/argocd.yaml
kubectl apply -f 03-features/v1.11.0/02-multi-authorized-stages/kargo.yaml
```

## Trigger

All three Stages auto-promote once the Warehouse discovers Freight. To
force discovery:

```bash
kubectl -n kargo-demo-34 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. Promotions to `frontend` and `backend` both **succeed**, even though
   they target the same Application.
2. The Application's spec reflects both Stages' updates:

   ```bash
   kubectl -n argocd get application kargo-demo-34 \
     -o jsonpath='{.spec.source.helm.parameters}' | jq
   ```

   `image.tag` (set by `frontend`) and `metrics.image.tag` (set by
   `backend`) both carry the promoted nginx version.
3. The Promotion to `denied` **fails** (phase `Errored`):

   ```bash
   kubectl -n kargo-demo-34 get promotions \
     -o custom-columns=NAME:.metadata.name,STAGE:.spec.stage,PHASE:.status.phase
   ```

   Its `status.message` contains
   `Argo CD Application "kargo-demo-34" in namespace "argocd" is not
   authorized`. (The controller logs the more detailed reason — `does not
   permit mutation by Kargo Stage denied in namespace kargo-demo-34` — as a
   warning rather than surfacing it in the Promotion's status.)

## Troubleshooting

- **`frontend`/`backend` promotion errors with an authorization message** —
  the annotation is a single comma-separated value; check for whitespace
  or a typo in an entry
  (`kubectl -n argocd get application kargo-demo-34 -o jsonpath='{.metadata.annotations}'`).
  Every entry must be exactly `<project>:<stage>`.
- **`denied` promotion succeeds** — you're probably running a Kargo
  version where some glob-style entry in the annotation matches it;
  inspect the annotation and remove any wildcard entries.
- **The two authorized Stages' Promotions race** — that's expected and
  fine here: they update disjoint Helm parameters. The note in the
  [annotation docs](https://docs.kargo.io/user-guide/reference-docs/annotations)
  cautions against multiple Stages that disagree about the *same* desired
  state — e.g. both setting `image.tag` — which manifests as an
  Application that never settles into sync.
