# 08 — `fail` step (and Failed-status preservation)

## What this validates

- PR [akuity/kargo#5918](https://github.com/akuity/kargo/pull/5918) — the
  new `fail` promotion step. Lets a pipeline explicitly mark itself as
  `Failed` with a custom message, typically gated by an `if` expression
  used as a guard rail.
- PR [akuity/kargo#5941](https://github.com/akuity/kargo/pull/5941) —
  prerequisite fix that ensures the `Failed` status returned by a step is
  preserved by the engine and surfaced on the `Promotion` resource, rather
  than being overwritten to `Succeeded`.

The example deliberately demonstrates BOTH outcomes:

- **`test` stage** uses `fail` behind an `if` that does not match any
  current nginx tag → the step is skipped, the promotion succeeds.
- **`prod` stage** uses `fail` unconditionally → every promotion ends in
  `Failed` with the configured message, providing a clear "manual approval
  required" gate.

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- Outbound HTTPS to `public.ecr.aws` for image discovery.
- No Argo CD setup, no Git credentials, no GPG, no fork required — this
  example is purely about controller-side step semantics.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/08-fail-step/kargo.yaml
```

## Trigger

Both stages auto-promote. To force discovery:

```bash
kubectl -n kargo-demo-22 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

```bash
kubectl -n kargo-demo-22 get promotions
```

You should see (at least) two promotions:

- One targeting Stage `test` with `PHASE=Succeeded`. Inspect its
  `.status.steps[].status` for the `fail` step — it will be `Skipped`.
- One targeting Stage `prod` with `PHASE=Failed`. Inspect:
  ```bash
  kubectl -n kargo-demo-22 get promotion <prod-promotion> -o yaml
  ```
  - `.status.phase: Failed`
  - The `fail` step entry under `.status.steps[]` has `status: Failed`
    and a `message:` containing
    `Manual approval required for prod promotion of <freight>`.

The same statuses should be reflected in the dashboard UI: `prod`
promotions show a red icon and the failure message in the step detail.

## Toggling behavior

To make the `test` stage fail, edit the manifest in-place to:

```yaml
constraint: ^1.27.0-rc.0  # allow pre-releases through
strictSemvers: false
```

…and adjust the `if` to match a known pre-release tag. Reapply and a
fresh `test` promotion should now end in `Failed` with the pre-release
message.

## Troubleshooting

- **`prod` promotion shows `Succeeded` despite the unconditional `fail`** —
  you are on a Kargo version older than 1.10 (i.e., before #5941). Upgrade.
- **`fail` step's `if` never evaluates true even on a pre-release tag** —
  expression syntax: `matches` is the regex operator (string-side first,
  pattern second). `==` would be exact equality.
- **`prod` promotion does not auto-fire** — `prod` only auto-promotes
  Freight already verified in `test`. If `test` failed for some unrelated
  reason, no Freight is verified and `prod` stays idle.
