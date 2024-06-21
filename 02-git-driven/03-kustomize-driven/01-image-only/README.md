In this example, stage-specific Argo CD `Application` resources point at a
specific branch of a Git repository (named `kustomize`). Kargo watches for new
versions of the `public.ecr.aws/nginx/nginx` container image.

New versions of the image are advanced from stage to stage by running `kustomize
edit set image` in an stage-specific path (Kustomize overlay) and committing
that change to the head of the `kustomize` branch.
