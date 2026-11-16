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
- Outbound HTTPS to github.com. The Warehouse subscribes to the `main`
  branch of the public [akuity/kargo](https://github.com/akuity/kargo)
  repo, so no fork and no credentials are needed.

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
  | yq '.status.discoveredArtifacts.git[0].commits[].creatorDate'
```

All listed commit timestamps are at or after the `since:` date in
`kargo.yaml`. The corresponding `Freight` resources reference only those
commits.

`main` moves quickly, so with the committed `since:` date the list may hit
the subscription's `discoveryLimit` (100) before it reaches the cutoff. In
that case the limit, not `since`, is what bounds it. The toggles below show
`since` doing the work.

## Toggling behavior

To prove the cutoff is what's bounding the list, patch the live Warehouse
and re-trigger discovery each time:

```bash
kubectl -n kargo-demo-27 patch warehouse kargo-demo --type=json \
  -p '[{"op":"replace","path":"/spec/subscriptions/0/git/since","value":"<date>"}]'
```

- Recent: a date a few days back → fewer than 100 commits, all at or after
  the cutoff.
- Tighten: `2099-01-01T00:00:00Z` → discovery returns zero commits, the
  `Healthy` condition reports `No commits discovered`, and no new Freight
  is produced.

## Troubleshooting

- **Schema validation rejects `since:` field** — you're on a Kargo
  version older than 1.10.
- **`since` set but discovery still returns ancient commits** — the
  Warehouse uses a different `commitSelectionStrategy` (e.g. `SemVer`).
  `since` only takes effect with `NewestFromBranch` (the default when
  `branch:` is set). Other strategies don't walk commit history.
- **Empty discovery despite a recent cutoff** — the branch genuinely has
  no commits newer than the cutoff; check `git log --since=...`.
