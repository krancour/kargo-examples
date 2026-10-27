# 01 — Auto-promotion holds after a rollback

## What this validates

PR [akuity/kargo#6334](https://github.com/akuity/kargo/pull/6334) — when a
user promotes Freight that is **not** the current auto-promotion candidate
for an origin (typically a rollback to an older version), Kargo records a
*hold* for that origin in the Stage's `status.autoPromotionHolds` and stops
auto-promoting newer Freight from it. Promoting the current candidate lifts
the hold. The Promotion webhook stamps the intent on the Promotion itself:
`kargo.akuity.io/auto-promotion-hold` or `kargo.akuity.io/auto-promotion-resume`,
valued with the origin key (`Warehouse/kargo-demo`).

Two smaller changes ride along:

- PR [akuity/kargo#6679](https://github.com/akuity/kargo/pull/6679) — the
  `PromotionCreated` event for a Promotion annotated
  `kargo.akuity.io/rollback: "true"` carries
  `event.kargo.akuity.io/rollback: "true"`.
- PR [akuity/kargo#6562](https://github.com/akuity/kargo/pull/6562) —
  approving Freight for a Stage no longer makes it available there if the
  Stage does not request Freight from that origin. This is the negative case.

## Prerequisites

- A running Kargo control plane.
- Nothing else — no fork, no Argo CD Application, no credentials.

## Apply

```bash
kubectl apply -f 03-features/v1.12.0/01-auto-promotion-holds/kargo.yaml
```

## Trigger

The sequence matters. Each step waits for the previous Promotion to succeed.

1. **Older Freight lands first.** The Warehouse starts constrained to
   `~1.28.0`. Force discovery and let auto-promotion promote it:

   ```bash
   kubectl -n kargo-demo-35 annotate warehouse kargo-demo \
     kargo.akuity.io/refresh="$(date +%s)" --overwrite
   ```

2. **A newer candidate appears.** Widen the constraint to `^1.28.0` so the
   newest 1.x tag is discovered, then refresh again. Auto-promotion promotes it.

   ```bash
   kubectl -n kargo-demo-35 patch warehouse kargo-demo --type=merge \
     -p '{"spec":{"subscriptions":[{"image":{"repoURL":"public.ecr.aws/nginx/nginx","constraint":"^1.28.0","strictSemvers":true,"discoveryLimit":3}}]}}'
   kubectl -n kargo-demo-35 annotate warehouse kargo-demo \
     kargo.akuity.io/refresh="$(date +%s)" --overwrite
   ```

3. **Roll back.** Find both pieces of Freight, then promote the older one
   by hand, marked as a rollback:

   ```bash
   kubectl -n kargo-demo-35 get freight \
     -o custom-columns=NAME:.metadata.name,ORIGIN:.origin.name,TAG:.images[0].tag
   OLD=$(kubectl -n kargo-demo-35 get freight -o json | jq -r '
     .items[] | select(.origin.name == "kargo-demo" and (.images[0].tag | startswith("1.28.")))
     | .metadata.name')
   kubectl create -f - <<EOT
   apiVersion: kargo.akuity.io/v1alpha1
   kind: Promotion
   metadata:
     generateName: test-rollback-
     namespace: kargo-demo-35
     annotations:
       kargo.akuity.io/rollback: "true"
   spec:
     stage: test
     freight: ${OLD}
   EOT
   ```

4. **Lift the hold.** Promote the current candidate (the newest Freight from
   `kargo-demo`) by hand:

   ```bash
   NEW=$(kubectl -n kargo-demo-35 get freight \
     -o json | jq -r '[.items[] | select(.origin.name == "kargo-demo")]
       | sort_by(.metadata.creationTimestamp) | last | .metadata.name')
   kubectl create -f - <<EOT
   apiVersion: kargo.akuity.io/v1alpha1
   kind: Promotion
   metadata:
     generateName: test-resume-
     namespace: kargo-demo-35
   spec:
     stage: test
     freight: ${NEW}
   EOT
   ```

5. **Negative case.** Approve Freight from the unrequested `other` origin
   for `test`, then try to promote it:

   ```bash
   OTHER=$(kubectl -n kargo-demo-35 get freight \
     -o jsonpath='{.items[?(@.origin.name=="other")].metadata.name}')
   kubectl -n kargo-demo-35 patch freight "${OTHER}" --subresource=status \
     --type=merge -p '{"status":{"approvedFor":{"test":{}}}}'
   kubectl create -f - <<EOT
   apiVersion: kargo.akuity.io/v1alpha1
   kind: Promotion
   metadata:
     generateName: test-cross-origin-
     namespace: kargo-demo-35
   spec:
     stage: test
     freight: ${OTHER}
   EOT
   ```

## Expected outcome

1. After step 1, `test` is on the newest nginx `1.28.x`. After step 2, it is on the
   newest 1.x tag via an auto-promotion.
2. The rollback Promotion from step 3 is stamped by the webhook:

   ```bash
   kubectl -n kargo-demo-35 get promotions \
     -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,HOLD:.metadata.annotations.kargo\\.akuity\\.io/auto-promotion-hold,RESUME:.metadata.annotations.kargo\\.akuity\\.io/auto-promotion-resume
   ```

   The `test-rollback-*` row shows `HOLD: Warehouse/kargo-demo`. Auto-promotion's
   own Promotions show neither annotation.
3. Once it succeeds, the Stage records the hold:

   ```bash
   kubectl -n kargo-demo-35 get stage test \
     -o jsonpath='{.status.autoPromotionHolds}' | jq
   ```

   Expect a `Warehouse/kargo-demo` key whose `freightName` is `$OLD` and whose
   `promotionName` is the rollback Promotion.
4. The hold sticks. Refresh the Warehouse again and wait a minute: no new
   Promotion is created and `test` stays on `1.28.x`:

   ```bash
   kubectl -n kargo-demo-35 get stage test \
     -o jsonpath='{.status.freightHistory[0].items.*.images[0].tag}'
   ```

5. The rollback's `PromotionCreated` event is annotated:

   ```bash
   kubectl -n kargo-demo-35 get events -o json | jq -r '
     .items[] | select(.reason == "PromotionCreated")
     | "\(.involvedObject.name)\t\(.metadata.annotations["event.kargo.akuity.io/rollback"] // "-")"'
   ```

   Only the `test-rollback-*` Promotion shows `true`.
6. After step 4 succeeds, the `test-resume-*` Promotion carries
   `RESUME: Warehouse/kargo-demo`, `status.autoPromotionHolds` is empty
   (the key is absent), and `test` is back on the newest tag.
7. Step 5 is rejected at admission. `kubectl create` fails with an error
   containing `Freight is not available to this Stage`, and no
   `test-cross-origin-*` Promotion exists.

## Troubleshooting

- **Step 1 promotes something newer than 1.28.x** — the Warehouse constraint was widened
  before the first Freight was produced. Delete the project and start over;
  the order of tags is what makes the hold observable.
- **`$OLD` or `$NEW` is empty** — the Warehouse has not produced both
  pieces of Freight yet. List Freight with the `custom-columns` command in
  step 3 and wait for both a `1.28.x` tag and a newer tag to appear under the
  `kargo-demo` origin.
- **No hold recorded** — the hold is committed only when the rollback
  Promotion *succeeds*. Check its phase; a `Failed` or `Errored` rollback
  neither establishes nor lifts a hold.
- **Auto-promotion re-promotes the newer tag despite the hold** — confirm the
  Promotion that did it was created by a user rather than the controller
  (it would carry one of the intent annotations). Controller-created
  Promotions are exempt from stamping and respect holds.
- **The status patch in step 5 is rejected** — that is also a valid
  negative result: record the error. The Promotion create in the same step
  must still fail.
