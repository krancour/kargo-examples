In this example, stage-specific Argo CD `Application` resources point at
specific versions of the `nginx` chart in the Bitnami Helm chart repository
_and_ mix in specific versions of the `public.ecr.aws/nginx/nginx` container
image. Kargo watches the chart repository for new versions of the `nginx` chart
_and_ watches for new versions of the `public.ecr.aws/nginx/nginx` image.

New chart + image pairs are advanced from stage to stage by updating the
`targetRevision` field _and_ Helm-specific parameters of each stage's
corresponding Argo CD `Application` resource.
