#!/usr/bin/env bash
set -u

CLUSTER_NAME="${CLUSTER_NAME:-ci-cluster}"
NAMESPACE="${NAMESPACE:-default}"
POSTGRES_RELEASE_NAME="${POSTGRES_RELEASE_NAME:-postgresql}"
REDIS_RELEASE_NAME="${REDIS_RELEASE_NAME:-redis}"
JOB_RELEASE_NAME="${JOB_RELEASE_NAME:-integration-test}"
CLEANUP_TIMEOUT="${CLEANUP_TIMEOUT:-60}"
STATUS=0

run_cleanup() {
  local step_name="$1"
  shift
  echo "::group::Cleanup: ${step_name}"
  echo "+ $*"
  if timeout "${CLEANUP_TIMEOUT}" "$@"; then
    echo "✓ ${step_name} succeeded"
  else
    local rc=$?
    echo "✗ ${step_name} failed with exit code ${rc}" >&2
    STATUS=1
  fi
  echo "::endgroup::"
}

CLUSTER_EXISTS="false"
if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  CLUSTER_EXISTS="true"
fi

if [ "${CLUSTER_EXISTS}" = "true" ] && command -v helm >/dev/null 2>&1; then
  run_cleanup "Uninstall integration test" helm uninstall "${JOB_RELEASE_NAME}" --namespace "${NAMESPACE}" --ignore-not-found --wait
  run_cleanup "Uninstall PostgreSQL" helm uninstall "${POSTGRES_RELEASE_NAME}" --namespace "${NAMESPACE}" --ignore-not-found --wait
  run_cleanup "Uninstall Redis" helm uninstall "${REDIS_RELEASE_NAME}" --namespace "${NAMESPACE}" --ignore-not-found --wait
elif [ "${CLUSTER_EXISTS}" != "true" ]; then
  echo "Kind cluster ${CLUSTER_NAME} is not present; skipping Helm release cleanup"
else
  echo "helm is unavailable; skipping Helm release cleanup"
fi

if command -v kind >/dev/null 2>&1; then
  run_cleanup "Delete Kind cluster" kind delete cluster --name "${CLUSTER_NAME}"

  # Verify cluster is actually gone
  if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    echo "✗ Kind cluster ${CLUSTER_NAME} still exists after deletion" >&2
    STATUS=1
  else
    echo "✓ Verified: Kind cluster ${CLUSTER_NAME} is gone"
  fi
else
  echo "kind is unavailable; skipping Kind cluster cleanup"
fi

if [ "${STATUS}" -ne 0 ]; then
  echo "::warning::Cleanup completed with errors — check logs above"
fi

exit "${STATUS}"
