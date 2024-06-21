In this example, stage-specific Argo CD `Application` resources point at a
specific branch of a Git repository (named `helm`). Kargo watches for new
versions of the `public.ecr.aws/nginx/nginx` container image.

New versions of the image are advanced from stage to stage by updating an
stage-specific Helm values file and committing that change to the head of the
`helm` branch.
