# Kargo Examples

This is a library of carefully annotated Kargo examples.

See `README.md` files in each directory for more information about individual
examples.

These examples all complement an example application GitOps repository found at
[https://github.com/krancour/kargo-demo-gitops](https://github.com/krancour/kargo-demo-gitops).

You should fork that repo, and when doing so, _uncheck the `Copy the main branch
only` option_. There is no need for you to clone that repository on your local
machine. (You only need to clone _this_ repository.)

> ⚠️&nbsp;&nbsp;_Anywhere_ in these manifests that you see:
>
> * `<github-username>`, replace it with your own GitHub handle.
>
> * `<github-pat>`, replace it with a GitHub personal access token capable of
>   reading _and writing_ to your fork.
>
> * `<dockerhub-username>`, replace it with your Docker Hub handle.
>
> * `<dockerhub-pat>`, replace it with a Docker Hub personal access token with
>   read-only permissions.
>
> It is best to utilize your favorite text editor's search-and-replace feature
> to carry out these substitutions.

All examples are broken into two sets of manifests, with one named `argocd.yaml`
and the other named `kargo.yaml`. The former should be applied first, followed
by the latter. The point of this separation is to make clear which aspects of
each example are _not_ novel or Kargo-specific and which are.
