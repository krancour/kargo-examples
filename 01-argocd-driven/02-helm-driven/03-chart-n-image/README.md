In this example, environment-specific Argo CD `Application` resources point
directly at a specific version of the `nginx` chart in the Bitnami Helm chart
repository _and_ mix in a specific version of the `nginx` container image from
Docker Hub. Kargo watches the chart repository for new versions of the `nginx`
chart _and_ watches the image repository for new versions of the `nginx` image.

New chart + image pairs are advanced from environment to environment by updating
the `targetRevision` field _and_ Helm-specific parameters of each environment's
corresponding Argo CD `Application` resource.
