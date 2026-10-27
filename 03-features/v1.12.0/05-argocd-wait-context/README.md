# 05 — Argo CD deep links from `argocd-wait` alone

## What this validates

PR [akuity/kargo#6766](https://github.com/akuity/kargo/pull/6766) — the
`kargo.akuity.io/argocd-context` annotation on a Stage, which the UI uses to
build deep links into Argo CD, is now populated from promotion step
**output**. Both `argocd-update` and `argocd-wait` report the Applications
they resolved under an `apps` output key (`[{name, namespace}]`), with the
namespace always concrete even when apps were selected by label.

Previously the annotation came only from the health-check criteria that
`argocd-update` registers. `argocd-wait` registers none, so a Stage that
only waited on an Application had no deep link. This example is exactly
that Stage.

## Prerequisites

- A running Kargo control plane.
- Argo CD in the `argocd` namespace (admin/admin at <http://localhost:30080>).
- No fork and no credentials — the Application deploys the public podinfo
  chart and syncs itself.

## Apply

```bash
kubectl apply -f 03-features/v1.12.0/05-argocd-wait-context/argocd.yaml
kubectl apply -f 03-features/v1.12.0/05-argocd-wait-context/kargo.yaml
```

## Trigger

`test` auto-promotes as soon as the Warehouse produces Freight. To force
discovery:

```bash
kubectl -n kargo-demo-39 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

The Promotion's single step waits until the Application is Synced and
Healthy, which podinfo reaches on its own within a minute or two of apply.

## Expected outcome

1. The Promotion succeeds. Its recorded step output names the Application:

   ```bash
   kubectl -n kargo-demo-39 get promotions \
     -o jsonpath='{.items[-1:].status.state.wait.apps}'; echo
   ```

   Expect `[{"name":"kargo-demo-39","namespace":"argocd"}]`.
2. The Stage carries the annotation, built from that output:

   ```bash
   kubectl -n kargo-demo-39 get stage test \
     -o jsonpath='{.metadata.annotations.kargo\.akuity\.io/argocd-context}'; echo
   ```

   Expect the same list: `[{"name":"kargo-demo-39","namespace":"argocd"}]`.
3. In the Kargo UI the `test` Stage shows an Argo CD link that opens
   `kargo-demo-39` in Argo CD. (Before #6766 this Stage showed none.)
4. The Stage's health is unchanged by this feature: `argocd-wait` still
   registers no health check, so `test` reports `Healthy` on the strength of
   its Promotion alone rather than by tracking the Application.

## Troubleshooting

- **The step never finishes** — the Application isn't reaching
  Synced/Healthy. `kubectl -n argocd get application kargo-demo-39` shows
  its state; podinfo pulls `ghcr.io/stefanprodan/podinfo`, so check for
  image pull errors in `kargo-demo-39-app`.
- **Output is present but the annotation is missing** — the annotation is
  written by the Stage reconciler after the Promotion succeeds, so give it a
  moment. If it still never appears, check the controller logs for
  `argocd-context`.
- **`argocd-wait` errors with a permissions problem** — the Kargo
  controller must be able to read `Application` resources in `argocd`. The
  chart grants this when Argo CD integration is enabled (the default).
