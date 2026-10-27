# 18 — Webhook path filtering (`includePaths` honored on push events)

## What this validates

PR [akuity/kargo#5611](https://github.com/akuity/kargo/pull/5611) — webhook
receivers for providers that include changed-file lists in their push
payloads (GitHub, GitLab, Gitea) now honor the Warehouse's
`includePaths` / `excludePaths` filters when deciding whether to refresh
the Warehouse.

Behavior is **transparent** — there is no new field on the receiver or
Warehouse, just the existing `includePaths`. A receiver-driven refresh
that previously fired on every push to the watched branch now fires only
when the push touches files matching `includePaths` (or doesn't match
`excludePaths`).

This is unrelated to discovery-time path filtering (Kargo has always
honored `includePaths` when crawling commits during discovery). The new
behavior cuts unnecessary discovery passes triggered by webhooks for
no-op pushes.

Providers whose payloads do NOT include file lists (Azure, Bitbucket,
Docker Hub, Quay, Harbor, Artifactory, generic) keep their old behavior:
they always trigger refresh.

## Prerequisites

- A running Kargo control plane with the external webhooks server
  (`kargo-external-webhooks-server` in the `kargo` namespace).
- The cluster-level GitHub webhook receiver from `00-common/kargo.yaml`
  applied (it ships a `github-receiver` Secret and the
  `webhookReceivers[].github` block on ClusterConfig).
- A fork of [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops)
  with a `manifests` branch containing a `manifests/` directory (the
  Warehouse subscribes to it; the seed recipe is in the appendix).
- `curl`, `jq`, `openssl`. **No tunnel and no webhook on the fork**: the
  test plays GitHub itself.

## Apply

```bash
kubectl apply -f 00-common/kargo.yaml   # once per cluster
sed "s|<github-username>|$GH_USER|g" \
  03-features/v1.10.0/18-webhook-path-filtering/kargo.yaml | kubectl apply -f -
```

## Trigger

The receiver decides purely from the push payload: it matches the
Warehouse by `repository.clone_url`, the branch by `ref`, and the paths
by the union of `commits[].added/modified/removed` and `head_commit`'s
lists. So a hand-built push event, signed with the receiver's shared
secret exactly as GitHub signs, exercises the whole decision. Deliver four
of them through a port-forward:

```bash
NS=kargo-demo-32
SECRET=$(kubectl -n kargo-cluster-secrets get secret github-receiver \
  -o jsonpath='{.data.secret}' | base64 -d)
RPATH=$(kubectl get clusterconfig cluster -o json \
  | jq -r '.status.webhookReceivers[] | select(.name=="github") | .path')
kubectl -n kargo port-forward svc/kargo-external-webhooks-server 18443:443 &
sleep 2

payload() {  # payload <ref> <changed-file>
  jq -nc --arg ref "$1" --arg f "$2" --arg u "$GH_USER" '{
    ref: $ref,
    repository: {clone_url: ("https://github.com/" + $u + "/kargo-demo-gitops.git"),
                 html_url: ("https://github.com/" + $u + "/kargo-demo-gitops")},
    commits: [{id: "0000000000000000000000000000000000000002", added: [], modified: [$f], removed: []}],
    head_commit: {id: "0000000000000000000000000000000000000002", added: [], modified: [$f], removed: []}}'
}
deliver() {  # deliver <label> <ref> <changed-file> [bad]
  local body sig before after
  body=$(payload "$2" "$3")
  sig=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')
  [ "$4" = bad ] && sig=deadbeef
  before=$(kubectl -n $NS get warehouse kargo-demo -o jsonpath='{.metadata.annotations.kargo\.akuity\.io/refresh}')
  echo "== $1"
  curl -sk -w ' HTTP %{http_code}\n' -X POST "https://localhost:18443$RPATH" \
    -H 'Content-Type: application/json' -H 'X-GitHub-Event: push' \
    -H "X-Hub-Signature-256: sha256=$sig" --data "$body"
  sleep 2
  after=$(kubectl -n $NS get warehouse kargo-demo -o jsonpath='{.metadata.annotations.kargo\.akuity\.io/refresh}')
  echo "   refresh annotation: ${before:-<none>} -> ${after:-<none>}"
}

deliver "manifests/ touched on manifests branch" refs/heads/manifests manifests/configmap.yaml
deliver "README only on manifests branch"        refs/heads/manifests README.md
deliver "manifests/ touched on another branch"   refs/heads/main      manifests/configmap.yaml
deliver "bad signature"                          refs/heads/manifests manifests/configmap.yaml bad
kill %1; unset SECRET
```

## Expected outcome

| Delivery | Response | `kargo.akuity.io/refresh` on the Warehouse |
|---|---|---|
| `manifests/` touched, `manifests` branch | `200 {"msg":"refreshed 1 warehouse(s)"}` | set / changed |
| README only, `manifests` branch | `200 {"msg":"refreshed 0 warehouse(s)"}` | unchanged |
| `manifests/` touched, other branch | `200 {"msg":"refreshed 0 warehouse(s)"}` | unchanged |
| bad signature | `401 {"error":"unauthorized"}` | unchanged |

Row 2 is the feature: before #5611 that delivery refreshed the Warehouse
too. Row 3 is the pre-existing branch match, row 4 the signature check.
The refreshed Warehouse then runs a discovery pass, so after row 1 its
`status.discoveredArtifacts.git[0].commits` is fresh and any new commit
under `manifests/` turns into Freight.

## Troubleshooting

- **Row 1 says `refreshed 0 warehouse(s)`** — the payload's `clone_url`
  doesn't normalize to the Warehouse's `repoURL` (check `$GH_USER` and the
  fork name), or `ref` isn't `refs/heads/manifests`.
- **Every delivery is 401** — the secret came from the wrong namespace or
  the body was altered after signing; sign exactly the bytes you send.
- **Row 2 also refreshes** — you're on a Kargo older than 1.10, or the
  Warehouse lost its `includePaths`.
- **Connection refused** — the port-forward died; the external webhooks
  server listens on 443 (TLS) in the Service, hence `curl -k`.

## Appendix — the real-GitHub route

Only needed if you want GitHub itself to send the events. Expose the
external webhooks server publicly (for example `ngrok http 18443` on top
of the port-forward above), then on the fork add a webhook with payload
URL `https://<tunnel-host>$RPATH`, content type `application/json`, the
`github-receiver` secret, push events only. Push two commits to the
`manifests` branch, one under `manifests/` and one outside it, and read
the same annotation. The `manifests` branch seed, if your fork lacks it:

```bash
git clone https://github.com/<github-username>/kargo-demo-gitops.git
cd kargo-demo-gitops
git checkout --orphan manifests
git rm -rf .
mkdir -p manifests
printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo-config\ndata:\n  greeting: hello\n' > manifests/configmap.yaml
echo '# Initial commit on the manifests branch.' > README.md
git add manifests README.md
git commit -m "Seed manifests branch for kargo-demo-32"
git push origin manifests
```
