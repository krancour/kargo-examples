# 07 — `toml-update` step (and `toml-parse`)

## What this validates

PR [akuity/kargo#5996](https://github.com/akuity/kargo/pull/5996) — the new
`toml-update` and `toml-parse` promotion steps. They are TOML-shaped
counterparts to the existing `yaml-update` / `yaml-parse` and `json-update`
/ `json-parse` steps. Useful for `Cargo.toml`, `pyproject.toml`,
`netlify.toml`, etc.

This example exercises:

- Updating a **nested key** (`image.tag`, `package.version`).
- Updating a key whose name **contains a literal dot** — the
  Kubernetes-style label `example.com/version` — using the backslash
  escape required by sjson path syntax.

`toml-parse` is not exercised in the manifest but its usage is mirror-image
of `toml-update` (give it `outputs:` with `name` + `fromExpression`); see
the docs for examples.

## Prerequisites

- A running Kargo control plane (Tilt: `make hack-tilt-up`).
- The shared `github` Secret in `kargo-shared-resources` (already in
  `00-common/kargo.yaml`) granting Kargo write access to your fork.
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops)
  on the account the `github` Secret is configured for.
- **A new `toml` branch on your fork** containing a single file at
  `configs/settings.toml`. Create it locally and push:

  ```bash
  git clone https://github.com/<github-username>/kargo-demo-gitops.git
  cd kargo-demo-gitops
  git checkout --orphan toml
  git rm -rf .
  mkdir -p configs
  cat > configs/settings.toml <<'EOF'
  [package]
  name = "kargo-demo-21"
  version = "0.0.0"

  [image]
  repo = "public.ecr.aws/nginx/nginx"
  tag = "0.0.0"

  [labels]
  "example.com/version" = "0.0.0"
  EOF
  git add configs/settings.toml
  git commit -m "Seed configs/settings.toml for kargo-demo-21"
  git push origin toml
  ```

- Replace `<github-username>` in `kargo.yaml` with your fork's account.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

## Apply

```bash
kubectl apply -f 03-features/07-toml-update/kargo.yaml
```

This example does **not** ship an `argocd.yaml` — there are no
`Application` resources to deploy; the validation is purely about the file
on the destination branch.

## Trigger

`test` auto-promotes. To force discovery:

```bash
kubectl -n kargo-demo-21 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

After a promotion to `test`, the branch `21/stage/test` on your fork
contains a `configs/settings.toml` whose:

- `[image]` table has `tag = "<discovered nginx tag>"` (e.g.
  `tag = "1.29.2"`).
- `[package]` table has the same string in `version`.
- `[labels]` table's `"example.com/version"` quoted key has the same
  string.

Crucially, formatting (whitespace, comments, key order) elsewhere in the
file is preserved — `toml-update` is an in-place edit, not a re-render.

## Troubleshooting

- **`step failed: file not found: configs/settings.toml`** — the `toml`
  branch on your fork is missing or the file path differs. Re-run the
  `Prerequisites` setup.
- **`step failed: key labels.example.com/version not found`** — you didn't
  escape the literal dot. The path syntax requires
  `labels.example\.com/version`. (TOML itself accepts `"example.com/version"`
  as a quoted key, but in the *update path* you have to escape the dot to
  prevent it from being treated as a navigation separator.)
- **Step succeeds but value isn't a scalar** — `toml-update` only writes
  scalars (string, number, boolean). Tables and arrays must be edited at
  the leaf.
