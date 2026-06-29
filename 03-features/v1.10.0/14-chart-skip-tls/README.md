# 14 — Chart subscription `insecureSkipTLSVerify`

## What this validates

PR [akuity/kargo#5987](https://github.com/akuity/kargo/pull/5987) — chart
subscriptions on a Warehouse now support `insecureSkipTLSVerify`. Until
1.10, the flag existed for git and image subscriptions but not for chart
ones, leaving operators of self-signed Helm chart repos with no good
option.

This example stands up a real, in-cluster HTTPS Helm chart repository
(ChartMuseum + a cert-manager-issued self-signed cert) seeded with three
versions of a tiny `hello` chart. The Warehouse subscribes with
`insecureSkipTLSVerify: true`. With the flag set, discovery succeeds.
Flip it to `false` to see discovery fail with
`x509: certificate signed by unknown authority`.

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- **cert-manager** installed in the cluster — the Tilt stack installs it
  automatically; otherwise:
  ```bash
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
  ```
- That's it. No fork, no Argo CD, no GitHub credentials.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
# 1) Create the Project namespace first so the chart-repo Issuer/Cert
#    have somewhere to live.
kubectl apply -f 03-features/14-chart-skip-tls/kargo.yaml

# 2) Bring up the in-cluster self-signed HTTPS chart repo.
kubectl apply -f 03-features/14-chart-skip-tls/chart-repo.yaml

# 3) Wait for ChartMuseum to be ready (initContainer packages the chart,
#    cert-manager mints the cert):
kubectl -n kargo-demo-28 rollout status deploy/chart-repo --timeout=2m
```

## Trigger

Force the Warehouse to discover:

```bash
kubectl -n kargo-demo-28 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

Within a few seconds:

```bash
kubectl -n kargo-demo-28 get warehouse kargo-demo -o yaml \
  | yq '.status.discoveredArtifacts.charts[0].versions[]'
```

You should see three versions of the `hello` chart: `1.0.0`, `1.0.1`,
`1.1.0`. A `Freight` resource appears bundling the latest matching
version.

## Validate the flag actually does something

Toggle the flag off:

```bash
kubectl -n kargo-demo-28 patch warehouse kargo-demo --type=merge -p \
  '{"spec":{"subscriptions":[{"chart":{"repoURL":"https://chart-repo.kargo-demo-28.svc:8443","name":"hello","semverConstraint":"^1.0.0","discoveryLimit":5,"insecureSkipTLSVerify":false}}]}}'
kubectl -n kargo-demo-28 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

`kubectl -n kargo-demo-28 get warehouse kargo-demo -o yaml` now shows the
`Healthy` condition flipping to `False` with a message containing
`x509: certificate signed by unknown authority` (or
`tls: failed to verify certificate`). Flip it back to `true` and the next
discovery succeeds.

## Cleanup

```bash
kubectl delete -f 03-features/14-chart-skip-tls/chart-repo.yaml
kubectl delete -f 03-features/14-chart-skip-tls/kargo.yaml
```

## Troubleshooting

- **`chart-repo` pod CrashLoopBackOff at startup** — usually means the
  TLS Secret hasn't materialized yet. cert-manager mints
  `chart-repo-tls` lazily; give it ~10s after applying. Check
  `kubectl -n kargo-demo-28 get cert chart-repo-tls` →
  `READY=True`.
- **Discovery fails despite the flag** — confirm the flag is on the
  *chart* subscription, not on a sibling git/image subscription:
  ```bash
  kubectl -n kargo-demo-28 get warehouse kargo-demo -o jsonpath='{.spec.subscriptions[*].chart.insecureSkipTLSVerify}'
  ```
  Should print `true`.
- **`cert-manager` API not available** — `kubectl get crd
  certificates.cert-manager.io` should return non-empty. If not, install
  cert-manager (see Prerequisites).
- **`Healthy=False` with a `connection refused` error** — ChartMuseum
  isn't running. `kubectl -n kargo-demo-28 logs deploy/chart-repo
  -c chartmuseum` will tell you why; common cause is the `tls.crt` /
  `tls.key` paths being wrong (env vars `TLS_CERT` / `TLS_KEY` in
  `chart-repo.yaml`).
