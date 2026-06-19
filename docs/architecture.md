# Architecture

## Pipeline Flow

```
Developer Push / PR
│
▼
ci-integration-test.yml (caller)
│  - triggers: push, pull_request, workflow_dispatch
│  - inputs: force_fail, runner_type
│
▼
reusable-kind-integration-ci.yml
│  - inputs: force_fail, runner_type, runner_label
│  - conditional setup based on runner_type
│
├── Job: pre-check
│   ├── Load .env.ci (composite action)
│   ├── [github-hosted only] setup-python, setup-helm
│   ├── Install pip tools (ruff, bandit, pip-audit)
│   ├── Python syntax check
│   ├── Ruff lint
│   ├── pip-audit (SCA)
│   ├── bandit (SAST)
│   ├── shellcheck
│   └── Helm lint + template
│
├── Job: build (needs: pre-check)
│   ├── Docker Buildx + GHA layer cache
│   ├── [github-hosted only] Trivy vulnerability scan
│   ├── docker save → app-image.tar
│   └── Upload artifact
│
└── Job: integration (needs: build)
    ├── Download image artifact
    ├── [github-hosted] kind-action / [others] kind create cluster
    ├── Load image into Kind
    ├── Deploy PostgreSQL (Bitnami Helm chart)
    ├── Deploy Redis (Bitnami Helm chart)
    ├── Run integration test Job (Helm chart)
    ├── Poll Job status (Complete/Failed/Timeout)
    ├── [always] Print logs
    ├── [always] Collect artifacts (scripts/collect-logs.sh)
    ├── [always] Upload artifacts
    ├── [always] Cleanup (scripts/cleanup.sh)
    └── [always] Write job summary
```

## Runner Type Resolution

The `runs-on` expression resolves based on `inputs.runner_type`:

```
github-hosted  → ubuntu-latest (installs all tools via actions)
self-hosted    → inputs.runner_label (tools pre-installed by admin)
custom-image   → ci-integration-runner (snapshot with cached Kind node image)
```

## Configuration Model

All non-secret CI defaults live in `.env.ci`. A composite action (`.github/actions/load-env`) loads them into `GITHUB_ENV` for each job. No manual output declarations needed — adding a variable to `.env.ci` makes it available everywhere automatically.

## Lifecycle Boundaries

- **Pre-check failure** → no image build, no cluster
- **Build failure** → no cluster
- **Provisioning failure** → collect what's available, cleanup
- **Workload failure** → print logs, collect artifacts, cleanup
- **Timeout** → describe job, collect what's possible, cleanup

## Cleanup Model

`scripts/cleanup.sh` features:
- Timeout guard per command (default 60s)
- `--wait` on Helm uninstall
- Verification that cluster is deleted
- `::group::` collapsible output in Actions UI
- `::warning::` annotation on partial failure
- Idempotent — safe to run when resources don't exist

## Artifacts Produced

| Artifact | Contents | Retention |
|----------|----------|-----------|
| `app-image` | Docker image tarball | 7 days |
| `integration-artifacts` | kubectl-get-all.txt, events, describe, job logs | 14 days |

## Snapshot Runner (build-ci-tools-image.yml)

Pre-installs static tools that rarely change:
- kind, kubectl, helm, shellcheck
- Pre-warms Kind node image (docker pull + create/delete cluster)

Does NOT pre-install (volatile, changes with app):
- Python packages (ruff, bandit, pip-audit, app deps)
- Bitnami chart versions
- App-specific dependencies
