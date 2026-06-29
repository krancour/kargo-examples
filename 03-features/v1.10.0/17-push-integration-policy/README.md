# 17 — Configurable `pushIntegrationPolicy` (rebase vs merge vs fail)

## What this validates

PR [akuity/kargo#5904](https://github.com/akuity/kargo/pull/5904) — the
operator-selectable strategy Kargo's controller uses to integrate
divergent remote commits into the local working tree before pushing.

This is **chart-level configuration**, not per-Project YAML. The Helm
chart value:

```yaml
controller:
  gitClient:
    pushIntegrationPolicy: AlwaysRebase  # default in 1.10
```

…controls the behavior. Valid values:

| Value | Behavior |
|-------|----------|
| `AlwaysRebase`   | Unconditionally rebase local commits onto the remote. Existing default in 1.10. Loses GPG signatures on rebased commits. |
| `RebaseOrMerge`  | Try to rebase; if rebase would discard a signature, fall back to a merge commit. **Default in v1.12.0.** |
| `RebaseOrFail`   | Try to rebase; if it can't preserve signatures, fail the promotion. |
| `AlwaysMerge`    | Skip rebase entirely; always create a merge commit when divergence exists. |

The example pipeline in `kargo.yaml` produces signed commits using the
ClusterConfig-default identity from `00-common/kargo.yaml`. The bundled
`validate.sh` script orchestrates the validation: it runs a baseline
promotion, deliberately introduces a divergent commit on the target
branch, then runs another promotion and shows you what happened.

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- The shared `github` Secret in `kargo-shared-resources` (already in
  `00-common/kargo.yaml`) granting Kargo write access to your fork.
- The shared `gpg-signing-key` Secret in `kargo-system-resources`
  (already in `00-common/kargo.yaml`) plus the corresponding ClusterConfig
  `gitClient` block — also already in `00-common/kargo.yaml`. Together
  these provide the cluster-default signed git identity.
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops)
  with the `kustomize` branch present.
- A local clone of your fork at `./kargo-demo-gitops` (used by
  `validate.sh` to push the divergent commit).
- `gh` CLI authenticated against your fork.
- An Argo CD installation in the `argocd` namespace.
- Replace `<github-username>` in `argocd.yaml` and `kargo.yaml`.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster

# Pick a policy and re-apply the chart with that value. From the kargo
# repo root:
helm upgrade kargo charts/kargo \
  -n kargo \
  --reuse-values \
  --set controller.gitClient.pushIntegrationPolicy=RebaseOrMerge
# Wait for the controller pod to roll:
kubectl -n kargo rollout status deploy/kargo-controller
```

For the Tilt dev stack specifically, `hack/tilt/values.dev.yaml` has the
relevant section commented; toggle it there and re-apply (Tilt will roll
the controller automatically).

## Apply

```bash
kubectl apply -f 03-features/17-push-integration-policy/argocd.yaml
kubectl apply -f 03-features/17-push-integration-policy/kargo.yaml
```

## Trigger / Validate

Run the helper script once for each policy you want to validate:

```bash
cd 03-features/17-push-integration-policy
./validate.sh <github-username> test
```

The script will:

1. Force-discover the Warehouse so a promotion fires.
2. Wait for it to settle (Succeeded baseline).
3. Push a divergent commit directly to `31/stage/test` on your fork (as
   `DivergentCommitter <divergent@example.com>`, NOT as Kargo).
4. Force-discover again so a second promotion fires that has to integrate
   the divergent commit before pushing.
5. Tell you where to look at the resulting Promotion to see whether
   Kargo rebased, merged, or failed.

## Expected outcome

Inspect `kubectl -n kargo-demo-31 get promotion <latest> -o yaml` after
the divergent-second-promotion:

| Policy in effect | Expected `.status.phase` | Shape of the new commit on `31/stage/test` |
|------------------|--------------------------|---------------------------------------------|
| `AlwaysRebase`   | `Failed`                 | No new Kargo commit; remote unchanged. The push step's error message mentions losing signature on rebase. |
| `RebaseOrMerge`  | `Succeeded`              | A merge commit with two parents (divergent + Kargo's), AND the original Kargo commit kept its signature. |
| `RebaseOrFail`   | `Failed`                 | No new commit; error message explicitly references the integration policy. |
| `AlwaysMerge`    | `Succeeded`              | A merge commit even when a clean rebase would have been possible. |

## Troubleshooting

- **`AlwaysRebase` succeeds despite signed commits** — the divergent
  commit was not present at push time (race against your validate.sh
  step ordering). Re-run; ensure the divergent push lands BEFORE the
  warehouse refresh.
- **Controller logs `unknown integration policy "..."`** — the chart
  value is misspelled; values are case-sensitive.
- **No new promotion fires after second refresh** — the warehouse may
  not see new artifacts (the divergent commit isn't on `kustomize` and
  no new image was published). The script's `kargo.akuity.io/refresh`
  annotation should still trigger a Stage reconcile; check Stage events.
- **Pipeline produces unsigned commits despite the cluster default** —
  the ClusterConfig in `00-common/kargo.yaml` was not applied or the
  `gpg-signing-key` Secret is missing in `kargo-system-resources`. Apply
  `00-common/kargo.yaml` first.
