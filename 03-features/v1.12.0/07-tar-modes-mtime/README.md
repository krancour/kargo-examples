# 07 — `tar` with fixed modes and a fixed modification time

## What this validates

Two options backported to the `tar` step after v1.12.0:

- PR [akuity/kargo#7770](https://github.com/akuity/kargo/pull/7770) —
  `fileMode` and `dirMode` record a fixed octal mode for every regular file
  and directory in the archive, in place of each entry's own mode. Files a
  promotion renders are often owner-only (`0600`/`0700`), which a non-root
  container can't read after extraction. World-writable modes are refused,
  failing the step terminally. Not in any tag yet; needs a build of
  `release-1.12` newer than v1.12.5.
- PR [akuity/kargo#7657](https://github.com/akuity/kargo/pull/7657) — `mtime`
  records a fixed modification time for every entry, so identical content
  produces an identical archive (and an identical digest). The same PR makes
  the step always strip ownership: every entry has user and group ID `0` and
  no user or group name. In v1.12.5 and later.

Three Stages archive the same rendered files:

| Stage | `fileMode` | `dirMode` | `mtime` | Expected |
|---|---|---|---|---|
| `fixed` | `"0644"` | `"0755"` | `2000-01-01T12:00:00Z` | Archive shows the fixed modes and time |
| `asis` | — | — | — | Archive shows `0600`/`0700` and real times |
| `denied` | `"0666"` | — | — | Promotion `Failed`, world-writable |

`file-write` creates files at `0600` and directories at `0700`, so any other
mode in the archive came from the `tar` step. Each archive is pushed to an
in-namespace registry so it can be pulled back out and listed.

## Prerequisites

- A Kargo control plane built from `release-1.12` after v1.12.5.
- cert-manager installed (it is part of the standard prerequisite install;
  see SETUP.md). It issues the registry's certificate.
- No fork, no Argo CD Application, no credentials.

## Apply

```bash
kubectl apply -f 03-features/v1.12.0/07-tar-modes-mtime/kargo.yaml
kubectl -n kargo-demo-41 rollout status deploy/registry
```

## Trigger

All three Stages auto-promote once the Warehouse produces Freight. To force
discovery:

```bash
kubectl -n kargo-demo-41 annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Expected outcome

Set up a port-forward to the registry and two helpers:

```bash
kubectl -n kargo-demo-41 port-forward svc/registry 5000:5000 &
sleep 2
tags()  { curl -sk "https://localhost:5000/v2/bundle/$1/tags/list" | jq -r '.tags[]'; }
layer() { curl -sk -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
            "https://localhost:5000/v2/bundle/$1/manifests/$2" | jq -r '.layers[0].digest'; }
show()  { curl -skL "https://localhost:5000/v2/bundle/$1/blobs/$(layer "$1" "$2")" | tar tvz; }
```

1. The `fixed` and `asis` Promotions are `Succeeded`, and `denied` is
   `Failed` because the mode is world-writable:

   ```bash
   kubectl -n kargo-demo-41 get promotions -o json | jq -r \
     '.items[] | "\(.spec.stage)\t\(.status.phase)\t\(.status.message // "")"'
   ```

   The `denied` message contains
   `invalid fileMode: mode "0666" must not be world-writable`.
2. `fixed`'s archive has the fixed modes, the fixed time, and no owner:

   ```bash
   show fixed "$(tags fixed | head -1)"
   ```

   `base/` is `drwxr-xr-x`; `base/deployment.yaml` and
   `base/kustomization.yaml` are `-rw-r--r--`; every entry is dated
   `Jan  1  2000` and owned by `0 0`.
3. `asis`'s archive keeps the entries' own modes and times, still with no
   owner:

   ```bash
   show asis "$(tags asis | head -1)"
   ```

   `base/` is `drwx------`; both files are `-rw-------`; dates are today's;
   owner and group are `0 0`.
4. Archiving identical content again gives an identical layer with `mtime`
   set, and a different one without it. Promote each Stage's current Freight
   a second time:

   ```bash
   for STAGE in fixed asis; do
   FREIGHT=$(kubectl -n kargo-demo-41 get stage "${STAGE}" \
     -o jsonpath='{.status.freightHistory[0].items.*.name}')
   kubectl create -f - <<EOT
   apiVersion: kargo.akuity.io/v1alpha1
   kind: Promotion
   metadata:
     generateName: ${STAGE}-again-
     namespace: kargo-demo-41
   spec:
     stage: ${STAGE}
     freight: ${FREIGHT}
   EOT
   done
   ```

   Once both are `Succeeded`, each repository has two tags. Compare their
   layer digests:

   ```bash
   for STAGE in fixed asis; do
     echo "${STAGE}:"; for T in $(tags "${STAGE}"); do layer "${STAGE}" "${T}"; done
   done
   kill %1
   ```

   `fixed` prints the same digest twice; `asis` prints two different ones.

## Troubleshooting

- **`oci-push` fails with `connection refused`** — the `registry`
  Deployment wasn't Ready when the auto-promotion fired. Re-run the Trigger
  once it is.
- **`oci-push` fails with a certificate error** — `insecureSkipTLSVerify`
  is set on the step, so the registry isn't serving TLS at all. Check that
  `kubectl -n kargo-demo-41 get certificate registry-tls` is Ready and that
  the `registry` pod started after the Secret appeared.
- **`fixed` or `denied` fails schema validation on `fileMode`** — the build
  predates #7770. Check the controller image.
- **`asis` shows a non-zero owner** — the build predates #7657 (v1.12.5).
- **`fixed` prints two different digests** — the rendered content differed
  between the two Promotions. Both must use the same Freight; check the
  `freight` each Promotion names.
