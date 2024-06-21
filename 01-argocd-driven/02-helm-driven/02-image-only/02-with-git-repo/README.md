In this example, stage-specific Argo CD `Application` resources point at a
specific branch of a Git repository (named `helm`) _and_ mix in a specific
version of the `public.ecr.aws/nginx/nginx` container image. Kargo watches for
new versions of the `public.ecr.aws/nginx/nginx` image.

New versions of the image are advanced from stage to stage by updating
Helm-specific parameters of each stage's corresponding Argo CD `Application`
resource.
