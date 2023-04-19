In this example, environment-specific Argo CD `Application` resources point at a
corresponding, environment-specific branch of a Git repository. Kargo watches
the `kustomize` branch of that repository for new commits and also watches the
`nginx` image repository on Docker Hub for new versions of the `nginx` image.

New versions of the commit + image pair are advanced from environment to
environment by checking out the commit, running `kustomize edit set image` in an
environment-specific path (Kustomize overlay), then committing the entire
working tree to the environment-specific branch.

Note that sourcing commits from one branch, but _making_ commits to another
branch prevents the formation of a loop.
