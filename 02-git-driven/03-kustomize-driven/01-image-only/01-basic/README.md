In this example, stage-specific Argo CD `Application` resources point at
corresponding, stage-specific branches of a Git repository. Kargo watches for
new versions of the `public.ecr.aws/nginx/nginx` container image.

New versions of the image are advanced from stage to stage by cloning the git
repository, checking out the `kustomize` branch, running
`kustomize edit set image` against the base kustomize configuration, rendering a
stage-specific kustomize overlay, and committing the results to the head of the
stage-specific branch.
