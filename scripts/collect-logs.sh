#!/usr/bin/env bash
set -u

ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"
NAMESPACE="${NAMESPACE:-default}"
JOB_NAME="${JOB_NAME:-integration-test}"

mkdir -p "${ARTIFACT_DIR}"

run_capture() {
  local output_file="$1"
  shift
  echo "+ $*" > "${output_file}"
  "$@" >> "${output_file}" 2>&1
}

run_capture "${ARTIFACT_DIR}/kubectl-get-all.txt" kubectl get all --namespace "${NAMESPACE}" -o wide
run_capture "${ARTIFACT_DIR}/kubectl-get-events.txt" kubectl get events --namespace "${NAMESPACE}" --sort-by=.lastTimestamp
run_capture "${ARTIFACT_DIR}/kubectl-describe-all.txt" kubectl describe all --namespace "${NAMESPACE}"

if kubectl get job "${JOB_NAME}" --namespace "${NAMESPACE}" >/dev/null 2>&1; then
  run_capture "${ARTIFACT_DIR}/job-describe.txt" kubectl describe job "${JOB_NAME}" --namespace "${NAMESPACE}"
  run_capture "${ARTIFACT_DIR}/integration-test.log" kubectl logs "job/${JOB_NAME}" --namespace "${NAMESPACE}" --all-containers=true
fi

echo "Collected artifacts in ${ARTIFACT_DIR}"
