In this example, stage-specific Argo CD `Application` resources point directly
at a specific version of the `nginx` chart in the Bitnami Helm chart repository.
Kargo watches that repository for new versions of the `nginx` chart.

New versions of the chart are advanced from stage to stage by updating the
`targetRevision` field of each stage's corresponding Argo CD `Application`
resource.
