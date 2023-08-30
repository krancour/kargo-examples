In this example, stage-specific Argo CD `Application` resources point at a
corresponding, stage-specific branch of a Git repository. Kargo watches the
`kustomize` branch of that repository for new commits and also watches the
`nginx` image repository on Docker Hub for new versions of the `nginx` image.

New versions of the commit + image pair are advanced from stage to stage by
checking out the commit, running `kustomize edit set image` in an stage-specific
path (Kustomize overlay), then committing the entire working tree to the
stage-specific branch.

Note that sourcing commits from one branch, but _making_ commits to another
branch prevents the formation of a loop.
