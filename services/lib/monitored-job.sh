#!/usr/bin/env bash

monitored_job_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
. "$monitored_job_library_dir/../../lib/common.sh"
unset monitored_job_library_dir

monitoring_finished=0
monitoring_healthchecks_url=""

resolve_healthchecks_url() {
  local env_file="$1"
  local variable_name="$2"
  local url

  if [[ ! "$variable_name" =~ ^HEALTHCHECKS_[A-Z0-9]+(_[A-Z0-9]+)*_URL$ ]]; then
    echo "Error: Invalid Healthchecks.io variable name: $variable_name" >&2
    echo "Expected an environment variable name matching HEALTHCHECKS_*_URL." >&2
    return 1
  fi

  if [[ -z "${!variable_name:-}" ]]; then
    echo "Error: Missing required Healthchecks.io setting in $env_file: $variable_name" >&2
    return 1
  fi

  url="${!variable_name}"
  printf '%s\n' "${url%/}"
}

send_healthcheck_ping() {
  local suffix="$1"
  local curl_path

  if ! curl_path="$(command -v curl 2>/dev/null)"; then
    return 0
  fi

  "$curl_path" \
    -fsS \
    --connect-timeout 2 \
    --max-time 5 \
    --retry 5 \
    --retry-max-time 30 \
    -o /dev/null \
    "${monitoring_healthchecks_url}${suffix}" \
    </dev/null >/dev/null 2>&1 || true
}

finish_monitoring() {
  local status="$1"

  trap - HUP INT TERM
  monitoring_finished=1

  if [[ $status -eq 0 ]]; then
    send_healthcheck_ping ""
  else
    send_healthcheck_ping "/fail"
  fi

  exit "$status"
}

handle_monitored_exit() {
  local status="$1"

  trap - EXIT

  if [[ $monitoring_finished -eq 0 ]]; then
    send_healthcheck_ping "/fail"
  fi

  exit "$status"
}

start_monitoring() {
  monitoring_healthchecks_url="$1"
  monitoring_finished=0

  trap 'handle_monitored_exit "$?"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  send_healthcheck_ping "/start"
}

start_monitoring_from_env() {
  local env_file="$1"
  local variable_name="$2"
  local healthchecks_url

  if ! shoutbomb_load_env "$env_file"; then
    return 1
  fi

  if ! healthchecks_url="$(resolve_healthchecks_url "$env_file" "$variable_name")"; then
    return 1
  fi

  start_monitoring "$healthchecks_url"
}

run_logged() {
  local tag="$1"
  local logger_path="${SHOUTBOMB_LOGGER_PATH:-/usr/bin/logger}"
  shift

  "$@" 2>&1 | "$logger_path" -t "$tag"
}
