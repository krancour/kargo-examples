# 03 — `git-merge-pr` deletes its source branch

## What this validates

PR [akuity/kargo#7271](https://github.com/akuity/kargo/pull/7271) — the new
`deleteSourceBranch` option on the `git-merge-pr` step. Pipelines that chain
`git-open-pr` and `git-merge-pr` push to a generated
`kargo/promotion/<promotion-name>` branch on every promotion, and until now
nothing cleaned those up. GitHub's repository-level "Automatically delete
head branches" setting does not fire for merges performed with a GitHub App
installation token, which is how Kargo authenticates with App credentials,
so the branches lingered even with it enabled.

With `deleteSourceBranch: true`, the step deletes the PR's head branch
after a successful merge. A branch that is already gone counts as success.
A deletion failure is logged and surfaced in the step result's message but
does **not** fail the step.

## Prerequisites

- A running Kargo control plane.
- The shared `github` Secret in `kargo-shared-resources` (from
  `00-common/kargo.yaml`) granting the configured GitHub App
  `Contents: Read & write` and `Pull requests: Read & write` on your fork.
  Branch deletion needs `Contents: Read & write`.
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops):
  - The `kustomize` branch must exist.
  - `37/stage/test` is created automatically.
- Replace every `<github-username>` in `kargo.yaml` (see SETUP.md for the
  substitution pipe).
- No Argo CD Application is involved.

## Apply

```bash
kubectl apply -f 00-common/kargo.yaml   # once per cluster
kubectl apply -f 03-features/v1.12.0/03-merge-pr-delete-source-branch/kargo.yaml
```

## Trigger

`test` auto-promotes. To force discovery:

```bash
kubectl -n kargo-demo-37 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. The Promotion succeeds. A PR opened from a `kargo/promotion/<name>`
   branch against `37/stage/test` and was merged.
2. The source branch no longer exists on the fork. Read its name from the
   Promotion's recorded step output and ask GitHub:

   ```bash
   PROMO=$(kubectl -n kargo-demo-37 get promotions \
     -o jsonpath='{.items[-1:].metadata.name}')
   BRANCH=$(kubectl -n kargo-demo-37 get promotion "${PROMO}" \
     -o jsonpath='{.status.state.push.branch}')
   echo "${BRANCH}"
   gh api "repos/<github-username>/kargo-demo-gitops/branches/${BRANCH}"
   ```

   The last command fails with `HTTP 404: Branch not found`.
3. The merge itself is intact: `37/stage/test` on the fork has a new
   commit whose SHA matches `.status.state['merge-pr'].commit`, and the
   PR shows as **Merged**.
4. Contrast: every earlier PR-flow example in this repo (for instance
   `03-features/v1.10.0/11-git-merge-squash`) leaves its
   `kargo/promotion/*` branch behind. Listing branches on the fork shows
   those survivors alongside the absence of this example's.

## Troubleshooting

- **The branch still exists but the Promotion succeeded** — by design a
  deletion failure does not fail the step. Look at the `git-merge-pr` step's
  message in the Promotion status
  (`kubectl -n kargo-demo-37 get promotion "${PROMO}" -o jsonpath='{.status.stepExecutionMetadata}' | jq`).
  The usual cause is a token without `Contents: Read & write`, or a branch
  protection rule covering `kargo/promotion/*`.
- **`git-open-pr` fails with a 404** — the GitHub App is not installed on
  the fork, or the `github` Secret's `repoURL` pattern does not match it.
- **The Promotion stalls in `git-merge-pr`** — `wait: true` keeps the step
  running until the PR is mergeable. A required status check on
  `37/stage/test` will hold it indefinitely.
