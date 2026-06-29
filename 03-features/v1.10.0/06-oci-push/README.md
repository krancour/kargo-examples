# 06 — `oci-push` step (and port-numbered registry refs)

## What this validates

- PR [akuity/kargo#5782](https://github.com/akuity/kargo/pull/5782) — the new
  `oci-push` promotion step. Copies/retags OCI artifacts (container images
  and OCI Helm charts) between registries, preserving the manifest list for
  multi-arch images.
- PR [akuity/kargo#5894](https://github.com/akuity/kargo/pull/5894) — the
  `srcRef` / `destRef` regex now accepts `host:port/repo:tag` style
  references for non-default registry ports (e.g. `localhost:5000/...`).

This example does no Git work and stands up no Argo CD `Application`s. The
entire pipeline is one `oci-push` step that retags every newly discovered
nginx image to a stage-specific tag in the public, anonymous
[`ttl.sh`](https://ttl.sh) ephemeral registry.

## Prerequisites

- A running Kargo control plane with image discovery working
  (Tilt: `make hack-tilt-up`).
- Outbound HTTPS connectivity from the Kargo controller pod to:
  - `public.ecr.aws` (source, AWS ECR public).
  - `ttl.sh` (destination, anonymous push allowed).
- No credentials are required — `public.ecr.aws/nginx/nginx` is anonymous,
  and `ttl.sh` accepts anonymous pushes for any tag.

## Setup

```bash
make hack-tilt-up                      # if not already running
kubectl apply -f 00-common/kargo.yaml  # once per cluster
```

Nothing project-specific to set up; the destination registry is public.

## Apply

```bash
kubectl apply -f 03-features/06-oci-push/kargo.yaml
```

> 💡 **About the port-number fix**: this example does not use port numbers
> in the registry URL because `public.ecr.aws` and `ttl.sh` both serve on
> 443. The fix in #5894 widens the `srcRef`/`destRef` regex so that
> references such as `localhost:5000/myrepo:mytag` or
> `internal-registry.example.com:8443/x@sha256:...` now validate. To check,
> swap `destRepo` to `host.docker.internal:5000/kargo-demo-20` (assuming
> you've started a `registry:2` container with
> `docker run -d -p 5000:5000 --restart=always --name registry registry:2`)
> and re-apply — schema validation will accept it.

## Trigger

`test` auto-promotes as soon as the Warehouse discovers an nginx image. To
force discovery:

```bash
kubectl -n kargo-demo-20 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

1. For each promotion, the `push` step's outputs include an `image`
   reference such as
   `ttl.sh/kargo-demo-20:test-1.29.2-1h`, a `digest`, and a `tag`.
2. You can pull the result from any host with Docker:
   ```bash
   docker pull ttl.sh/kargo-demo-20:test-1.29.2-1h
   ```
3. `crane manifest ttl.sh/kargo-demo-20:test-1.29.2-1h | jq '.annotations'`
   shows the `org.opencontainers.image.source` annotation (unprefixed →
   image manifest), and the `manifest:`-prefixed `io.kargo.*` annotations.
4. Because nginx is multi-arch, the destination is a manifest list; the
   per-platform image manifests carry the `manifest:` annotations, and the
   index has none beyond what was on the source.

## Troubleshooting

- **`step failed: ... 401 Unauthorized` on push** — the destination
  registry requires authentication. `ttl.sh` does not, but if you swapped
  it for a private registry, add credentials per
  [Managing Secrets](https://docs.kargo.io/user-guide/security/managing-secrets/)
  with `kargo.akuity.io/cred-type: image` and a `repoURL` matching the
  destination.
- **`exceeds max artifact size`** — the controller chart value
  `controller.images.push.maxArtifactSize` (default 1 GiB) governs how
  large a cross-repo push may be. Same-repo retags are exempt.
- **Schema validation rejects `host:port/...`** — you're on a Kargo
  version older than 1.10. The pattern was relaxed in #5894.
