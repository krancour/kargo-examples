In this example, stage-specific Argo CD `Application` resources point at
corresponding, stage-specific branches of a Git repository. Kargo watches for
new versions of the `public.ecr.aws/nginx/nginx` container image.

New versions of the image are advanced from stage to stage by cloning the git
repository, checking out the `new-helm` branch, updating the default Helm values
file, rendering the Helm chart with a stage-specific values file mixed in, and
committing the results to the head of the stage-specific branch.
