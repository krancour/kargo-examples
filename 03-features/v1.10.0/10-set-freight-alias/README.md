# 10 — `set-freight-alias` step

## What this validates

PR [akuity/kargo#5516](https://github.com/akuity/kargo/pull/5516) — the new
`set-freight-alias` promotion step. Replaces the random
adjective-noun-animal alias Kargo assigns each new Freight with something
meaningful (here: `nginx-<discovered-tag>`).

Aliases must be unique within a Project. The example deliberately surfaces
that constraint in the `Troubleshooting` section.

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- Outbound HTTPS to `public.ecr.aws` for image discovery.
- No Argo CD, no Git credentials, no GPG, no fork. Single-stage
  controller-only validation.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/10-set-freight-alias/kargo.yaml
```

## Trigger

The single `test` stage auto-promotes. To force discovery:

```bash
kubectl -n kargo-demo-24 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

```bash
kubectl -n kargo-demo-24 get freight \
  -o custom-columns=NAME:.metadata.name,ALIAS:.alias,IMAGES:.images[*].tag
```

Each Freight resource shows an alias of the form `nginx-1.29.2` instead
of the default `<adjective>-<animal>` style. The same alias appears in the
dashboard freight timeline tooltip.

In the dashboard you can now reference Freight by its alias in the URL,
e.g. `…/project/kargo-demo-24/stage/test/freight/nginx-1.29.2`.

## Troubleshooting

- **Step fails with `alias already in use`** — uniqueness is enforced
  per-project. If the same image tag is discovered twice (e.g. after
  manually deleting the previous Freight then re-discovering), the second
  promotion's `set-freight-alias` will fail. Make the alias more specific:

  ```yaml
  alias: nginx-${{ imageFrom(vars.imageRepo).Tag }}-${{ ctx.targetFreight.name }}
  ```

  …and re-apply.
- **Step fails with `freight not found`** — `name:` must be the Kubernetes
  name of the Freight, not the alias. Use `${{ ctx.targetFreight.name }}`.
- **Alias didn't change in the UI** — the dashboard caches; refresh.
