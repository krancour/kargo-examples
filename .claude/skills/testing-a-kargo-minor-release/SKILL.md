---
name: testing-a-kargo-minor-release
description: Use when validating a Kargo OSS minor release (v1.N) with the kargo-examples repo — discovering what shipped, writing feature examples under 03-features/v1.N.0, running every example on the OrbStack cluster, reporting results, or resuming such a run at a given phase
---

# Testing a Kargo Minor Release

The procedure for validating a Kargo OSS minor release with this repo. Five
phases, each resumable on its own.

Facts that hold throughout:

- **Repos.** Examples: this repo. Source: a local clone of akuity/kargo; ask
  for its path if it isn't obvious, and read from whichever remote points at
  `akuity/kargo` (`git remote -v`), called `upstream` below.
- **OSS only.** Fleet/target-aware Stages and Promotions only fully work in
  Kargo EE. Drop those PRs from the candidate list, and anything else that's
  EE-only, unless the user says this run covers EE.
- **OrbStack only.** `kubectl config current-context` must print `orbstack`.
  Anything else is a hard stop, at the start of every phase that touches the
  cluster.
- **The working-tree `00-common/kargo.yaml` may hold real credentials** the
  user substituted in. Apply it. Never stage it. Every `git add` names
  explicit paths; never `-A`, `-u`, or `.`. Never `cat` or `git diff` it
  either; `git diff --stat` is the only way to look at it. Keys must not
  land in a transcript.
- **`<github-username>` placeholders** are substituted in a pipe at apply
  time, never edited in place:
  `sed "s|<github-username>|$GH_USER|g" f.yaml | kubectl apply -f -`.
  Every example names the fork `kargo-demo-gitops`. When the user's fork is
  named differently, map the repo in the same pipe, first:
  `sed -e "s|<github-username>/kargo-demo-gitops.git|$GH_USER/<fork>.git|g" -e "s|<github-username>|$GH_USER|g"`.
- **Status messages state only what a tool result showed.** A command that
  was rejected or timed out is reported as exactly that. Never imply a PR,
  Promotion, or namespace exists because the plan expected one.
- **The user runs commit and push.** Hand over commands: staging and commit
  in one paste, message from a quoted heredoc, `-s` for sign-off. Follow the
  shipping-a-change skill if it's available.

## Phases and resuming

| Phase | Does | Leaves behind |
|---|---|---|
| 0 Inputs | Version, install path, cluster check | Nothing |
| 1 Discover | Candidate feature list, pruned by the user | Pruned list in chat |
| 2 Write | `03-features/v1.N.0/` examples, commit command | Example dirs |
| 3 Execute | Every example in the repo, in batches, on OrbStack | `TEST-RESULTS-v1.N.md`, growing per batch |
| 4 Report | Final results file and score | `TEST-RESULTS-v1.N.md`, complete |

The user may say "start at phase 3" or "just rerun 03-features/v1.12.0/04".
A resume re-does the named phase in full, narrowed only as far as they say,
and skips everything before it. What an earlier phase left behind is reused
as-is: existing example dirs are not rewritten, and the pruned list is not
re-derived. The named phase's own prechecks always run again. When the build
changed since the last run, phase 3 restarts from batch one with a fresh
results table; rows from the old build are not evidence for the new one.
Open every run by stating the phase you're starting at and why.

## Phase 0: Inputs

1. Version under test, `v1.N`.
2. `GH_USER`: the GitHub account holding the user's fork of
   `kargo-demo-gitops`, and the fork's name if it isn't `kargo-demo-gitops`.
   Used for every placeholder substitution.
3. Install path, asked once with a single question:
   - **a. User installs.** They bring up Tilt or helm install a build
     themselves. Phase 3 waits for their go.
   - **b. Skill installs.** Helm install a published chart. Need a chart
     version; with no GA tag yet, use the newest `v1.N.0-rc.*` from
     `git tag --sort=-v:refname` in the kargo clone. Mirror the kargo
     repo's `hack-install-cert-manager`, `hack-install-argocd` and
     `hack-install-argo-rollouts` Makefile targets and
     `hack/tilt/values.dev.yaml` for cert-manager, Argo CD (admin/admin,
     NodePort 30080), Argo Rollouts and the Kargo values (API on NodePort
     30081, TLS off, admin/admin). Leave out Dex and the chart-level signing
     key; `00-common` supplies the git identity.
4. Cluster check. Also confirm the cluster is fresh or at least free of
   `kargo-demo-*` namespaces; delete any that are there.

## Phase 1: Discover

Merged PRs on the release branch, not release notes and not a draft file.

```bash
cd <kargo clone> && git fetch upstream
# release-1.N exists?
git rev-parse --verify upstream/release-1.N 2>/dev/null \
  && HEAD=upstream/release-1.N || HEAD=upstream/main
git log --format='%s' upstream/release-1.$((N-1))..$HEAD | grep -oE '#[0-9]+' | sort -u
```

Fetch title, labels and body for each with `gh pr view <n> -R akuity/kargo
--json title,labels,body`. Drop chores, dependency bumps, docs, tests,
refactors, fleet/target-aware and EE-only work. Also grep this repo for any
field a PR removed or deprecated; fixing existing examples for a breaking
change is in scope.

Present one table: PR, title, how it will be validated (new example / manual
UI check for the user / skip with reason). **Stop there.** Nothing is
designed or written until the user prunes the list.

## Phase 2: Write

One directory per feature, `03-features/v1.N.0/NN-slug/`, numbered in the
order the user pruned. Match the existing shape exactly:

- `README.md` with sections: What this validates (link the PR),
  Prerequisites, Apply, Trigger, Expected outcome, Troubleshooting.
- `kargo.yaml`, plus `argocd.yaml` when an Application is involved, with a
  comment marking the novel bit.
- Project name `kargo-demo-NN`, where NN continues from the highest in use:
  `grep -rho 'kargo-demo-[0-9]*' --include='*.yaml' . | sort -u | tail -1`.
- `SETUP.md` for the version, covering only shared plumbing.

Prefer zero-fork designs (public images, public charts, in-namespace echo
servers) so the example needs nothing from `00-common`. Don't hardcode the
"newest" tag of a public image in a README or a check (`1.29.x`): it moves.
Say "the newest tag" and select Freight by origin and creation time. Add a negative case
when it's cheap, like the `denied` Stage in v1.11's example 02.

Use the writing-yaml skill if it's available. Verify with `yq -e '.'` on
every manifest, and with `kubectl apply --dry-run=server` once a cluster
with the CRDs is up. Then hand over one commit command for the new
directory. Fixes to existing examples for a breaking change go in their own
commit, handed over first.

## Phase 3: Execute

Prechecks: context is `orbstack`; Kargo is running and its image tag is the
build under test (`kubectl -n kargo get deploy kargo-api -o
jsonpath='{.spec.template.spec.containers[0].image}'`); Argo CD is in
`argocd`. Path a: wait for the user's go before any of this, and when the
image is a local build with no published tag, ask them to confirm it's the
one and record the tag verbatim in the results header. Then apply the
working-tree `00-common/kargo.yaml`.

**Scope is every example in the repo** unless the user narrows it: each
directory holding a `kargo.yaml` under `01-*`, `02-*`, and every
`03-features/*`, in that order, oldest version first.

**Batches of four, with cleanup between.** OrbStack has limited resources.
Per example:

1. Read its README, or the manifest comments when there is none, for
   Trigger and Expected outcome.
2. Apply `argocd.yaml` then `kargo.yaml`, through the placeholder pipe.
3. Read the example's own `ProjectConfig` for which Stages auto-promote.
   Never carry the answer over from the previous example: in the base
   examples `test` and `uat` usually do and `prod` usually doesn't, and the
   selector may be a regex. Trigger as the README says; usually a Warehouse
   refresh annotation. A Stage without auto-promotion gets a Promotion
   created by hand from its upstream Stage's current Freight, after that
   Stage is Verified. Don't hand-promote a Stage that auto-promotes; it
   only makes duplicate Promotions.
4. Poll Promotions and Applications in a loop, ten seconds apart, and keep
   any single poll under five minutes; post a one-line status to the user
   between polls. Never a bare `kubectl get -w`. Soak times in the base
   examples are 10m: patch them to 1m on the live Stages for the run
   (`requiredSoakTime`) and say so in the results row; nobody is waiting
   ten minutes per stage to prove a soak. A `prod` that uses
   `git-wait-for-pr` blocks until a human merges the PR on the fork: ask
   the user once whether the skill may merge; on a yes, `gh pr merge
   --merge` the open PR against `NN/stage/prod`, and only after a tool
   result shows that PR exists.
5. Run the README's specific checks and keep the output as evidence.
6. Classify: ✅ matched expected outcome; ❌ did not; ⚠️ not run, with the
   reason.

⚠️ is for what the skill can't do alone: a chart reinstall for a policy
toggle, a UI-only check, an EE-only feature. The user can opt any of these
in. A webhook receiver is not on that list: play the provider. Build the
push payload the receiver parses, sign it with the receiver Secret
(`X-Hub-Signature-256` for GitHub), and POST it through a port-forward to
`kargo-external-webhooks-server`; the 200 body says how many Warehouses
were refreshed. No tunnel, no webhook on the fork.

An example bug (stale path, removed field, wrong namespace) gets fixed and
the example rerun, and the fix is noted in results. A suspected Kargo bug is
recorded with expected vs observed and a controller log excerpt. Nothing is
patched in kargo and nothing is filed.

After each batch: delete the batch's Argo CD ApplicationSets and
Applications **by name** (`kubectl -n argocd get applicationsets,applications
-o name | grep kargo-demo-`), never `--all`; delete its Projects; then delete
every `kargo-demo-*` namespace that still exists, including the Argo CD
destination namespaces (`kargo-demo-NN-<stage>`), and `kubectl wait
--for=delete` on each. Confirm no Terminating pods remain, then start the
next batch. The same applies to a single example's rerun: re-applying while
its destination namespace is still Terminating makes the sync fail with
`unable to create new content in namespace`. Leftover `kargo-demo-*` namespaces found at the
start of a run are deleted the same way, without asking. Append the batch's
rows to `TEST-RESULTS-v1.N.md` before moving on, so an interruption loses
nothing.

### Troubleshoot first

The user is engaged only for what the skill genuinely cannot resolve. Two
attempts at a fix come before any question to them.

| Resolve alone | Escalate |
|---|---|
| Leftover or stuck-terminating `kargo-demo-*` namespaces: delete, clear finalizers | Wrong cluster context |
| Kargo or Argo CD pods not ready yet: wait, then check logs | A credential, token, or external account only the user holds |
| Image pull backoff on a public image: retry, check the tag exists | The Kargo build itself looks broken (crashlooping controller, CRDs missing after install) |
| Promotion never starts: refresh the Warehouse again, check the Stage's `requestedFreight`; if the Stage doesn't auto-promote, promote by hand | Two fix attempts failed |
| PR-path Promotion Errored on `task.outputs['open-pr'].pr.id` with `commit` and `open-pr` Skipped: the fork's `NN/stage/<stage>` branch already holds this content from an earlier run, so there was no diff and no PR. Delete that branch on the fork (`gh api -X DELETE repos/$GH_USER/<fork>/git/refs/heads/NN/stage/<stage>`) and re-promote | |
| Application Degraded with ImagePullBackOff on a `bitnami/*` image: Docker Hub dropped Bitnami's versioned tags and kept only `latest`. Raise the Warehouse's chart `semverConstraint` to versions that reference `latest` (nginx ≥ 22.0.7); don't override the image to `bitnamilegacy/*` | |
| Sync fails with `namespaces "kargo-demo-NN-<stage>" not found`: the Application's `syncPolicy` lacks `syncOptions: [CreateNamespace=true]`. Add it to `argocd.yaml` | |
| Project apply refused with "namespace already exists and is not labeled as a Project namespace": a pre-created Namespace needs the label `kargo.akuity.io/project: "true"` | |
| A step config with a JSON-shaped string (`{"a": "..."}`) fails with `Expected: string, given: object`: expression evaluation parses it. Build it with `${{ quote({...}) }}` inside a block scalar | |
| An example's URL placeholder like `http://<host IP>:8080` wants a listener on the host: run one (Python `http.server`) and point the live PromotionTask at `host.internal`, OrbStack's host address | |
| `stageMetadata()` reads nil right after `set-metadata`, or `status.metadata` is missing after a Stage's first Promotion: known suspect (v1.12 run), record it, re-promote | |
| Step timeout that a second attempt clears | A ⚠️ opt-in they haven't given |
| Anything in the example README's Troubleshooting section | |

Every self-resolved problem is noted in the example's results row, so it
stays visible. A ❌ on one example is not an escalation: record it, finish
the batch, and it shows up in the batch status line. A broken build is:
halt the batch, leave the cluster as it is for the user to inspect, and
message them with the log excerpt and the score so far.

Post a status update after every batch, score first:
`Batch 3/9: 3 ✅ 1 ❌ 0 ⚠️. Cumulative 11 ✅ 1 ❌ 0 ⚠️.`

## Phase 4: Report

`TEST-RESULTS-v1.N.md` at the repo root, never staged. Header: date, build
image tag, install path, cluster context. Then one table:

| Example | Validates | Result | Evidence | Notes |
|---|---|---|---|---|
| `03-features/v1.11.0/02-multi-authorized-stages` | #6398 | ✅ | frontend, backend Succeeded; denied Errored "not authorized" | |

❌ rows carry expected vs observed. ⚠️ rows carry the reason. Below the
table: fixes made to existing examples, and their commit command.

Final message to the user: the score line, the ❌ list, the path to the
file.

## Common mistakes

| Mistake | Correction |
|---|---|
| Deriving features from release notes or a draft notes file | Merged PRs on `upstream/release-1.N`, falling back to `upstream/main`. |
| Designing examples before the user prunes the list | Phase 1 ends at the table. Stop. |
| Testing only the new version's examples | Every example in the repo, oldest first. |
| Applying everything at once, leaving namespaces up | Batches of four, cleanup between, wait for namespace deletion. |
| Results only in chat | `TEST-RESULTS-v1.N.md` at repo root, appended per batch. |
| `git add -A` or staging `00-common/kargo.yaml` | Explicit paths only. That file may have real keys. |
| `cat` or `git diff` on `00-common/kargo.yaml` | `git diff --stat` only. Reading it puts keys in the transcript. |
| `sed -i` on `<github-username>` | Pipe into `kubectl apply -f -`. |
| Writing a fleet/target-aware example | EE-only. Skip unless the user says otherwise. |
| Running against kind, docker-desktop, or a remote cluster | OrbStack only. Hard stop. |
| Re-deriving the feature list or rewriting examples on a resume | Reuse what earlier phases left behind. |
| Asking about leftover namespaces, unready pods, or a flaky step | Troubleshoot first. Two attempts before a question. |
| Assuming a Stage auto-promotes because the previous example's did | Read each example's `ProjectConfig`. `prod` is usually manual. |
| Hand-promoting a Stage that already auto-promotes | Duplicate Promotions. Check the policy first. |
| Reporting a PR, Promotion, or namespace that no tool result showed | Say what was observed. A rejected or timed-out command is reported as such. |
| `kubectl delete applications --all` in `argocd` | Delete by `kargo-demo-` name only. |
| Re-applying an example while its `kargo-demo-NN-<stage>` namespace is Terminating | Wait for delete on every `kargo-demo-*` namespace, destinations included. |
| Merging a PR on the user's fork without being told to | Ask once. `gh pr merge` only after a tool result shows the PR. |
| Marking a webhook example ⚠️ for want of a tunnel | Sign a synthetic payload and deliver it yourself. |
| Polls that run ten minutes with no word to the user | Under five minutes per poll, a status line between polls. |
| Leaving a 10m soak in place and waiting it out | Patch to 1m on the live Stage and note it. |
| Hardcoding the "newest" tag (`1.29.x`) in a new README | It moves. Select by origin and creation time. |
| A push-integration test that pushes its divergent commit before the next Promotion clones | Nothing diverges at push time. Manufacture the divergence inside the Promotion: a second clone commits and pushes first. |
| Bare `git commit -s` or an interactive commit | Heredoc command, explicit paths, `-s`. |
