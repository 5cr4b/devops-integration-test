# Architecture

## Pipeline Flow

```text
Developer Push
|
V
GitHub Actions
|
V
Caller Workflow
|
V
Reusable Workflow
|
V
Pre-check
|
V
Build Container Image
|
V
Create Kind Cluster
|
+------ PostgreSQL
|
+------ Redis
|
V
Integration Test Job
|
V
Collect Logs
|
V
Upload Artifacts
|
V
Cleanup (Always)
```

The diagram highlights the infrastructure lifecycle because that is the primary reliability concern.

## Workflow Structure

The repository uses two workflow files:

- `.github/workflows/ci.yml`: trigger-facing caller workflow for `push`, `pull_request`, and `workflow_dispatch`.
- `.github/workflows/reusable-kind-integration-ci.yml`: reusable workflow containing pre-check, build, provisioning, test, artifact collection, and cleanup jobs.
- `.github/workflows/build-ci-tools-image.yml`: manual workflow that builds a reusable CI tools image snapshot for future self-hosted or shared-runner optimization.

This keeps repository-specific triggers and inputs separate from the reusable implementation. In a larger organization, the reusable workflow could move to a central platform repository and be consumed by many application repositories.

## Configuration Model

Non-secret CI defaults live in `.env.ci`. The reusable workflow has a small `load-config` job that exposes selected values as job outputs for action inputs, then each execution job loads the same file into shell environment variables.

This avoids scattering service names, chart versions, and tool versions throughout YAML while keeping production secrets out of the repository.

## Lifecycle Boundaries

The reusable pipeline separates cheap validation, build work, infrastructure provisioning, test execution, diagnostics, and cleanup:

- `pre-check`: Python syntax, Ruff linting, pip-audit (SCA), Bandit (SAST), ShellCheck, and Helm chart validation.
- `build`: container image build, Docker layer cache use, and `app-image.tar` export.
- `integration`: Kind cluster creation, Helm deployments, Helm-rendered Kubernetes Job execution, artifact collection, and cleanup.

This separation is intentional. A syntax failure should not create infrastructure. A test failure should preserve evidence. Cleanup should not depend on the test succeeding.

## Runtime Topology

The Kind cluster is created fresh for every workflow run. PostgreSQL and Redis are installed into the default namespace using Bitnami Helm charts with persistence disabled.

The integration workload is packaged as a local Helm chart under `helm/integration-test` and runs as a Kubernetes Job inside the cluster. It connects to:

- `postgresql.default.svc.cluster.local:5432`
- `redis-master.default.svc.cluster.local:6379`

The Job writes and reads `test-key=test-value` through both services. If either validation fails, the workload exits with code `1` and the workflow fails.

## Failure Behavior

The expected behavior is explicit:

- Pre-check failure: no image build, no cluster creation.
- Build failure: no cluster creation.
- PostgreSQL failure: collect cluster state if available, then cleanup.
- Redis failure: collect state for PostgreSQL and Redis, then cleanup.
- Job failure: print logs, collect artifacts, upload artifacts, then cleanup.
- Timeout: describe the Job, attempt to collect logs, upload artifacts, then cleanup.

## Artifact Outputs

Artifacts are written under `artifacts/` and uploaded by GitHub Actions:

- `integration-test.log`
- `job-describe.txt`
- `kubectl-get-all.txt`
- `kubectl-get-events.txt`
- `kubectl-describe-all.txt`

The Docker image is exported separately as `app-image.tar`. This makes the tested workload available even when the runtime environment has been destroyed.

## Cleanup Model

Cleanup is implemented as the final integration job step with `if: always()`. The cleanup script removes the integration test, PostgreSQL, and Redis Helm releases first, then deletes the Kind cluster.

The script is designed for partial failure:

- If the cluster was never created, Helm cleanup is skipped.
- If a release is absent, Helm ignores it.
- Kind delete is still attempted by cluster name.

This keeps the original failure visible while still making best effort to remove all resources.
