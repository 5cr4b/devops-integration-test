# Senior DevOps CI Assignment

## Overview

This repository implements a complete GitHub Actions CI pipeline for a Python integration workload. The workload runs inside Kubernetes and validates read/write behavior against PostgreSQL and Redis deployed into a fresh Kind cluster.

The application is intentionally small because the engineering focus is the delivery system around it:

- expose a thin repository workflow that calls a reusable CI workflow
- keep CI defaults in `.env.ci` instead of scattering values through YAML
- keep Kubernetes Job configuration in a local Helm chart
- fail fast before infrastructure provisioning
- build and preserve a deterministic container image artifact
- create isolated infrastructure for every run
- run the validation workload as a Kubernetes-native Job
- collect enough evidence to debug failures
- clean up resources even when the test path fails

## Architecture

```text
Developer Push
|
V
GitHub Actions
|
V
Caller Workflow: .github/workflows/ci.yml
|
V
Reusable Workflow: .github/workflows/reusable-kind-integration-ci.yml
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

More detail is available in [docs/architecture.md](docs/architecture.md).

## Questions I Would Ask Before Building This In Production

These are the questions I would ask before turning this assignment into a shared production CI pattern. The answers affect ownership, runtime targets, cost, and how much operational sophistication is justified.

### Developer Workflow

**Are integration tests written by developers or platform teams?**

This matters because developer-owned tests need simple local reproduction, clear templates, and fast feedback. Platform-owned tests can be more standardized, but they risk becoming disconnected from application behavior.

**What feedback time is considered acceptable?**

This determines whether every pull request should create a full cluster or whether some checks should move to nightly or merge-queue execution. A five-minute target leads to different tradeoffs than a thirty-minute target.

**Are tests expected to block merges?**

Blocking tests need low flake rates, clear failure messages, and strong ownership. Non-blocking tests can be broader and noisier, but they are less useful as release gates.

### Reliability

**Should failed environments be retained for debugging?**

Retention improves diagnosis but increases cost and leak risk. For this assignment I clean up aggressively because lifecycle guarantees are more important than interactive debugging.

**Should provisioning be retried automatically?**

Retries can hide transient infrastructure issues, but they can also mask real chart or image problems. I would only add retries around known flaky external calls and would keep final failure artifacts.

### Kubernetes

**Is cluster isolation the goal of the fresh-cluster requirement?**

If isolation is the core goal, Kind per run is appropriate. If the goal is production parity, a managed or long-lived test cluster with namespace isolation may be more representative.

**Is production parity more important than speed?**

Kind is fast and cheap, but it does not model managed load balancers, cloud IAM, storage classes, or node behavior perfectly. That is acceptable for this workload, but not for every production validation.

### Scale

**How would this design evolve for hundreds of repositories?**

Copying workflow YAML into hundreds of repositories creates drift. At that scale, I would move the pattern into reusable workflows, shared templates, and centrally maintained actions.

**Would a shared platform be preferable?**

A shared platform can provide standard CI clusters, policy, secrets, artifact handling, and observability. It is more expensive to build, but it reduces repeated work and improves governance.

## Assumptions

- PostgreSQL and Redis are sufficient stand-ins for external dependencies in this assignment.
- Kind is acceptable in CI and Docker-in-Docker is not required on GitHub-hosted Ubuntu runners.
- Pipeline runtime and reproducibility are more important than exact production parity.
- The assignment values cleanup guarantees more than retaining live failed environments.
- Fixed demo credentials are acceptable because all resources are ephemeral and isolated to CI.
- Registry push is intentionally out of scope, so the Docker image is exported as `app-image.tar`.
- The default namespace is acceptable for a single-use ephemeral cluster.
- GitHub Actions hosted runners provide enough CPU and memory for one Kind cluster plus PostgreSQL and Redis.

## Design Decisions

### CI Platform: GitHub Actions

**Alternatives considered:** GitLab CI, Jenkins, CircleCI, Buildkite.

**Pros:**

- Native `push` and `pull_request` triggers.
- Built-in artifact handling.
- First-class Docker layer cache and pip cache support.
- Low setup cost for reviewers.

**Cons:**

- Hosted runners are less controllable than dedicated CI workers.
- Advanced orchestration can become verbose in YAML.
- Cancellation and runner-loss behavior still depend on the CI platform.

**Final reasoning:**

GitHub Actions is the requested platform and is sufficient for the assignment. The repository uses a thin caller workflow, [.github/workflows/ci.yml](.github/workflows/ci.yml), which delegates to [.github/workflows/reusable-kind-integration-ci.yml](.github/workflows/reusable-kind-integration-ci.yml). That keeps the trigger surface small while making the implementation reusable for other repositories.

### Workflow Reuse: Thin Caller Plus Reusable Workflow

**Alternatives considered:** one monolithic workflow file, composite actions, external shared workflow repository.

**Pros:**

- Demonstrates the same pattern an organization can use across repositories.
- Keeps `push`, `pull_request`, and manual failure inputs in the caller workflow.
- Centralizes CI lifecycle logic in one reusable implementation.
- Makes future migration to an organization-level shared workflow straightforward.

**Cons:**

- Adds one more workflow file for a small repository.
- Local reusable workflows are still versioned with the repository, not centrally released.
- Some GitHub Actions behavior is less obvious when jobs are hidden behind `workflow_call`.

**Final reasoning:**

For a take-home assignment, a local reusable workflow is the right middle ground. It demonstrates scale-oriented design without introducing an external template repository that reviewers cannot inspect in the same codebase.

### CI Configuration: `.env.ci`

**Alternatives considered:** workflow-level `env`, repository variables, GitHub Secrets, hardcoded shell commands.

**Pros:**

- Keeps non-secret CI defaults in one reviewable file.
- Makes local reproduction easier because shell commands and workflows can source the same values.
- Avoids repeating service names, chart versions, and tool versions throughout the workflow.

**Cons:**

- GitHub Actions cannot use `$GITHUB_ENV` directly for every expression, so the workflow has a small `load-config` job for action inputs.
- `.env.ci` is not a secret store and should not contain production credentials.

**Final reasoning:**

The values in [.env.ci](.env.ci) are non-secret defaults for an ephemeral CI environment. Centralizing them improves maintainability without adding a configuration service or secret manager that would be excessive for this assignment.

### Kubernetes: Kind Instead Of AKS/EKS/GKE

**Alternatives considered:** AKS, EKS, GKE, k3d, minikube, shared long-lived cluster.

**Pros:**

- Creates a fresh Kubernetes cluster per run.
- Avoids cloud credentials and managed cluster lifecycle cost.
- Fast enough for pull request feedback.
- Easy to reproduce locally with Docker.

**Cons:**

- Lower production parity than managed Kubernetes.
- Does not exercise cloud IAM, storage classes, ingress controllers, or managed control-plane behavior.
- Runner resources limit how large the test environment can become.

**Final reasoning:**

The assignment asks for no managed Kubernetes services and values fresh environments. Kind is the simplest tool that satisfies those requirements while keeping cost and reviewer setup low.

### Deployment: Helm Charts

**Alternatives considered:** raw Kubernetes manifests, Kustomize, Docker Compose outside Kubernetes, custom operators.

**Pros:**

- Bitnami charts are maintained and widely used.
- `helm upgrade --install --wait` gives a practical readiness boundary.
- Release names make cleanup straightforward.
- Chart values let persistence be disabled cleanly for ephemeral CI.

**Cons:**

- Helm chart behavior can change if chart versions are not pinned.
- Generic charts expose more configuration than this assignment needs.
- Debugging chart templates can be harder than debugging small manifests.

**Final reasoning:**

The assignment explicitly requires Bitnami PostgreSQL and Redis charts. Helm reduces implementation risk and keeps the reviewer focused on CI lifecycle design rather than hand-written database manifests.

### Integration Job Packaging: Local Helm Chart

**Alternatives considered:** inline YAML in the workflow, raw manifest checked into `k8s/`, Kustomize, a full application chart.

**Pros:**

- Keeps Kubernetes resource structure out of the workflow body.
- Gives values-based configuration for image, service endpoints, and `FORCE_FAIL`.
- Lets pre-check validate the chart with `helm lint` and `helm template`.
- Matches how teams commonly package Kubernetes workloads.

**Cons:**

- Adds a small chart directory for a single Job.
- Helm templating can be harder to read than plain YAML for very small resources.

**Final reasoning:**

The chart under [helm/integration-test](helm/integration-test) is small but makes the pipeline cleaner and easier to evolve. The workflow orchestrates lifecycle; Helm owns Kubernetes object rendering.

### Test Execution: Kubernetes Job

**Alternatives considered:** running the container directly with `docker run`, running a shell command from the runner, using a long-lived test pod.

**Pros:**

- Executes the workload from inside the same Kubernetes network as PostgreSQL and Redis.
- Provides a Kubernetes-native success/failure signal.
- Captures logs through standard `kubectl logs`.
- Models how batch validation tasks commonly run in clusters.

**Cons:**

- More YAML than a direct `docker run`.
- Requires Job status polling logic.
- Debugging can require Kubernetes knowledge.

**Final reasoning:**

The Job is the right abstraction because the system under test is the Kubernetes-deployed environment, not just the Python code. Running inside Kubernetes validates service discovery and in-cluster connectivity.

## Fail-Fast Philosophy

Cheap failures should happen before expensive operations.

The `pre-check` job runs before image builds and before any Kubernetes infrastructure exists. It performs:

- Python syntax validation with `py_compile`
- Ruff linting
- Dependency vulnerability scan with `pip-audit` (SCA)
- Security scan with `bandit` (SAST)
- Shell script validation with `shellcheck`
- Helm chart lint and template validation

The `build` job depends on `pre-check`, and the `integration` job depends on `build`. If syntax or linting fails, Kind is never installed and no cluster is created. This protects reviewer time, reduces CI cost, and avoids creating resources for defects that can be detected locally in seconds.

## Reliability Strategy

### Cleanup Guarantees

The workflow uses `if: always()` for artifact collection, artifact upload, and cleanup. Cleanup is intended to execute after:

- success
- failure
- cancellation once the runner continues cleanup handling
- non-zero exit codes from provisioning or test steps

Cleanup removes:

- Integration test Helm release
- PostgreSQL Helm release
- Redis Helm release
- Kind cluster

Resource leaks are dangerous because they hide real pipeline cost, consume runner resources, interfere with later runs, and create confusing debugging signals. Even though Kind runs locally on the CI runner, cleanup still matters because leaked clusters can leave containers, networks, and volumes behind during a job.

The cleanup script is idempotent and tolerates partial infrastructure. If the cluster was never created, it skips Helm cleanup and still asks Kind to delete the cluster by name. If a Helm release is missing, `--ignore-not-found` prevents cleanup from masking the original failure.

### Failure Scenarios

**1. PostgreSQL deployment failure**

Expected behavior: the PostgreSQL Helm install exits non-zero. The integration Job is not created. Artifact collection still captures cluster state and events if the cluster exists. Cleanup then removes any partial PostgreSQL release and deletes the Kind cluster.

**2. Redis deployment failure**

Expected behavior: PostgreSQL may already exist, but Redis deployment exits non-zero. Artifact collection captures the state of both components. Cleanup removes both Helm releases and deletes the Kind cluster.

**3. Integration test failure**

Expected behavior: the Kubernetes Job reaches a failed condition because the workload exits non-zero. CI prints Job logs, collects artifacts, uploads them, and then destroys the infrastructure. The workflow fails, which is correct because the validation failed.

**4. Kubernetes Job failure or timeout**

Expected behavior: the workflow actively checks for both `Complete` and `Failed` Job conditions. A failed Job fails quickly instead of waiting for the full timeout. If no terminal condition appears in time, CI describes the Job, attempts to print logs, collects artifacts, and cleans up.

### Intentional Failure Run

The workflow supports `workflow_dispatch` with `force_fail=true`. That sets `FORCE_FAIL=true` in the Kubernetes Job, causing the application to exit with code `1`.

The purpose is not to test the application. The purpose is to prove that the failure path still collects evidence and executes cleanup.

## Developer Experience Considerations

### Fast Feedback

Kind was chosen because it gives a real Kubernetes API without waiting for cloud cluster provisioning. The pipeline also separates pre-check, build, and integration phases so developers see syntax and lint failures quickly.

### Debugging Support

Failures should provide evidence without requiring immediate reruns. The pipeline collects:

- integration test logs
- Job description
- `kubectl get all`
- Kubernetes events
- `kubectl describe all`

This is enough to distinguish common failure classes: image load problems, chart readiness issues, service discovery failures, container crashes, and test assertion failures.

### Artifacts

The Docker image is exported as `app-image.tar` so the exact tested image is available from the pipeline. Runtime artifacts are uploaded separately so reviewers can inspect both the input image and the cluster evidence.

### Custom CI Tools Image

Using a custom CI tools image can be a good optimization when the same pipeline runs frequently. Pre-installing `kind`, `kubectl`, `helm`, Docker CLI, Python, and linting tools can reduce setup time and make tool versions more consistent.

The tradeoff is that the image becomes another artifact to patch and govern. It should be rebuilt regularly, scanned, and versioned. For this repository, [.github/workflows/build-ci-tools-image.yml](.github/workflows/build-ci-tools-image.yml) builds a `ci-tools:snapshot` image and uploads `ci-tools-image.tar`. The main CI still uses pinned marketplace setup actions because that is simpler on GitHub-hosted runners, while the snapshot workflow demonstrates the path to faster self-hosted or organization-wide execution.

## Caching Strategy

Cached:

- pip packages through `actions/setup-python`
- Docker build layers through Docker Buildx GitHub Actions cache
- optional CI tools image layers in the snapshot workflow

Not cached:

- PostgreSQL data
- Redis data
- Kubernetes cluster state
- integration test state

The workload validates infrastructure behavior, so service data and cluster state must be fresh each run. Caching only build inputs keeps the pipeline faster without weakening test isolation.

## Cost Considerations

Kind is cheaper and faster than AKS, EKS, or GKE for this kind of CI integration testing because it runs on the existing CI runner and does not require:

- cloud cluster provisioning time
- cloud control-plane cost
- node group lifecycle management
- cloud IAM setup for the take-home environment
- cleanup of external cloud resources

Managed Kubernetes would be appropriate when the test must validate cloud-specific behavior. For this assignment, the cost and operational overhead would distract from the core CI/CD lifecycle.

## Tradeoffs Made Under the 4-Hour Constraint

**Chose:** Bitnami Helm charts  
**Instead of:** custom PostgreSQL and Redis manifests  
**Reason:** reduced implementation effort, improved reliability, and kept reviewer focus on pipeline design.

**Chose:** Kind per run  
**Instead of:** namespace isolation in a shared cluster  
**Reason:** directly satisfies the fresh-cluster requirement and avoids hidden persistent state.

**Chose:** reusable workflow called by a thin `ci.yml`  
**Instead of:** one monolithic workflow file  
**Reason:** demonstrates a scalable pattern while keeping the repository self-contained for review.

**Chose:** local Helm chart for the integration Job  
**Instead of:** embedding Kubernetes YAML inside the workflow  
**Reason:** keeps the pipeline focused on orchestration and makes Job configuration easier to review and reuse.

**Chose:** `.env.ci` plus a small config-loading job  
**Instead of:** workflow-level hardcoded environment variables  
**Reason:** centralizes non-secret configuration while still supporting GitHub Actions expressions for action inputs.

**Chose:** marketplace setup actions pinned by SHA  
**Instead of:** custom install scripts for Kind, Helm, and kubectl  
**Reason:** reduces custom bash, improves supply-chain reviewability, and makes tool setup behavior easier for reviewers to recognize.

**Chose:** fixed ephemeral credentials  
**Instead of:** GitHub Secrets  
**Reason:** credentials only protect disposable local services inside an ephemeral CI cluster. Secrets would be required for shared or production-like environments.

**Chose:** collect broad `kubectl describe all` output  
**Instead of:** highly curated diagnostics  
**Reason:** broad diagnostics are faster to implement and useful during review. A mature platform should structure diagnostics by component.

## Security Considerations

This assignment keeps security controls practical rather than pretending an ephemeral CI demo is production. Future improvements:

- store real credentials in GitHub Secrets or a secret manager
- use workload identity for cloud access instead of static credentials
- scan container images for vulnerabilities
- generate SBOMs for built images
- sign container images and verify signatures before deployment
- keep Helm chart versions pinned and update them intentionally
- use stricter Kubernetes security contexts and read-only filesystems
- scope GitHub Actions permissions to the minimum required, as this workflow does with `contents: read`

## How I Would Evolve This Design

Current state: a single repository owns a thin caller workflow, a reusable workflow, a local Helm chart, minimal scripts, and documentation.

For an organization-wide platform, I would evolve this into:

- reusable GitHub Actions workflows published from a central platform repository
- shared CI templates with versioned rollout and changelogs
- internal Helm repositories or approved chart mirrors
- a published and scanned CI tools image for self-hosted runners
- platform APIs for requesting ephemeral test environments
- golden pipelines with standard logging, timeouts, retries, and cleanup behavior
- centralized dashboards for pass rate, duration, flake rate, and cleanup failures
- policy checks for image signing, SBOMs, and secret usage

The important shift is from copy/paste YAML to a maintained product. At scale, developer experience depends on stable interfaces, clear ownership, and safe defaults.

## Running Locally

Prerequisites:

- Docker
- kubectl
- Helm
- Kind

Example local flow:

```bash
docker build -t integration-workload:ci app
kind create cluster --name ci-cluster --wait 120s
kind load docker-image integration-workload:ci --name ci-cluster
set -a
. ./.env.ci
set +a
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install "${POSTGRES_RELEASE_NAME}" bitnami/postgresql \
  --version "${POSTGRES_CHART_VERSION}" \
  --set auth.database="${POSTGRES_DB}" \
  --set auth.username="${POSTGRES_USER}" \
  --set auth.password="${POSTGRES_PASSWORD}" \
  --set primary.persistence.enabled=false \
  --wait
helm upgrade --install "${REDIS_RELEASE_NAME}" bitnami/redis \
  --version "${REDIS_CHART_VERSION}" \
  --set architecture=standalone \
  --set auth.password="${REDIS_PASSWORD}" \
  --set master.persistence.enabled=false \
  --wait
helm upgrade --install "${JOB_RELEASE_NAME}" helm/integration-test \
  --set image.repository=integration-workload \
  --set image.tag=ci
```

Then create the same Job used by the reusable workflow, or run the workflow in GitHub Actions. When finished:

```bash
scripts/collect-logs.sh
scripts/cleanup.sh
```

## Pipeline Evidence

Record workflow links here after pushing the repository:

| Run | Expected Result | Link |
| --- | --- | --- |
| Successful run 1 | Pass | TODO |
| Successful run 2 | Pass | TODO |
| Successful run 3 | Pass | TODO |
| Intentional failure with `force_fail=true` | Fail after test Job, collect artifacts, then cleanup | TODO |

## Time Log

Approximate effort:

- Repository scaffolding and Python workload: 35 minutes
- CI workflows, Helm chart, and scripts: 110 minutes
- Artifact collection and cleanup behavior: 35 minutes
- Documentation and review pass: 60 minutes

Total: about 3.5 hours.
