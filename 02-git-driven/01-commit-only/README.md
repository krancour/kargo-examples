In this example, stage-specific Argo CD `Application` resources point at a
corresponding, stage-specific branch of a Git repository. Kargo watches a specific branch of that
repository (named `commit-only`) for new commits.

New commits are advanced from stage to stage by copying their contents to the
head of the the stage-specific branch.

This example happens to use Kustomize, but that choice is not of any significant
consequence for this example.
