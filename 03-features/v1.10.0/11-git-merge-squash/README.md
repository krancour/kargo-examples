# 11 — `git-merge-pr` with `mergeMethod: squash`

## What this validates

PR [akuity/kargo#5581](https://github.com/akuity/kargo/pull/5581) — the new
`mergeMethod` field on the `git-merge-pr` step. Previously the step always
used the provider's default merge style (`merge` for GitHub). Now you can
choose `squash`, `rebase`, or `merge` (provider-specific values).

The single stage in this example deliberately produces **two** commits on
the source branch (`kargo/promotion/<name>`) before opening a PR — first
rendering the manifests with a placeholder image tag, then bumping to the
real freight tag. Squash-merging the PR collapses both into a single
commit on `25/stage/test`. Without that two-commit setup, squash would
look identical to `merge` or `rebase` (collapsing one commit is a no-op).

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- The shared `github` Secret in `kargo-shared-resources` (already in
  `00-common/kargo.yaml`) granting the configured GitHub App `Contents:
  Read & write` AND `Pull requests: Read & write` on your fork.
- Repo settings on your fork: **Settings → General → Pull Requests →
  "Allow squash merging"** must be enabled (default for new GitHub repos).
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops):
  - `kustomize` branch must exist.
  - `25/stage/test` is auto-created.
- An Argo CD installation in the `argocd` namespace.
- Replace every `<github-username>` in `argocd.yaml` and `kargo.yaml`.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/11-git-merge-squash/argocd.yaml
kubectl apply -f 03-features/11-git-merge-squash/kargo.yaml
```

## Trigger

`test` auto-promotes. To force discovery:

```bash
kubectl -n kargo-demo-25 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. A pull request opens against `25/stage/test` from a generated branch
   like `kargo/promotion/<promotion-name>`.
2. The PR's **Commits** tab shows **two** commits:
   - `1/2: Stage manifests with placeholder image tag` — rendered
     manifests with `image: ...:pending`.
   - `2/2: Updated image to ...` — the diff is just the changed `image:`
     line in `manifests.yaml`.
3. The `git-merge-pr` step squash-merges the PR. On GitHub the PR is
   marked **Squashed and merged** (purple icon) rather than **Merged**.
4. `git log --oneline 25/stage/test` on your fork shows **exactly one
   new commit per promotion** — the squashed one — whose default message
   GitHub auto-builds from the PR title plus the two source commit
   subjects. The intermediate `:pending` state is gone from history.
5. Contrast: switch `mergeMethod: squash` → `mergeMethod: merge` and
   re-run; the next promotion adds **three** commits to `25/stage/test`
   (the two source commits + a merge commit). With `mergeMethod: rebase`,
   you'd get **two** (replayed, no merge commit).
6. `outputs['merge-pr'].commit` is the SHA of the new commit on
   `25/stage/test`, used to drive `argocd-update`.

## Troubleshooting

- **`git-merge-pr` step fails: `Squash merges are not allowed on this
  repository`** — enable squash merging on your fork's repo settings.
- **`mergeMethod: foo` rejected** — the value must be one of the
  provider-supported strings. For GitHub: `merge`, `squash`, `rebase`.
  Other providers accept different values; consult the provider docs.
- **Promotion ends in `Failed` because the PR isn't mergeable yet** —
  if `wait: true` is set (it is in this example), the step stays in
  `RUNNING` until the PR becomes mergeable. If `wait: false`, an
  unmergeable PR causes immediate failure. Common cause: a required
  status check on the target branch.
