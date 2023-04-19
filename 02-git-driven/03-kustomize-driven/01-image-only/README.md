In this example, environment-specific Argo CD `Application` resources point at a
specific branch of a Git repository (named `kustomize`). Kargo watches the
`nginx` image repository on Docker Hub for new versions of the `nginx` image.

New versions of the image are advanced from environment to environment by
running `kustomize edit set image` in an environment-specific path (Kustomize
overlay) and committing that change to the head of the `kustomize` branch.
