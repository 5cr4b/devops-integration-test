# Next Steps

## Immediate Improvements

- Add a `Makefile` with `make precheck`, `make build`, `make local-ci`, and `make cleanup`.
- ~~Add ShellCheck to catch script issues beyond `bash -n`.~~ **Done** — replaced `bash -n` with `shellcheck` in pre-check.
- Pin Bitnami chart versions after validating compatibility and documenting the upgrade process.
- ~~Add a GitHub Actions job summary with key timings, artifact links, and cleanup status.~~ **Done** — added `Write job summary` step with `GITHUB_STEP_SUMMARY`.
- Move the reusable workflow into a central platform repository once multiple services consume it.
- Publish the CI tools image snapshot to an internal registry after adding scanning and lifecycle ownership.

## Production Hardening Ideas

- Use a dedicated namespace per run, even inside a fresh cluster, to make ownership clearer.
- ~~Add resource requests and limits for PostgreSQL, Redis, and the test Job.~~ **Done** — added to Helm Job template.
- Add explicit retry policy only around known transient operations, not around deterministic test failures.
- Add structured diagnostics by component so failures are faster to inspect.
- Add a cleanup failure alert if this pattern becomes a shared platform capability.

## Security Enhancements

- Store non-demo credentials in GitHub Secrets or an external secret manager.
- Use workload identity for any cloud access instead of static credentials.
- ~~Add image vulnerability scanning before running integration tests.~~ **Done** — added Trivy scan in build job.
- Generate SBOMs for built images.
- Sign container images and verify signatures before deployment.
- ~~Run the test workload with a stricter pod security context and read-only root filesystem.~~ **Done** — added `securityContext` to Helm Job.
- Mirror or approve third-party Helm charts before organization-wide use.

## Scalability Enhancements

- Publish the reusable GitHub Actions workflow with semantic version tags.
- Provide organization-level golden pipeline templates that call the reusable workflow.
- Add an internal Helm repository for approved dependency charts.
- Add an internal container registry for approved CI tools images.
- Add a platform API for requesting ephemeral test environments.
- Track pass rate, duration, flake rate, and cleanup failure rate centrally.
- Split larger integration suites into multiple Jobs or test shards once runtime becomes a bottleneck.

## Monitoring Ideas

- Publish stage durations and readiness timings.
- Capture pod termination reasons and Kubernetes events as structured JSON.
- Emit metrics for cleanup success and failure.
- Track intentional failure runs separately from product failures.
- Add trend reporting for CI cost and runtime as repository count grows.
