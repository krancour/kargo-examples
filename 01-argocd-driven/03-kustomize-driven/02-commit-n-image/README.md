In this example, stage-specific Argo CD `Application` resources point at a
specific commit from a Git repository _and_ mix in a specific version of the
`nginx` container image from Docker Hub. Kargo watches a specific branch of that
repository (named `kustomize`) for new commits _and_ watches the image
repository for new versions of the `nginx` image.

New commit + image pairs are advanced from stage to stage by updating the
`targetRevision` field _and_ Kustomize-specific parameters of each stage's
corresponding Argo CD `Application` resource.
