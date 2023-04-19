In this example, environment-specific Argo CD `Application` resources point at a
specific commit from a Git repository _and_ mix in a specific version of the
`nginx` container image from Docker Hub. Kargo watches a specific branch of that
repository (named `helm`) for new commits _and_ watches the image repository
for new versions of the `nginx` image.

New commit + image pairs are advanced from environment to environment by
updating the `targetRevision` field _and_ Helm-specific parameters of each
environment's corresponding Argo CD `Application` resource.
