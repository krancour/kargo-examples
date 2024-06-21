In this example, stage-specific Argo CD `Application` resources point at a
corresponding, stage-specific branch of a Git repository. Kargo watches the
`helm` branch of that repository for new commits and also watches for new
versions of the `public.ecr.aws/nginx/nginx` container image.

New versions of the commit + image pair are advanced from stage to stage by
checking out the commit, updating a stage-specific Helm values file, then
committing the entire working tree to the stage-specific branch.

Note that sourcing commits from one branch, but _making_ commits to another
branch prevents the formation of a loop.
