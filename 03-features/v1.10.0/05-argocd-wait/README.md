# 05 — `argocd-wait` step (explicit Argo CD readiness gate)

## What this validates

PR [akuity/kargo#5832](https://github.com/akuity/kargo/pull/5832) — the new
standalone `argocd-wait` promotion step.

`argocd-wait` blocks promotion until the named (or selected) Argo CD
`Application` resources reach the requested conditions. Unlike the wait
implicit in `argocd-update`, this step:

- Can be invoked anywhere in the pipeline, any number of times.
- Supports **label selectors** as well as exact names.
- Lets you choose the conditions to wait on: `health`, `sync`,
  `operation`, `suspended`, `degraded`. Health-family conditions (`health`,
  `suspended`, `degraded`) are OR'd; the rest are AND'd.

This example uses the exact-name variant in `test`. The selector-based
variant is a drop-in replacement; a commented-out snippet in `kargo.yaml`
shows how.

## Prerequisites

- A running Kargo control plane (Tilt dev stack:
  `make hack-tilt-up`).
- Argo CD installed in the `argocd` namespace.
- The shared `github` Secret in `kargo-shared-resources` (already in
  `00-common/kargo.yaml`) granting Kargo write access to your fork of
  `kargo-demo-gitops`.
- Fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops):
  - `kustomize` branch must exist.
  - `19/stage/test` will be auto-created.
- Replace every `<github-username>` in `argocd.yaml` and `kargo.yaml`.

## Setup

```bash
make hack-tilt-up                           # if not already running
kubectl apply -f 00-common/kargo.yaml       # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/05-argocd-wait/argocd.yaml
kubectl apply -f 03-features/05-argocd-wait/kargo.yaml
```

## Trigger

Auto-promotion to `test` should kick off as soon as the Warehouse discovers
Freight. To force discovery:

```bash
kubectl -n kargo-demo-19 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. The promotion runs through normal kustomize/git steps, then reaches
   `argocd-wait`.
2. The step blocks until `kargo-demo-19-test` is `Healthy` + `Synced` +
   operationally idle (i.e. no in-progress operation).
3. On success, the Promotion's step outputs include `healthStatus` keyed
   by `argocd/kargo-demo-19-test`.
4. Flip to the selector-based variant by uncommenting the alternative
   block in `kargo.yaml` (and commenting out the name-based one). The
   `Application` in `argocd.yaml` already carries matching labels.

## Troubleshooting

- **`argocd-wait` step times out** — typical causes: the Application
  isn't actually pointing at the branch the promotion just pushed to
  (recheck the `kargo.akuity.io/authorized-stage` annotation matches
  `<project>:<stage>`); or the Application is `Unknown` sync because
  Argo CD can't reach the repo.
- **Selector matches zero apps** — the labels on the `Application` in
  `argocd.yaml` don't match the selector. If you replaced it with your
  own `Application`, mirror those labels.
- **`degraded` as an acceptable terminal state** — adding `degraded` to
  `waitFor` OR's it with `health`, so the wait completes if the app is
  either `Healthy` or `Degraded`. Useful when degraded-but-steady is
  acceptable for a given stage.
