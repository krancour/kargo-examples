In this example, stage-specific Argo CD `Application` resources point at
corresponding, stage-specific branches of a Git repository. Kargo watches the
`new-helm` branch of that repository for new commits and also watches for new
versions of the `public.ecr.aws/nginx/nginx` container image.

New versions of the commit + image pair are advanced from stage to stage by
checking out the commit, updating the default Helm values file, rendering the
Helm chart with a stage-specific Helm values file mixed in, and
committing the results to the head of the stage-specific branch.
