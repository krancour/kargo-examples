In this example, stage-specific Argo CD `Application` resources point at
corresponding, stage-specific branches of a Git repository. Kargo watches the
`kustomize` branch of that repository for new commits and also watches for new
versions of the `public.ecr.aws/nginx/nginx` container image.

New versions of the commit + image pair are advanced from stage to stage by
checking out the commit, running `kustomize edit set image` against the base
kustomize configuration, rendering a stage-specific kustomize overlay, and
committing the results to the head of the stage-specific branch.
