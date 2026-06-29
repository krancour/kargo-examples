#!/usr/bin/env bash
# Validate the active `pushIntegrationPolicy` by deliberately introducing
# a divergent commit on the target branch between two promotions.
#
# Usage:
#   ./validate.sh <github-username> <stage>
#
# Example:
#   ./validate.sh <github-username> test
#
# The script:
#   1. Force-discovers the Warehouse so a fresh promotion fires.
#   2. Waits for that promotion to complete.
#   3. Manually pushes a divergent commit to the stage branch on the fork.
#   4. Force-discovers the Warehouse a second time.
#   5. Reports the outcome of the second promotion (Succeeded vs Failed,
#      and what its push step did).
#
# Prerequisites:
#   - `gh` CLI authenticated against your fork.
#   - The fork has been cloned locally and is at the path passed as $REPO
#     (defaults to ./kargo-demo-gitops — clone it there first if not).
#   - kubectl context points at the cluster running Kargo.

set -euo pipefail

USER="${1:?missing github username}"
STAGE="${2:?missing stage name}"
REPO="${REPO:-./kargo-demo-gitops}"
NAMESPACE="kargo-demo-31"
BRANCH="31/stage/${STAGE}"

if [[ ! -d "$REPO/.git" ]]; then
  echo "ERROR: $REPO is not a git working tree. Clone https://github.com/${USER}/kargo-demo-gitops.git there first." >&2
  exit 1
fi

echo "[1/5] Refreshing Warehouse to force a baseline promotion..."
kubectl -n "$NAMESPACE" annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite

echo "[2/5] Waiting up to 2 minutes for the Stage to settle..."
for _ in $(seq 1 24); do
  phase=$(kubectl -n "$NAMESPACE" get promotions \
    --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{.items[-1:].status.phase}')
  echo "    latest promotion phase: ${phase:-<none>}"
  [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
  sleep 5
done

echo "[3/5] Pushing a divergent commit to ${BRANCH} as someone-other-than-Kargo..."
(
  cd "$REPO"
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git pull --ff-only origin "$BRANCH"
  date > divergent-${RANDOM}.txt
  git add divergent-*.txt
  git -c user.name="DivergentCommitter" \
      -c user.email="divergent@example.com" \
      commit -m "Out-of-band divergent commit"
  git push origin "$BRANCH"
)

echo "[4/5] Refreshing Warehouse again to force another promotion..."
kubectl -n "$NAMESPACE" annotate warehouse kargo-demo \
  kargo.akuity.io/refresh="$(date +%s)" --overwrite

echo "[5/5] Watch the resulting Promotion. Tail with:"
echo "    kubectl -n $NAMESPACE get promotions -w"
echo
echo "Then inspect the latest one with:"
echo "    kubectl -n $NAMESPACE get promotion <name> -o yaml | yq '.status'"
echo
echo "Compare actual behavior to the controller's pushIntegrationPolicy:"
echo "  AlwaysRebase  → Failed (cannot rebase preserving signature)"
echo "  RebaseOrMerge → Succeeded, push step shows merge commit"
echo "  RebaseOrFail  → Failed, error mentions integration policy"
echo "  AlwaysMerge   → Succeeded, push step shows merge commit"
