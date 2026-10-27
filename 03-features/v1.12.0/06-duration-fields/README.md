# 06 — Mutating webhooks leave duration fields as written

## What this validates

PR [akuity/kargo#7150](https://github.com/akuity/kargo/pull/7150) — Kargo's
mutating admission webhooks no longer rewrite duration fields they did not
touch. A `metav1.Duration` written as `2h` remarshals as `2h0m0s`, and the
webhooks' defaulting path used to emit that difference as a patch on every
create and update. Now shorthand durations survive both.

Fields exercised: `Warehouse.spec.interval`, a Stage's
`requestedFreight[].sources.requiredSoakTime`, and a promotion step's
`retry.timeout`.

## Prerequisites

- A running Kargo control plane.
- Nothing else — no fork, no Argo CD Application, no credentials, and no
  Promotion is needed.

## Apply

```bash
kubectl apply -f 03-features/v1.12.0/06-duration-fields/kargo.yaml
```

## Trigger

Creating the resources is the first test (the webhook runs on create).
Then put each resource through an update that the webhook also sees:

```bash
kubectl -n kargo-demo-40 label stage uat touched=yes --overwrite
kubectl -n kargo-demo-40 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

Both immediately after apply and again after the updates above, every
duration reads back exactly as written:

```bash
kubectl -n kargo-demo-40 get warehouse kargo-demo -o jsonpath='{.spec.interval}'; echo
kubectl -n kargo-demo-40 get stage uat \
  -o jsonpath='{.spec.requestedFreight[0].sources.requiredSoakTime}'; echo
kubectl -n kargo-demo-40 get stage uat \
  -o jsonpath='{.spec.promotionTemplate.spec.steps[0].retry.timeout}'; echo
```

| Field | Expected | Pre-#7150 |
|---|---|---|
| Warehouse `spec.interval` | `5m` | `5m0s` |
| Stage `requiredSoakTime` | `2h` | `2h0m0s` |
| Step `retry.timeout` | `1h` | `1h0m0s` |

## Troubleshooting

- **A value reads back in canonical form** — confirm the webhook that
  served the request is the build under test:
  `kubectl -n kargo get deploy kargo-webhooks-server -o jsonpath='{.spec.template.spec.containers[0].image}'`.
  A stale webhooks server from an earlier install will still rewrite.
- **`uat` is rejected on apply** — `requiredSoakTime` is only valid on a
  freight request that names upstream Stages, which is why it sits on `uat`
  and not `test`. Don't move it.
