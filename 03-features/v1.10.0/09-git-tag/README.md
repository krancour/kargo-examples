# 09 — `git-tag` step + `git-push` tag option

## What this validates

PR [akuity/kargo#5785](https://github.com/akuity/kargo/pull/5785) — both:

- The new `git-tag` promotion step, which creates an annotated tag on the
  local working tree.
- The new `tag` field on the existing `git-push` step, which pushes a
  named tag to the remote.

The single stage in this example creates and pushes a release tag of the
form `v<image-tag>-<promotion-name>` whenever Freight is promoted.

The schema enforces a tight `oneOf` on `git-push`: a single call may push
exactly one of `targetBranch`, `generateTargetBranch`, or `tag`. So the
pipeline calls `git-push` twice — once for the branch, once for the tag.

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- The shared `github` Secret in `kargo-shared-resources` (already in
  `00-common/kargo.yaml`) granting Kargo write access to your fork
  (Contents: Read & write — required for tag pushes too).
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops):
  - `kustomize` branch must exist.
  - `23/stage/test` will be auto-created.
- An Argo CD installation in the `argocd` namespace.
- Replace every `<github-username>` in `argocd.yaml` and `kargo.yaml`.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/09-git-tag/argocd.yaml
kubectl apply -f 03-features/09-git-tag/kargo.yaml
```

## Trigger

`test` auto-promotes. To force discovery:

```bash
kubectl -n kargo-demo-23 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

After a successful promotion, the GitHub UI for your fork shows a new tag
under **Tags**, named like `v1.29.2-test.01HXY...`. Locally:

```bash
git fetch --tags origin
git tag --list 'v*' --format='%(refname:short) %(contents:subject)'
```

…lists the new tag. The annotation message is the message rendered by
the `git-tag` step (in this example: `"Release 1.29.2 promoted to test
by <promotion>."`).

The Promotion resource's step outputs include:

- `push-branch.commit` and `push-branch.branch` — the branch push.
- `tag.commit` — the SHA the tag references.
- `push-tag` has no significant outputs beyond status.

## Troubleshooting

- **`git-push` step rejected with a schema error** — you almost certainly
  set more than one of `targetBranch`, `generateTargetBranch`, or `tag`
  on the same call. Split into two `git-push` steps.
- **Tag push fails with `403`** — the GitHub App lacks `Contents: Read &
  write`, which is the same permission as commit pushes.
- **Annotation message is empty in the UI** — the `message` field on
  `git-tag` is required (the schema enforces `minLength: 1`); confirm
  it's not just whitespace.
- **`git-tag` succeeds but `git-push` says "tag does not exist"** — make
  sure the second `git-push` runs in the SAME working tree (`path:` value)
  as the `git-tag` call. Tags live on the local clone until pushed.
