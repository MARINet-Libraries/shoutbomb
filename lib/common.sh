#!/usr/bin/env bash

# Load a Bash-compatible environment file and export all assignments it makes.
shoutbomb_load_env() {
  local env_file="$1"
  local source_status

  if [[ ! -f "$env_file" ]]; then
    echo "Error: Environment file not found: $env_file" >&2
    return 1
  fi

  if [[ ! -r "$env_file" ]]; then
    echo "Error: Environment file is not readable: $env_file" >&2
    return 1
  fi

  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  source_status=$?
  set +a

  if [[ $source_status -ne 0 ]]; then
    echo "Error: Failed to load environment file: $env_file" >&2
    return 1
  fi
}

shoutbomb_array_contains() {
  local needle="$1"
  shift
  local value

  for value in "$@"; do
    if [[ "$value" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

shoutbomb_collect_missing_vars() {
  local output_array_name="$1"
  shift
  local variable_name
  local -n output_array_ref="$output_array_name"

  output_array_ref=()

  for variable_name in "$@"; do
    if [[ -z "${!variable_name:-}" ]]; then
      output_array_ref+=("$variable_name")
    fi
  done
}
