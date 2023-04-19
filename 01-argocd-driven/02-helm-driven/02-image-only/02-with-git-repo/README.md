In this example, environment-specific Argo CD `Application` resources point at a
specific branch of a Git repository (named `helm`) _and_ mix in a specific
version of the `nginx` container image from Docker Hub. Kargo watches that image
repository for new versions of the `nginx` image.

New versions of the image are advanced from environment to environment by
updating Helm-specific parameters of each environment's corresponding Argo CD
`Application` resource.
