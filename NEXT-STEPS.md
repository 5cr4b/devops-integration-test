# Next Steps

## Immediate
- Add `Makefile` for local dev (`make lint`, `make build`, `make integration`, `make clean`)
- Pin Bitnami chart versions with documented upgrade cadence
- Publish snapshot runner to internal registry with lifecycle ownership

## Production Hardening
- Dedicated namespace per run (`integration-${GITHUB_RUN_ID}`)
- Resource requests/limits on PostgreSQL and Redis Helm deployments
- `activeDeadlineSeconds` tuned per workload
- Structured diagnostics by component

## Security
- Move credentials to GitHub Secrets for multi-repo adoption
- SBOM generation (`syft`) + image signing (`cosign`)
- Mirror Bitnami charts to internal registry

## Scalability
- Publish reusable workflow with semver tags to a central platform repo
- Matrix strategy for multiple services/dependency stacks
- Centralized dashboards for pass rate, duration, flake rate
- Platform API for ephemeral test environments at 50+ services
