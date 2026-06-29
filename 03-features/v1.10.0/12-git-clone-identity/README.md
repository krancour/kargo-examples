# 12 — Consolidated identity & signing on `git-clone.author`

## What this validates

PR [akuity/kargo#6058](https://github.com/akuity/kargo/pull/6058) — git
authorship and GPG signing config are now consolidated on
`git-clone.author`. The same fields on `git-commit.author`,
`git-tag.author`, and `git-push.committer` are deprecated in 1.10 and
scheduled for removal in v1.12.0.

This example is the side-by-side counterpart to the existing
`03-features/03-gpg/`. The pipeline is mechanically identical (clone →
kustomize → commit → push), but the same identity / signing key that 03-gpg
wired into `git-commit.author.signingKey` (and re-stated for every commit
step) lives once on `git-clone.author` here. It's also the recommended fix
for [akuity/kargo#5857](https://github.com/akuity/kargo/issues/5857) —
"git-commit with custom author fails with Author identity unknown" — which
was the failure mode the consolidation effectively eliminates.

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- The shared `github` Secret in `kargo-shared-resources` (already in
  `00-common/kargo.yaml`) granting Kargo write access to your fork.
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops):
  - `kustomize` branch must exist.
  - `26/stage/test` is auto-created.
- An Argo CD installation in the `argocd` namespace.
- Replace every `<github-username>` in `argocd.yaml` and `kargo.yaml`.

The Tony Stark GPG key in `kargo.yaml` is the same disposable test key as
in `03-features/03-gpg/`. It is not sensitive and is not trusted by anyone.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/12-git-clone-identity/argocd.yaml
kubectl apply -f 03-features/12-git-clone-identity/kargo.yaml
```

## Trigger

`test` auto-promotes. To force discovery:

```bash
kubectl -n kargo-demo-26 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. Branch `26/stage/test` accumulates signed commits.
2. `git log --show-signature 26/stage/test` (after `git fetch origin`)
   shows each commit signed with the Tony Stark key:
   ```
   gpg: Good signature from "Tony Stark <tony@starkindustries.com>"
   ```
3. The committer/author on each commit is `Tony Stark
   <tony@starkindustries.com>` even though `git-commit` carries no
   `author` block.
4. Compare `git diff -U0
   03-features/03-gpg/kargo.yaml 03-features/12-git-clone-identity/kargo.yaml`:
   the deprecated `author` block on `git-commit` is gone.

## Troubleshooting

- **Commit shows up but not signed** — the `gpg-signing-key` Secret is
  missing or has the key under a different field name. The lookup is
  `secret('gpg-signing-key').signingKey`.
- **`gpg: Bad signature`** — the `name` and `email` on `git-clone.author`
  must match a UID embedded in the GPG key. Use `gpg --list-packets` on
  the private key block to verify the UID is `Tony Stark
  <tony@starkindustries.com>`.
- **`Author identity unknown`** — the system-level git defaults aren't
  configured AND `git-clone.author` is missing. Either rely on the
  cluster default (set via the Helm chart's `controller.gitClient.name`
  / `.email`) or supply `git-clone.author` as in this example.
- **Deprecation warning logs about `git-commit.author`** — that's the
  intended signal if you accidentally also set `author` on `git-commit`;
  remove it.
