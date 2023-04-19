In this example, environment-specific Argo CD `Application` resources point at a
corresponding, environment-specific branch of a Git repository. Kargo watches
the `kustomize` branch of that repository for new commits

New commits are advanced from environment to environment by copying their
contents to the head of the the environment-specific branch.

This example happens to use Kustomize, but that choice is not of any significant
consequence for this example.
