In this example, stage-specific Argo CD `Application` resources point at a
specific commit from a Git repository _and_ mix in a specific version of the
`public.ecr.aws/nginx/nginx` container image. Kargo watches a specific branch of
that repository (named `helm`) for new commits _and_ watches for new versions of
the `public.ecr.aws/nginx/nginx` image.

New commit + image pairs are advanced from stage to stage by updating the
`targetRevision` field _and_ Helm-specific parameters of each stage's
corresponding Argo CD `Application` resource.
