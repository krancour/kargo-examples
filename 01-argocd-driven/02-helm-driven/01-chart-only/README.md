In this example, environment-specific Argo CD `Application` resources point
directly at a specific version of the `nginx` chart in the Bitnami Helm chart
repository. Kargo watches that repository for new versions of the `nginx` chart.

New versions of the chart are advanced from environment to environment by
updating the `targetRevision` field of each environment's corresponding Argo CD
`Application` resource.
