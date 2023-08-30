In this example, stage-specific Argo CD `Application` resources point at a
specific branch of a Git repository (named `helm`). Kargo watches the `nginx`
image repository on Docker Hub for new versions of the `nginx` image.

New versions of the image are advanced from stage to stage by updating an
stage-specific Helm values file and committing that change to the head of the
`helm` branch.
