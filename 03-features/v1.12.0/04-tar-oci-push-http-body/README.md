# 04 — `tar`, `oci-push` from a local file, and `http` bodies from files

## What this validates

Three steps that together package rendered content and ship it somewhere,
with nothing outside the cluster involved:

- PR [akuity/kargo#6666](https://github.com/akuity/kargo/pull/6666) — the
  new `tar` step archives a file or directory in the workspace
  (`inPath` → `outPath`, optional `gzip`, optional `.gitignore`-style
  `ignore` patterns).
- PR [akuity/kargo#6893](https://github.com/akuity/kargo/pull/6893) —
  `oci-push` gains `srcPath`: push a local file as a single-layer OCI 1.1
  artifact. The manifest carries a top-level `artifactType` (mirrored onto
  `config.mediaType`), the 2-byte empty-descriptor config `{}`, the configured layer
  `mediaType`, and any `annotations`. The file streams from disk, and paths
  escaping the workspace are rejected.
- PR [akuity/kargo#6753](https://github.com/akuity/kargo/pull/6753) — the
  `http` step accepts `bodyFromFile`, a workspace-relative path, in place of
  an inline `body`. Setting both is rejected; path traversal is refused.

The example brings its own targets: a `registry:3` behind a cert-manager
self-signed certificate (so `oci-push` can speak HTTPS with
`insecureSkipTLSVerify: true`) and an HTTP echo server that returns the
request as JSON.

## Prerequisites

- A running Kargo control plane.
- cert-manager installed (it is part of the standard prerequisite install;
  see SETUP.md). It issues the registry's certificate.
- No fork, no Argo CD Application, no credentials.

## Apply

```bash
kubectl apply -f 03-features/v1.12.0/04-tar-oci-push-http-body/kargo.yaml
```

Give the `registry` and `echo` Deployments a moment to become Ready:

```bash
kubectl -n kargo-demo-38 rollout status deploy/registry deploy/echo
```

## Trigger

`test` auto-promotes once the Warehouse produces Freight. To force
discovery:

```bash
kubectl -n kargo-demo-38 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. The Promotion succeeds. Read its name and the recorded outputs:

   ```bash
   PROMO=$(kubectl -n kargo-demo-38 get promotions -o jsonpath='{.items[-1:].metadata.name}')
   kubectl -n kargo-demo-38 get promotion "${PROMO}" -o jsonpath='{.status.state.report}' | jq
   ```

   `echoedPromotion` equals the Promotion's own name (the file body made
   the round trip through the echo server), and `digest` is a `sha256:`
   manifest digest.
2. The artifact is in the registry, tagged with the Promotion name:

   ```bash
   kubectl -n kargo-demo-38 port-forward svc/registry 5000:5000 &
   sleep 2
   curl -sk https://localhost:5000/v2/config/app/tags/list | jq
   curl -sk -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
     "https://localhost:5000/v2/config/app/manifests/${PROMO}" | jq
   ```

   The manifest shows:
   - `artifactType: application/vnd.kargo-demo.config.v1`
   - `config.mediaType` mirroring the artifactType, size `2` (the empty descriptor)
   - one layer with `mediaType: application/vnd.kargo-demo.config.layer.v1.tar+gzip`
   - `annotations` including `io.kargo.promotion: <promotion name>`
3. The layer really is the tarball the `tar` step built:

   ```bash
   LAYER=$(curl -sk -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
     "https://localhost:5000/v2/config/app/manifests/${PROMO}" | jq -r '.layers[0].digest')
   curl -skL "https://localhost:5000/v2/config/app/blobs/${LAYER}" | tar tz
   kill %1
   ```

   Lists `deployment.yaml` and `PROVENANCE.txt` (paths are relative to
   `inPath`).
4. The echo server logged one POST to `/upload` whose body is the JSON
   payload: `kubectl -n kargo-demo-38 logs deploy/echo | grep -A3 upload`.

## Troubleshooting

- **`oci-push` fails with a certificate error** — `insecureSkipTLSVerify`
  is set on the step, so this means the registry isn't serving TLS at all.
  Check `kubectl -n kargo-demo-38 get certificate registry-tls` is Ready
  and the `registry` pod has restarted since the Secret appeared.
- **`oci-push` fails with `connection refused`** — the `registry`
  Deployment isn't Ready yet; the auto-promotion may have fired before it
  came up. Re-run the Trigger once it is.
- **`http` step fails its `successExpression`** — the echo server parses a
  JSON body only when `Content-Type: application/json` is sent; the
  `headers` entry supplies it. Inspect the raw response with
  `kubectl -n kargo-demo-38 logs deploy/echo`.
- **`tar` output is missing files** — `inPath` is a directory; files are
  archived relative to it. Confirm the `file-write` steps ran first.
