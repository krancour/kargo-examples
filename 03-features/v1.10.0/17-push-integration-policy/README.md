# 17 — `RebaseOrMerge` push integration: both outcomes in one project

## What this validates

PR [akuity/kargo#5904](https://github.com/akuity/kargo/pull/5904) introduced
the operator-selectable strategy Kargo's controller uses to integrate
divergent remote commits into the local work tree before pushing, and
PR [akuity/kargo#7319](https://github.com/akuity/kargo/pull/7319) (commit
`c0b6dd467` on `release-1.12`) made `RebaseOrMerge` the default in v1.12.0:

```yaml
controller:
  gitClient:
    pushIntegrationPolicy: RebaseOrMerge  # default since 1.12 (was AlwaysRebase in 1.10 and 1.11)
```

Under `RebaseOrMerge`, `git-push` rebases when every local commit it would
have to replay is safe to rewrite, and falls back to a merge commit
otherwise. "Safe" comes from a signature-trust check on each commit to
replay, done with `git log --format=%G?` inside the pushing work tree:

| Commit to replay | Signing configured in the work tree | Decision |
|---|---|---|
| Signed by the work tree's own key | yes | rebase (Kargo re-signs) |
| Signed by the work tree's own key | no | merge (would strip the signature) |
| Signed by any other key | either | merge (Kargo can't vouch for it) |
| Unsigned | yes | merge (would fabricate a signature) |
| Unsigned | no | rebase |

This example exercises **both** outcomes under the default policy, with no
chart changes and no scripts. Divergence is manufactured inside each
Promotion: a second clone of the target branch, under an unsigned
`DivergentCommitter` identity, commits and pushes *before* Kargo's own work
tree pushes.

- **`rebase` Stage** — Kargo's work tree uses the cluster default identity
  from `00-common` (signed by "Kargo Test Key"). Its only commit to replay
  is its own: rebase.
- **`merge` Stage** — Kargo's work tree is cloned from a staging branch that
  a third work tree, signing as Tony Stark with a different key, built on
  top of the target branch. The cluster-default work tree cannot verify
  Tony's signature, so that commit is untrusted: merge.

The other two policies (`RebaseOrFail`, `AlwaysMerge`) and the old default
(`AlwaysRebase`) are chart-level and out of scope here.

## Prerequisites

- A running Kargo control plane on the chart default policy (or with
  `controller.gitClient.pushIntegrationPolicy=RebaseOrMerge` set).
- The shared `github` Secret and the ClusterConfig `gitClient` block with
  its `gpg-signing-key` from `00-common/kargo.yaml`. Together these give
  every work tree without an explicit `author` a signed identity.
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops).
  Branches `31/stage/rebase`, `31/stage/merge` and
  `31/stage/merge-staging` are created automatically.
- Replace every `<github-username>` in `kargo.yaml` (see SETUP.md).
- No Argo CD.

The Tony Stark GPG key in `kargo.yaml` is the same disposable test key as
in `03-gpg/`. It is not sensitive and is trusted by no one.

## Apply

```bash
kubectl apply -f 00-common/kargo.yaml   # once per cluster
kubectl apply -f 03-features/v1.10.0/17-push-integration-policy/kargo.yaml
```

## Trigger

Both Stages auto-promote. To force discovery:

```bash
kubectl -n kargo-demo-31 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

Both Promotions **succeed**. Each records the three commits involved in
its `report` output:

```bash
kubectl -n kargo-demo-31 get promotions \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,HEAD:.status.state.report.head
```

Then read the branch heads on the fork (`R=repos/<github-username>/kargo-demo-gitops`):

1. **`31/stage/rebase`** — `gh api $R/commits/<head> --jq '.parents|length'`
   is **1**, and that parent is the `DivergentCommitter` commit. The head is
   Kargo's commit, re-signed: its SHA differs from
   `report.kargoCommitBeforePush`, its author is "Kargo Test Key" and
   `.commit.verification.signature` is present. Linear history.
2. **`31/stage/merge`** — the head has **2** parents: the
   `DivergentCommitter` commit and Kargo's commit exactly as it was before
   the push (`report.kargoCommitBeforePush`, unchanged SHA). Kargo's
   commit's parent is Tony's commit (`report.tonyCommit`), author "Tony
   Stark", signature present and untouched.
3. The controller log says which way each push went:

   ```bash
   kubectl -n kargo logs deploy/kargo-controller | grep 'integrating remote changes'
   ```

   `via rebase` for the `rebase` Stage, `via merge (rebase unsafe)` for the
   `merge` Stage. (Trace level: set `controller.logLevel=TRACE` to see it.)

## Troubleshooting

- **The `merge` Stage rebased** — Kargo's work tree could verify Tony's
  signature, which means the cluster default signing key and the Tony key
  are the same. Check `00-common/kargo.yaml`'s `gpg-signing-key` is not the
  Tony key from `03-gpg/`.
- **The `rebase` Stage merged** — Kargo's own commit wasn't trusted in its
  own work tree, which means the imported signing key isn't at ultimate
  trust in that keyring. Look at the controller log for `rebase unsafe`.
- **`git-push` from `./other` fails with a non-fast-forward** — a previous
  run's Promotion is still in flight on the same branch. Wait for it.
- **`error creating new branch`** on the first run — the fork is not
  writable by the GitHub App in the `github` Secret.
