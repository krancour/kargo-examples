# 04 — `github-push` step (server-signed commits)

## What this validates

PR [akuity/kargo#6055](https://github.com/akuity/kargo/pull/6055) — the new
`github-push` promotion step.

`github-push` is a drop-in replacement for `git-push` when the remote is
GitHub. Instead of pushing over HTTPS, it pushes via the GitHub REST API on
behalf of the configured GitHub App. The resulting commits are signed
*server-side* by GitHub and show up with a `Verified` badge — no GPG
configuration required, and you get to skip the whole "rebase loses my
signature" problem entirely.

## Prerequisites

- A running Kargo control plane (Tilt dev stack:
  `make hack-tilt-up`).
- The shared `github` Secret in `kargo-shared-resources` (already in
  `00-common/kargo.yaml`) configured with a GitHub App that has
  `Contents: Read & write` on your `kargo-demo-gitops` fork.
  - `00-common/kargo.yaml` ships an example App scoped to
    `^https://github.com/<github-username>/.*`. **Replace with your own App** if you
    forked the demo repo to a different account.
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops)
  on the same account the App is installed against.
  - The `kustomize` branch must exist (it's the source-of-truth branch the
    Warehouse subscribes to).
  - Branch `18/stage/test` will be created automatically by the first
    promotion.
- An Argo CD installation (`argocd` namespace), reachable from the cluster.
- Replace every `<github-username>` placeholder in `argocd.yaml` and
  `kargo.yaml` with your fork's account name.

## Setup

```bash
# 1) Bring up the dev cluster (skip if already running).
make hack-tilt-up

# 2) Apply common cluster-level setup once per cluster.
kubectl apply -f 00-common/kargo.yaml
```

## Apply

```bash
kubectl apply -f 03-features/04-github-push/argocd.yaml
kubectl apply -f 03-features/04-github-push/kargo.yaml
```

## Trigger

A promotion to `test` should auto-fire as soon as the Warehouse discovers
the initial Freight (the head of `kustomize` paired with the latest
permitted `nginx` tag). If it doesn't, force discovery:

```bash
kubectl -n kargo-demo-18 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. Branch `18/stage/test` appears on your fork.
2. Each commit pushed to it shows a green **Verified** badge in the
   GitHub UI, with the signer attributed to the GitHub App (typically
   `<your-app>[bot]`).
3. The `Promotion` resource shows `phase: Succeeded` and the `push` step
   output contains `commit`, `branch`, and `commitURL`.
4. The Argo CD `Application` syncs to the new revision.

## Troubleshooting

- **`step failed: ... 403 Resource not accessible by integration`** — the
  GitHub App lacks `Contents: Read & write` on the target repo, OR the App
  isn't installed on it. Check the GitHub App settings.
- **`step failed: github: 422 Reference does not exist`** — the source
  branch hasn't been pushed to the staging ref yet; usually transient on
  first run, retries automatically (see the `maxAttempts` field — default
  10).
- **Commit shows up but not as Verified** — you accidentally configured
  `signingKey` on `git-clone.author`. Remove it; GitHub does the signing.
- **`Permission denied (publickey)` or HTTPS auth errors** — the credential
  regex on the `github` Secret doesn't match the `repoURL`. Adjust the
  Secret's `repoURL` regex (and `repoURLIsRegex: "true"`) to cover your
  fork's URL.
