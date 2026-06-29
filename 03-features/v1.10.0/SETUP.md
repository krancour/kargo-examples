# Kargo 1.10 Feature Validation — Setup Guide

Complete the numbered steps below **once**, in order. After step 3 you can
run the five "zero-fork" examples. Each additional step unlocks more. The
full sequence sets up every example in directories `04-github-push`
through `18-webhook-path-filtering`.

Each example's own `README.md` still has per-example **Trigger** and
**Expected outcome** sections — this page only covers the shared plumbing.

---

## Step 1 — Cluster and Kargo

Bring up (or confirm) a local Kargo dev stack:

```bash
make hack-tilt-up
```

The Tilt UI lives at <http://localhost:10350>, the Kargo UI at
<http://localhost:30082> (admin/admin), and the external webhooks server at
<http://localhost:30083>.

## Step 2 — Argo CD

Argo CD must be installed into the `argocd` namespace with
admin/admin available at <http://localhost:30080>. The Tilt stack installs
it automatically. If you're running Kargo some other way, install Argo CD
yourself and make sure the `kargo-controller` can talk to its API.

## Step 3 — Apply the shared resources

```bash
kubectl apply -f 00-common/kargo.yaml
```

This creates the shared namespaces, the cluster-level webhook receivers,
the cluster-default git identity/signing key, and the `github` credential
Secret template.

> ✅ **You can now run: 08, 10, 14, 15, 16.** (No fork, no Argo CD
> Application, no GitHub credentials needed.)

---

## Step 4 — Fork the demo repo

Fork [krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops)
to your own GitHub account. **Uncheck "Copy the main branch only"** when
forking so the `kustomize` branch comes along.

Set a shell variable to your fork's username — it's used in the rest of
the steps:

```bash
export GH_USER=<your-github-username>
```

## Step 5 — Configure the GitHub App

The `00-common/kargo.yaml` bundles an example `github` credentials Secret
scoped via regex to `^https://github.com/<github-username>/.*`. That Secret will
**not** authenticate against your fork unless you own the `<github-username>`
account, so you'll need to replace it with an App installed against your
fork.

1. Create a GitHub App (Settings → Developer settings → GitHub Apps).
   Grant it at minimum: `Contents: Read & write` and
   `Pull requests: Read & write`.
2. Install the App on your `kargo-demo-gitops` fork.
3. Note the App's `Client ID`, a generated `Private key` (downloaded as a
   PEM), and the numeric `Installation ID` (visible in the URL after you
   click *Configure* on the installed App).
4. Replace the `github` Secret in `kargo-shared-resources`:

   ```bash
   kubectl -n kargo-shared-resources delete secret github
   kubectl -n kargo-shared-resources create secret generic github \
     --type=Opaque \
     --from-literal=repoURL="^https://github.com/${GH_USER}/.*" \
     --from-literal=repoURLIsRegex=true \
     --from-literal=githubAppClientID="<your-app-client-id>" \
     --from-literal=githubAppInstallationID="<your-app-installation-id>" \
     --from-file=githubAppPrivateKey=/path/to/downloaded-private-key.pem
   kubectl -n kargo-shared-resources label secret github \
     kargo.akuity.io/cred-type=git
   ```

   > On your fork's repo settings, also confirm **Pull Requests → Allow
   > squash merging** is enabled (default for new GitHub repos; required
   > by example 11).

## Step 6 — Seed the extra branches on your fork

Two examples need branches your fork doesn't yet have. Run this once from
anywhere outside the Kargo repo:

```bash
git clone "https://github.com/${GH_USER}/kargo-demo-gitops.git" /tmp/kargo-demo-gitops
cd /tmp/kargo-demo-gitops

# --- toml branch (example 07) ---
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
git push -u origin toml

# --- manifests branch (example 18) ---
git checkout --orphan manifests
git rm -rf .
mkdir -p manifests
cat > manifests/configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-config
data:
  greeting: hello
EOF
echo "# Initial commit on the manifests branch." > README.md
git add manifests README.md
git commit -m "Seed manifests branch for kargo-demo-32"
git push -u origin manifests
```

Keep `/tmp/kargo-demo-gitops` around — example 17's `validate.sh`
expects a local clone at `./kargo-demo-gitops` by default, so symlink or
re-clone there if you want to run 17.

## Step 7 — Substitute `<github-username>` in the feature manifests

Every example under `04-*` through `18-*` that references your fork has
`<github-username>` placeholders. Replace them all in one shot:

```bash
cd kargo-examples      # repo root, NOT kargo repo root
find 03-features -name '*.yaml' -exec \
  sed -i.bak "s|<github-username>|${GH_USER}|g" {} \;
find 03-features -name '*.bak' -delete
```

> ✅ **You can now run: 04, 05, 06, 07, 09, 11, 12, 13, 18** (example 18
> still needs step 8 for webhooks to actually deliver).

---

## Step 8 — (Only needed for 18) Public webhook tunnel

Example 18 proves GitHub-push webhooks honor the Warehouse's
`includePaths`. For that to fire, GitHub has to be able to POST to the
external-webhooks server.

```bash
# In a separate terminal, stood up against localhost:30083:
ngrok http 30083
```

Copy the `https://<random>.ngrok-free.app` URL, then find the
receiver path:

```bash
kubectl get clusterconfig cluster -o yaml \
  | yq '.status.webhookReceivers[] | select(.name=="github") | .path'
```

…and the shared secret it validates with:

```bash
kubectl -n kargo-cluster-secrets get secret github-receiver \
  -o jsonpath='{.data.secret}' | base64 -d ; echo
```

Configure a webhook on your fork (Settings → Webhooks → Add):

- **Payload URL**: `https://<ngrok-host><receiver-path>`
- **Content type**: `application/json`
- **Secret**: the base64-decoded value above
- **Events**: Just the push event

## Step 9 — (Only needed for 17) Policy toggle + helper

Example 17 validates the four `pushIntegrationPolicy` values. For each
value you want to exercise, re-install the chart:

```bash
# From the kargo repo root:
helm upgrade kargo charts/kargo \
  -n kargo --reuse-values \
  --set controller.gitClient.pushIntegrationPolicy=RebaseOrMerge
kubectl -n kargo rollout status deploy/kargo-controller
```

Then run the helper script from the example directory:

```bash
cd kargo-examples/03-features/17-push-integration-policy
REPO=/tmp/kargo-demo-gitops ./validate.sh "${GH_USER}" test
```

Repeat for `AlwaysRebase`, `RebaseOrMerge`, `RebaseOrFail`, `AlwaysMerge`;
compare the final Promotion's `.status.phase` to the matrix in that
example's README.

---

## Running any example

Once the applicable steps above are done, applying any example is two
commands (one if it has no `argocd.yaml`):

```bash
kubectl apply -f 03-features/NN-<name>/argocd.yaml   # if present
kubectl apply -f 03-features/NN-<name>/kargo.yaml
```

Force Warehouse discovery whenever you want a promotion to fire
immediately:

```bash
kubectl -n kargo-demo-NN annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite
```

## Recommended order to work through them

From fastest-to-validate to most-setup-required:

| Order | Example | Unlocks on step |
|-------|---------|-----------------|
| 1 | 10-set-freight-alias | 3 |
| 2 | 16-keep-namespace | 3 |
| 3 | 08-fail-step | 3 |
| 4 | 14-chart-skip-tls | 3 |
| 5 | 15-replicate-shared | 3 |
| 6 | 06-oci-push | 3 (network to `ttl.sh`) |
| 7 | 13-warehouse-since | 7 |
| 8 | 07-toml-update | 7 (depends on step 6 branch seed) |
| 9 | 04-github-push | 7 |
| 10 | 12-git-clone-identity | 7 |
| 11 | 09-git-tag | 7 |
| 12 | 11-git-merge-squash | 7 (requires squash-merge enabled on fork) |
| 13 | 05-argocd-wait | 7 |
| 14 | 18-webhook-path-filtering | 8 |
| 15 | 17-push-integration-policy | 9 |

## Cleanup

Each example lives in its own `kargo-demo-NN` namespace. To tear one down
without losing the rest:

```bash
kubectl delete -f 03-features/NN-<name>/kargo.yaml
kubectl delete -f 03-features/NN-<name>/argocd.yaml   # if present
```

Example 16 is the exception — it deliberately leaves the namespace behind
(that's what it validates). See its README for the full teardown.
