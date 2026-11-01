# Publish documentation

The development site is hosted at
[Unaru documentation](https://ankitgoyalio.github.io/unaru/).
It documents the current `main` branch.

The CI workflow builds and validates DocC on pull requests and pushes. On `main`,
deployment waits for both Apple and Ubuntu checks. GitHub Pages uses the Actions
build source and the `github-pages` environment. Deployment needs `pages: write`
and `id-token: write` permissions.

The artifact contains a landing page and separate Shared, Backend, and app
documentation under the repository's `/unaru` URL prefix. It has no custom domain.

After deployment, CI checks the published landing page, module routes, and render
data. To repeat the check locally:

```fish
python3 Scripts/check-documentation-live.py https://ankitgoyalio.github.io/unaru/
```

If publication fails, inspect the CI build, deployment, and live-check logs.
A passing local build establishes artifact validity, not successful publication.
