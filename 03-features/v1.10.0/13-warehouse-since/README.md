# 13 — Warehouse `since` date-bounded discovery

## What this validates

PR [akuity/kargo#5992](https://github.com/akuity/kargo/pull/5992) — the new
`since` field on git Warehouse subscriptions. It bounds commit discovery
to commits at or after the supplied RFC 3339 date. Discovery walks history
newest-to-oldest and stops at the first commit older than the cutoff.

This only affects the `NewestFromBranch` commit selection strategy (the
one that walks history); `SemVer`, `Lexical`, and `NewestTag` short-circuit
on tag matches and don't traverse commits.

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops).
- The `kustomize` branch on your fork must contain at least one commit
  newer than the `since:` date in `kargo.yaml` (currently
  `2026-03-01T00:00:00Z` — adjust if your fork's history differs).
- Read access to the repo. If your fork is private, the shared `github`
  Secret in `00-common/kargo.yaml` provides this.
- Replace `<github-username>` in `kargo.yaml`.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/13-warehouse-since/kargo.yaml
```

## Trigger

Discovery happens on Warehouse reconciliation. Force it:

```bash
kubectl -n kargo-demo-27 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

```bash
kubectl -n kargo-demo-27 get warehouse kargo-demo -o yaml \
  | yq '.status.discoveredArtifacts.git[0].commits[].author.when'
```

(or use `kubectl get … -o jsonpath`):

- All listed commit timestamps are `>= 2026-03-01T00:00:00Z`.
- The list is shorter than what you'd get without the cutoff (compare by
  removing the `since:` line, re-applying, and re-checking).

The corresponding `Freight` resources reference only those bounded commits.

## Toggling behavior

To prove the cutoff is what's bounding the list, edit `kargo.yaml`:

- Loosen: change to `since: "2024-01-01T00:00:00Z"` → many more commits
  appear.
- Tighten: change to `since: "2099-01-01T00:00:00Z"` → discovery returns
  zero commits, no new Freight is produced (the Warehouse status reports
  the empty result).

Re-apply each time and re-trigger discovery.

## Troubleshooting

- **Schema validation rejects `since:` field** — you're on a Kargo
  version older than 1.10.
- **`since` set but discovery still returns ancient commits** — the
  Warehouse uses a different `commitSelectionStrategy` (e.g. `SemVer`).
  `since` only takes effect with `NewestFromBranch` (the default when
  `branch:` is set). Other strategies don't walk commit history.
- **Empty discovery despite a recent cutoff** — the branch genuinely has
  no commits newer than the cutoff; check `git log --since=...`.
