# Next Steps

## Immediate
- Add `Makefile` for local dev (`make lint`, `make build`, `make integration`, `make clean`)
- Testing on selfhosted agent for reduce the time for running pipeline, pre-install tool, set-up,..

## Production Hardening
- Dedicated namespace per run (`integration-${GITHUB_RUN_ID}`)
- Resource requests/limits on PostgreSQL and Redis Helm deployments

## Security
- Move credentials to GitHub Secrets for multi-repo adoption
- Mirror Bitnami charts to internal registry

## Scalability
- Publish reusable workflow with semver tags to a central platform repo
- Matrix strategy for multiple services/dependency stacks
- Centralized dashboards for pass rate, duration, flake rate