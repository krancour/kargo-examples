# 02 — Controller Prometheus metrics

## What this validates

PR [akuity/kargo#6892](https://github.com/akuity/kargo/pull/6892) — the
controller exposes an initial set of Prometheus metrics about Promotions and
Stages. Enabled with the chart value `controller.metrics.enabled=true`,
which binds a metrics server on the controller, adds an `http-metrics`
container port, and creates a `kargo-controller-metrics` Service (plain
HTTP, port 9090 by default).

Metrics under test, all prefixed `kargo_`:

| Metric | Type | Labels |
|---|---|---|
| `kargo_promotions_completed_total` | counter | `project`, `phase` |
| `kargo_promotion_duration_seconds` | histogram | `project`, `phase` |
| `kargo_promotion_step_duration_seconds` | histogram | `project`, `stepKind`, `terminalStatus` |
| `kargo_promotions_non_terminal` | gauge | `project` |
| `kargo_stages_by_ready_reason` | gauge | `project`, `reason` |

## Prerequisites

- A running Kargo control plane installed with
  `--set controller.metrics.enabled=true` (see SETUP.md). The Tilt dev
  stack does **not** enable this by default.
- Nothing else — no fork, no Argo CD Application, no credentials.

## Apply

```bash
kubectl apply -f 03-features/v1.12.0/02-controller-metrics/kargo.yaml
```

## Trigger

Both Stages auto-promote once the Warehouse discovers Freight. To force
discovery:

```bash
kubectl -n kargo-demo-36 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

Wait for the `test` Promotion to reach `Succeeded` and the `broken` one to
reach `Failed`, then scrape:

```bash
kubectl -n kargo port-forward svc/kargo-controller-metrics 9090:9090 &
sleep 2
curl -s http://localhost:9090/metrics | grep 'kargo-demo-36'
kill %1
```

## Expected outcome

1. The metrics Service exists and the scrape returns Prometheus text.
2. The scrape includes, for this project:

   ```text
   kargo_promotions_completed_total{phase="Succeeded",project="kargo-demo-36"} 1
   kargo_promotions_completed_total{phase="Failed",project="kargo-demo-36"} 1
   kargo_promotion_duration_seconds_count{phase="Succeeded",project="kargo-demo-36"} 1
   kargo_promotions_non_terminal{project="kargo-demo-36"} 0
   kargo_stages_by_ready_reason{project="kargo-demo-36",reason="..."} N
   ```

   Exact counts grow with re-runs; the `Failed` sample does not reappear
   because auto-promotion does not retry Freight whose last Promotion failed.
3. `kargo_stages_by_ready_reason` sums to 2 across reasons for this project
   (one row per readiness reason; `test` and `broken` will usually report
   different reasons).

## Troubleshooting

- **`svc/kargo-controller-metrics` not found** — metrics are off. Upgrade
  the release with `--set controller.metrics.enabled=true` and wait for the
  controller to roll.
- **No `kargo-demo-36` samples** — counters are recorded when a Promotion
  reaches a terminal phase after the controller started. Confirm both
  Promotions are terminal, then scrape again. Gauges are computed on each
  scrape from the live Stages and Promotions.
- **Port 9090 is busy** — pick another local port:
  `port-forward svc/kargo-controller-metrics 19090:9090`.
