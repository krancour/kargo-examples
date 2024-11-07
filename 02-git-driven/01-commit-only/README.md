In this example, stage-specific Argo CD `Application` resources point at
corresponding, stage-specific branches of a Git repository. Kargo watches a
specific branch of that repository (named `kustomize`) for new commits.

New commits are advanced from stage to stage by copying select contents to the
head of the stage-specific branch.

This example happens to use Kustomize, but that choice is coincidental and not
of any particular significance.
