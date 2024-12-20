This example depicts something I don't personally recommend, although it seems
to be a popular approach among users.

In this example, stage-specific Argo CD `Application` resources for _twenty
different applications_ point at a single branch of a Git repository. Kargo
watches for new versions of the `public.ecr.aws/nginx/nginx` container image.

For all twenty applications, new versions of the image are advanced from stage
to stage by cloning the git repository, checking out the `monorepo` branch,
running `kustomize edit set image` against an app-and-stage-specific Kustomize
overlay, and committing the results to the head of the `monorepo` branch.

What I do not like about this approach is that with all changes written to the
head of the same branch, and with all sixty `Application` resources pointing at
the head of that one branch, it is not possible for each stage's health checks
to factor in whether _each_ underlying `Application` is synced to the correct
commit. (Because if they were to do so, only one in sixty stages could ever be
healthy at any given moment.) Many users seem not to care about this limitation,
but for this reason, I find it vastly preferable that no two stages' promotion
processes write to the same branch. By doing so, the possibility of conflicts
upon push could also be reduced. i.e. Stage-specific branches impart some
tangible advantages and they are a sensible option that ought not be overlooked.

Despite my reservations about the approach used in this example, since it is a
popular approach nevertheless, this example helps to validate it. In particular,
it validates that health checks for multiple stages _not_ factoring in revision
information can simultaneously report as healthy. Because concurrent promotion
processes will also race to push to the head of a single branch, this example
also helps to validate the `argocd-update` promotion step's automatic conflict
resolution.
