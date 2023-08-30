In this example, stage-specific Argo CD `Application` resources point directly
at a specific version of the `nginx` chart in the Bitnami Helm chart repository
_and_ mix in a specific version of the `nginx` container image from Docker Hub.
Kargo watches that image repository for new versions of the `nginx` image.

New versions of the image are advanced from stage to stage by updating
Helm-specific parameters of each stage's corresponding Argo CD `Application`
resource.
