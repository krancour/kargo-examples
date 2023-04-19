In this example, environment-specific Argo CD `Application` resources point at a
specific commit from a Git repository. Kargo watches a specific branch of that
repository (named `kustomize`) for new commits.

New commits are advanced from environment to environment by updating the
`targetRevision` field of each environment's corresponding Argo CD `Application`
resource.

This example happens to use Kustomize to manage separate configurations for each
environment within a single branch, but the choice to use Kustomize is not of
any significant consequence for this example.
