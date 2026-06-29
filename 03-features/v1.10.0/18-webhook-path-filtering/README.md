# 18 — Webhook path filtering (`includePaths` honored on push events)

## What this validates

PR [akuity/kargo#5611](https://github.com/akuity/kargo/pull/5611) — webhook
receivers for providers that include changed-file lists in their push
payloads (GitHub, GitLab, Gitea) now honor the Warehouse's
`includePaths` / `excludePaths` filters when deciding whether to refresh
the Warehouse.

Behavior is **transparent** — there is no new field on the receiver or
Warehouse, just the existing `includePaths`. A receiver-driven refresh
that previously fired on every push to the watched branch now fires only
when the push touches files matching `includePaths` (or doesn't match
`excludePaths`).

This is unrelated to discovery-time path filtering (Kargo has always
honored `includePaths` when crawling commits during discovery). The new
behavior cuts unnecessary discovery passes triggered by webhooks for
no-op pushes.

Providers whose payloads do NOT include file lists (Azure, Bitbucket,
Docker Hub, Quay, Harbor, Artifactory, generic) keep their old behavior:
they always trigger refresh.

## Prerequisites

- A running Kargo control plane with the external webhooks server reachable
  from GitHub (Tilt: `make hack-tilt-up` exposes it on
  `localhost:30083`; for GitHub to reach it from the public internet you
  need an ingress, an ngrok tunnel, or a similar relay).
- The cluster-level GitHub webhook receiver from `00-common/kargo.yaml`
  applied (it ships with a `github-receiver` Secret and the
  `webhookReceivers[].github` block on ClusterConfig).
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops).
- **A `manifests` branch on your fork** containing a `manifests/`
  directory with at least one file. Suggested seed:
  ```bash
  git clone https://github.com/<github-username>/kargo-demo-gitops.git
  cd kargo-demo-gitops
  git checkout --orphan manifests
  git rm -rf .
  mkdir -p manifests
  echo 'apiVersion: v1' > manifests/configmap.yaml
  echo 'kind: ConfigMap' >> manifests/configmap.yaml
  echo 'metadata:' >> manifests/configmap.yaml
  echo '  name: demo-config' >> manifests/configmap.yaml
  echo 'data:' >> manifests/configmap.yaml
  echo '  greeting: hello' >> manifests/configmap.yaml
  echo '# Initial commit on the manifests branch.' > README.md
  git add manifests README.md
  git commit -m "Seed manifests branch for kargo-demo-32"
  git push origin manifests
  ```
- An ngrok (or equivalent) tunnel forwarding to `localhost:30083` so
  GitHub can deliver webhooks. Note the public URL.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/18-webhook-path-filtering/kargo.yaml
```

Get the receiver's URL path:

```bash
kubectl get clusterconfig cluster -o yaml \
  | yq '.status.webhookReceivers[] | select(.name=="github") | .path'
```

…and the secret it expects:

```bash
kubectl -n kargo-cluster-secrets get secret github-receiver \
  -o jsonpath='{.data.secret}' | base64 -d ; echo
```

Configure your fork's webhook (Settings → Webhooks → Add webhook):

- **Payload URL**: `https://<your-tunnel-host><path-from-above>`
- **Content type**: `application/json`
- **Secret**: the value printed above
- **Events**: just the push event
- **Active**: ✓

## Trigger / Validate

Make TWO commits on the `manifests` branch and watch which one refreshes
the Warehouse.

### Negative case — no refresh expected

```bash
cd kargo-demo-gitops
git checkout manifests
echo "edit at $(date)" >> README.md
git add README.md
git commit -m "Touch only README"
git push origin manifests
```

Watch:

```bash
kubectl -n kargo-demo-32 get warehouse kargo-demo -o yaml \
  | yq '.status.lastHandledRefresh,.status.discoveredArtifacts.git[0].commits[0].id'
```

`lastHandledRefresh` should NOT change. The Warehouse should not have
re-run discovery.

### Positive case — refresh expected

```bash
echo "data: $(date)" >> manifests/configmap.yaml
git add manifests/configmap.yaml
git commit -m "Update manifests/configmap.yaml"
git push origin manifests
```

Within seconds:

```bash
kubectl -n kargo-demo-32 get warehouse kargo-demo -o yaml \
  | yq '.status.lastHandledRefresh,.status.discoveredArtifacts.git[0].commits[0].id'
```

`lastHandledRefresh` updates, the latest discovered commit ID is the new
one, and a new Freight resource appears.

## Expected outcome (summary)

| Push touched | Webhook delivered? | Warehouse refreshed? |
|--------------|--------------------|----------------------|
| Only `README.md` | Yes (GitHub still delivers) | **No** — filtered by `includePaths` |
| `manifests/configmap.yaml` | Yes | **Yes** |
| Both files | Yes | **Yes** (any matching path is enough) |

## Troubleshooting

- **Webhook not delivered at all** — check the GitHub Webhooks UI for
  delivery errors. 401 → secret mismatch. Connection refused → tunnel
  down. 404 → wrong receiver path.
- **Webhook delivered but warehouse doesn't refresh on a manifests push**
  — confirm the push payload's `commits[].modified/added/removed` lists
  include a path matching `manifests/**`. GitHub elides these lists for
  pushes with > 3000 file changes; in that case Kargo falls back to
  refreshing.
- **Warehouse refreshes even on README-only pushes** — the path
  filter only applies to providers whose payloads include file lists.
  If your webhook URL is the `generic` receiver instead of `github`,
  no filtering happens. Confirm via the `clusterconfig` status path.
- **Refresh fires twice** — sometimes the initial Stage reconcile and
  the webhook arrive close together; benign.
