# DevOps CI Assignment — Integration Test Pipeline
[![CI](https://github.com/5cr4b/devops-integration-test/actions/workflows/ci-integration-test.yml/badge.svg)](https://github.com/5cr4b/devops-integration-test/actions/workflows/ci-integration-test.yml)

## 0. Pre-Assessment Questionnaire

1. **CI platform:** GitHub Actions
2. **Cloud provider:** Azure (most fluent), GCP, AWS
3. **IaC tooling:** Terraform, plain scripts
4. **Zero-trust/private-access:** Cloudflare Tunnel, Azure Private Link
5. **Scripting language:** Bash, Python
6. **AI coding agents:** Yes — used for scaffolding and review

---

## 1. What This Pipeline Does

On every push and pull request, the pipeline:

1. **Packages** the workload as a container image (multi-stage Dockerfile)
2. **Pre-check** — lints, scans, and validates before any infrastructure is provisioned
3. **Provisions** a fresh Kind cluster with real PostgreSQL and Redis via Helm
4. **Runs** the workload as a Kubernetes Job — exit 0 = pass, non-zero = fail
5. **Publishes** the container image artifact + captured workload logs
6. **Tears down** the cluster reliably, including on failure and timeout

---

## 2. Architecture

```
push / PR
  │
  ▼
ci-integration-test.yml (caller)
  │
  ▼
reusable-kind-integration-ci.yml (reusable workflow)
  │
  ├── Pre-check ─── lint, SCA, SAST, shellcheck, helm lint
  │
  ├── Build ─────── docker build → save artifact
  │
  └── Integration ─ Kind cluster → PostgreSQL → Redis → Job → Collect → Cleanup
```

---

## 3. Repository Structure

```
.github/
├── actions/load-env/action.yml            # Composite action: loads .env.ci
└── workflows/
    ├── ci-integration-test.yml            # Caller workflow (triggers)
    ├── reusable-kind-integration-ci.yml   # Single reusable pipeline (all runner types)
    └── build-ci-tools-image.yml           # Snapshot runner builder
app/
├── Dockerfile                             # Multi-stage, non-root, OCI labels
├── main.py                                # Integration workload (write/read PG + Redis)
└── requirements.txt                       # psycopg, redis
helm/integration-test/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl                       # Reusable labels
    └── job.yaml                           # K8s Job with securityContext + resource limits
scripts/
├── cleanup.sh                             # Idempotent teardown with timeout + verification
└── collect-logs.sh                        # Captures kubectl state as artifacts
docs/architecture.md                       # Detailed design doc
.env.ci                                    # Non-secret CI config (versions, names, ports)
```

---

## 4. Design Decisions

### Why Kind?
- Fresh cluster per run (satisfies R3)
- No cloud credentials needed
- Fast enough for PR feedback (~2 min to provision)
- Easy local reproduction

### Why a single reusable workflow with `runner_type` input?
- Supports 3 runner strategies: `github-hosted`, `self-hosted`, `custom-image`
- Conditional `if:` skips setup actions when tools are pre-installed
- Zero duplication — one file to maintain

### Why a separate Helm chart for the Job?
- Keeps K8s manifest out of workflow YAML
- Enables `helm lint` + `helm template` in pre-check
- Values-based configuration for image, endpoints, credentials

### Why `.env.ci` instead of hardcoded workflow vars?
- Single source of truth for versions and names
- Shell-sourceable for local dev
- Composite action loads it dynamically — no manual output declarations

---

## 5. Caching Strategy

### Cached (speeds up repeat runs):
| What | How | Savings |
|------|-----|---------|
| Docker build layers | BuildKit GHA cache (`type=gha`) | ~30-60s |
| pip packages | `actions/setup-python` cache (github-hosted only) | ~15-20s |
| Kind node image | Pre-warmed in snapshot runner | ~40-60s |

### Deliberately NOT cached:
| What | Why |
|------|-----|
| PostgreSQL/Redis data | Must be fresh — tests validate real write/read |
| Kubernetes cluster state | R3 requires fresh cluster per run |
| Helm chart downloads | Cached chart could mask a security yank from upstream |

---

## 6. Pre-check (Fail-Fast)

Runs **before** any infrastructure is provisioned. If pre-check fails, no image is built, no cluster is created.

| Check | Tool | Purpose |
|-------|------|---------|
| Syntax | `py_compile` | Catches syntax errors |
| Lint | `ruff` | Code quality |
| SCA | `pip-audit` | Dependency vulnerabilities |
| SAST | `bandit` | Security issues in code |
| Shell | `shellcheck` | Script best practices |
| Helm | `helm lint` + `helm template` | Chart validity |

---

## 7. Teardown Strategy

Cleanup runs via `if: always()` — executes after success, failure, or step error.

**Improvements over basic cleanup:**
- `timeout` guard per command (prevents hung uninstalls from blocking)
- `--wait` on Helm uninstall (ensures resources are actually deleted)
- Verification that Kind cluster is gone after deletion
- `::group::` collapsible sections in GitHub Actions UI
- `::warning::` annotation when cleanup has partial errors
- Idempotent — handles missing releases, missing cluster, missing tools

---

## 8. Security Hardening

| Layer | What |
|-------|------|
| Container | Multi-stage build, non-root user (65532), no pip cache in runtime |
| Helm Job | `runAsNonRoot`, `readOnlyRootFilesystem`, `capabilities.drop: [ALL]`, resource limits |
| Workflow | `permissions: contents: read`, pinned action SHAs, `cancel-in-progress` |
| Scanning | Trivy (container CVEs), pip-audit (dependency SCA), bandit (SAST) |

---

## 9. Runner Types

The reusable workflow supports 3 runner strategies via the `runner_type` input:

| Type | Label | Tools pre-installed | Use case |
|------|-------|--------------------|----|
| `github-hosted` | `ubuntu-latest` | ❌ installs everything via actions | Default, no infra needed |
| `self-hosted` | configurable | ✅ kind, kubectl, helm, shellcheck | Team-managed runners |
| `custom-image` | `ci-integration-runner` | ✅ snapshot with cached node image | Fastest, requires Team/Enterprise |

---

## 10. Test Results

The workload signals only via exit code. "Test results" are:
- **Workload logs** captured from `kubectl logs` → uploaded as artifact
- **Job summary** rendered in GitHub Actions UI with cluster info + last 20 log lines
- **Cluster state** — `kubectl get all`, events, describe → uploaded as artifact

---
