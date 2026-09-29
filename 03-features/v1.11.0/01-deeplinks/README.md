# 01 — Deep links (project-level + promotion step output)

## What this validates

PRs [akuity/kargo#6271](https://github.com/akuity/kargo/pull/6271) and
[akuity/kargo#6223](https://github.com/akuity/kargo/pull/6223) — configurable
deep links, in two distinct flavors:

1. **Resource-level links** (`#6271`): `ProjectConfig` (and, identically,
   `ClusterConfig`) gain `stageLinks` and `freightLinks` — lists of
   `{title, url, description, if}` entries. The UI shows them when viewing a
   Stage or piece of Freight, and they're served by the
   `.../stages/<stage>/links` and `.../freight/<name-or-alias>/links` API
   endpoints. `url` is a Go template (sprig included) evaluated against
   `{{ .stage }}` / `{{ .freight }}`; `if` is an expr-lang condition over the
   same context that hides the link when false.
2. **Promotion step output links** (`#6223`): any step may emit a `links`
   array (`{url, label?, icon?, tooltip?}`) in its output, and the UI renders
   them inline on the step and promotion views. This example emits them with
   `compose-output`.

## Prerequisites

- A running Kargo control plane (Tilt dev stack: `make hack-tilt-up`).
- Nothing else — no fork, no Argo CD Application, no credentials.

## Apply

```bash
kubectl apply -f 03-features/v1.11.0/01-deeplinks/kargo.yaml
```

## Trigger

Auto-promotion to `test` fires as soon as the Warehouse discovers Freight.
To force discovery:

```bash
kubectl -n kargo-demo-33 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. In the UI, the `test` Stage shows a **Grafana dashboard** link with the
   project and stage names substituted into the URL. The **Production
   runbook** link is absent.
2. Label the Stage and the conditional link appears (refresh the view):

   ```bash
   kubectl -n kargo-demo-33 label stage test tier=prod
   ```

   Remove it with `kubectl -n kargo-demo-33 label stage test tier-` and the
   link disappears again.
3. Any piece of Freight shows an **Image in ECR Gallery** link whose URL ends
   with that Freight's actual image tag.
4. The completed promotion's `compose-output` step shows two rendered links
   (**Promoted image**, **Dashboard**); the promotion view surfaces them too.
5. The same resolved links are available from the API, e.g.:

   ```bash
   # $KARGO_TOKEN: see "Getting an API token" in SETUP.md
   curl -s -H "Authorization: Bearer ${KARGO_TOKEN}" \
     http://localhost:30081/v1beta1/projects/kargo-demo-33/stages/test/links | jq
   ```

   Expect a `links` array with resolved URLs (and an `errors` array that is
   absent or empty).

## Troubleshooting

- **A link is missing** — check the `errors` array in the links API
  response: template and condition failures are collected there per-link
  rather than failing the request. The usual culprit is mixing up the two
  languages: `url` is a **Go template** (`{{ .stage.metadata.name }}`),
  while `if` is **expr-lang** (`stage.metadata.labels.tier == "prod"`, no
  braces, no leading dot).
- **The conditional link never appears** — the `if` expression guards
  against `nil` labels; make sure the label really landed
  (`kubectl -n kargo-demo-33 get stage test -o jsonpath='{.metadata.labels}'`).
- **Step links don't render** — `url` must be an absolute, valid URL;
  entries failing validation are silently dropped by the UI.
