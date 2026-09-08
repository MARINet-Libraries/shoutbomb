#!/usr/bin/env bash

TEST_SOURCE_ROOT="$(cd -- "$BATS_TEST_DIRNAME/.." && pwd)"
TEST_ORIGINAL_PATH="$PATH"

setup_project_fixture() {
  TEST_PROJECT="$BATS_TEST_TMPDIR/project fixture"
  TEST_OUTSIDE_DIR="$BATS_TEST_TMPDIR/outside working directory"
  MOCK_BIN="$BATS_TEST_TMPDIR/mock bin"
  MOCK_STATE_DIR="$BATS_TEST_TMPDIR/mock state"
  TEST_IDENTITY_FILE="$BATS_TEST_TMPDIR/identity key"
  TEST_KNOWN_HOSTS_FILE="$BATS_TEST_TMPDIR/known hosts"

  mkdir -p -- \
    "$TEST_PROJECT/data/_archive" \
    "$TEST_PROJECT/lib" \
    "$TEST_PROJECT/sql" \
    "$TEST_PROJECT/services/lib" \
    "$TEST_OUTSIDE_DIR" \
    "$MOCK_BIN" \
    "$MOCK_STATE_DIR"

  cp -- "$TEST_SOURCE_ROOT/check" "$TEST_PROJECT/check"
  cp -- "$TEST_SOURCE_ROOT/generate-reports" "$TEST_PROJECT/generate-reports"
  cp -- "$TEST_SOURCE_ROOT/upload" "$TEST_PROJECT/upload"
  cp -- "$TEST_SOURCE_ROOT/archive-reports" "$TEST_PROJECT/archive-reports"
  cp -- "$TEST_SOURCE_ROOT/lib/common.sh" "$TEST_PROJECT/lib/common.sh"
  cp -- "$TEST_SOURCE_ROOT/services/generate-and-upload" "$TEST_PROJECT/services/generate-and-upload"
  cp -- "$TEST_SOURCE_ROOT/services/archive-reports" "$TEST_PROJECT/services/archive-reports"
  cp -- "$TEST_SOURCE_ROOT/services/lib/monitored-job.sh" "$TEST_PROJECT/services/lib/monitored-job.sh"
  cp -- "$TEST_SOURCE_ROOT/sql/"*.sql "$TEST_PROJECT/sql/"

  cp -- "$TEST_SOURCE_ROOT/tests/mocks/curl" "$MOCK_BIN/curl"
  cp -- "$TEST_SOURCE_ROOT/tests/mocks/date" "$MOCK_BIN/date"
  cp -- "$TEST_SOURCE_ROOT/tests/mocks/logger" "$MOCK_BIN/logger"
  cp -- "$TEST_SOURCE_ROOT/tests/mocks/mock-lib.bash" "$MOCK_BIN/mock-lib.bash"
  cp -- "$TEST_SOURCE_ROOT/tests/mocks/psql" "$MOCK_BIN/psql"
  cp -- "$TEST_SOURCE_ROOT/tests/mocks/sftp" "$MOCK_BIN/sftp"

  chmod +x \
    "$TEST_PROJECT/check" \
    "$TEST_PROJECT/generate-reports" \
    "$TEST_PROJECT/upload" \
    "$TEST_PROJECT/archive-reports" \
    "$TEST_PROJECT/services/generate-and-upload" \
    "$TEST_PROJECT/services/archive-reports" \
    "$MOCK_BIN/curl" \
    "$MOCK_BIN/date" \
    "$MOCK_BIN/logger" \
    "$MOCK_BIN/psql" \
    "$MOCK_BIN/sftp"

  printf '%s\n' 'test identity' > "$TEST_IDENTITY_FILE"
  printf '%s\n' 'test.example ssh-ed25519 AAAATEST' > "$TEST_KNOWN_HOSTS_FILE"

  export TEST_PROJECT TEST_OUTSIDE_DIR MOCK_BIN MOCK_STATE_DIR
  export TEST_IDENTITY_FILE TEST_KNOWN_HOSTS_FILE
  export PATH="$MOCK_BIN:$TEST_ORIGINAL_PATH"
  export MOCK_DATE_EPOCH=1700000000

  unset SHOUTBOMB_LOGGER_PATH
  unset MOCK_PSQL_FAIL_REPORTS MOCK_PSQL_FAILURE_STATUS
  unset MOCK_SFTP_FAIL_MATCH MOCK_SFTP_FAILURE_STATUS
  unset MOCK_CURL_STATUS MOCK_LOGGER_FAIL_TAG MOCK_LOGGER_FAILURE_STATUS MOCK_LOGGER_STATUS
  unset MOCK_GENERATE_REPORTS_STATUS MOCK_UPLOAD_STATUS MOCK_ARCHIVE_REPORTS_STATUS
  unset PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD
  unset SSH_HOST SSH_PORT SSH_USERNAME SSH_IDENTITY_FILE SSH_KNOWN_HOSTS_FILE
  unset HEALTHCHECKS_TEST_URL HEALTHCHECKS_PRIMARY_REPORTS_URL HEALTHCHECKS_ARCHIVE_URL
}

install_workflow_stubs() {
  local command_name

  for command_name in generate-reports upload archive-reports; do
    cp -- "$TEST_SOURCE_ROOT/tests/mocks/workflow-command" "$TEST_PROJECT/$command_name"
    chmod +x "$TEST_PROJECT/$command_name"
  done
}

write_pg_env() {
  cat > "$TEST_PROJECT/.env" <<'EOF'
PGHOST=test-db.example
PGPORT=5432
PGDATABASE=test_database
PGUSER=test_user
PGPASSWORD=test_password
EOF
}

write_ssh_env() {
  cat > "$TEST_PROJECT/.env" <<EOF
SSH_USERNAME=test-user
SSH_IDENTITY_FILE='$TEST_IDENTITY_FILE'
EOF
}

write_ssh_env_with_overrides() {
  cat > "$TEST_PROJECT/.env" <<EOF
SSH_HOST=sftp.test.example
SSH_PORT=2200
SSH_USERNAME=test-user
SSH_IDENTITY_FILE='$TEST_IDENTITY_FILE'
SSH_KNOWN_HOSTS_FILE='$TEST_KNOWN_HOSTS_FILE'
EOF
}

write_monitoring_env() {
  cat > "$TEST_PROJECT/.env" <<EOF
HEALTHCHECKS_TEST_URL=https://hc.example.test/test-id/
HEALTHCHECKS_PRIMARY_REPORTS_URL=https://hc.example.test/primary-id
HEALTHCHECKS_ARCHIVE_URL=https://hc.example.test/archive-id
SHOUTBOMB_LOGGER_PATH='$MOCK_BIN/logger'
EOF
}

create_report_file() {
  local report_name="$1"
  local epoch="$2"
  local content="${3:-fixture $report_name $epoch}"

  printf '%s\n' "$content" > "$TEST_PROJECT/data/$report_name-$epoch.csv"
}

create_archived_report_file() {
  local report_name="$1"
  local epoch="$2"
  local content="${3:-archived fixture $report_name $epoch}"

  printf '%s\n' "$content" > "$TEST_PROJECT/data/_archive/$report_name-$epoch.csv"
}

mock_call_count() {
  local command_name="$1"
  local count_file="$MOCK_STATE_DIR/$command_name/count"

  if [[ -f "$count_file" ]]; then
    cat "$count_file"
  else
    printf '0\n'
  fi
}

mock_call_dir() {
  local command_name="$1"
  local call_number="$2"

  printf '%s/%s/%s\n' "$MOCK_STATE_DIR" "$command_name" "$call_number"
}

assert_status() {
  local expected="$1"

  # Bats sets status and output after each run invocation.
  # shellcheck disable=SC2154
  if [[ "$status" -ne "$expected" ]]; then
    printf 'Expected status %s, got %s.\nOutput:\n%s\n' "$expected" "$status" "$output" >&2
    return 1
  fi
}

assert_output_contains() {
  local expected="$1"

  if [[ "$output" != *"$expected"* ]]; then
    printf 'Expected output to contain:\n%s\nActual output:\n%s\n' "$expected" "$output" >&2
    return 1
  fi
}

refute_output_contains() {
  local unexpected="$1"

  if [[ "$output" == *"$unexpected"* ]]; then
    printf 'Expected output not to contain:\n%s\nActual output:\n%s\n' "$unexpected" "$output" >&2
    return 1
  fi
}

assert_file_exists() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    printf 'Expected file to exist: %s\n' "$file_path" >&2
    return 1
  fi
}

assert_file_not_exists() {
  local file_path="$1"

  if [[ -e "$file_path" || -L "$file_path" ]]; then
    printf 'Expected path not to exist: %s\n' "$file_path" >&2
    return 1
  fi
}

assert_directory_exists() {
  local directory_path="$1"

  if [[ ! -d "$directory_path" ]]; then
    printf 'Expected directory to exist: %s\n' "$directory_path" >&2
    return 1
  fi
}

assert_directory_not_exists() {
  local directory_path="$1"

  if [[ -e "$directory_path" ]]; then
    printf 'Expected directory not to exist: %s\n' "$directory_path" >&2
    return 1
  fi
}

assert_file_contains() {
  local file_path="$1"
  local expected="$2"

  if [[ ! -f "$file_path" ]] || ! grep -F -- "$expected" "$file_path" >/dev/null; then
    printf 'Expected %s to contain:\n%s\n' "$file_path" "$expected" >&2
    if [[ -f "$file_path" ]]; then
      printf 'Actual content:\n' >&2
      cat "$file_path" >&2
    fi
    return 1
  fi
}

refute_file_contains() {
  local file_path="$1"
  local unexpected="$2"

  if [[ -f "$file_path" ]] && grep -F -- "$unexpected" "$file_path" >/dev/null; then
    printf 'Expected %s not to contain:\n%s\nActual content:\n' "$file_path" "$unexpected" >&2
    cat "$file_path" >&2
    return 1
  fi
}

assert_file_content() {
  local file_path="$1"
  local expected="$2"
  local actual

  if [[ ! -f "$file_path" ]]; then
    printf 'Expected file to exist: %s\n' "$file_path" >&2
    return 1
  fi

  actual="$(cat "$file_path")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Unexpected content in %s.\nExpected:\n%s\nActual:\n%s\n' \
      "$file_path" "$expected" "$actual" >&2
    return 1
  fi
}

assert_call_count() {
  local command_name="$1"
  local expected="$2"
  local actual

  actual="$(mock_call_count "$command_name")"
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'Expected %s call(s) to %s, got %s.\n' "$expected" "$command_name" "$actual" >&2
    return 1
  fi
}

assert_mock_arg() {
  local command_name="$1"
  local call_number="$2"
  local expected="$3"
  local args_file

  args_file="$(mock_call_dir "$command_name" "$call_number")/args"
  if [[ ! -f "$args_file" ]] || ! grep -Fx -- "$expected" "$args_file" >/dev/null; then
    printf 'Expected call %s to %s to contain argument:\n%s\n' \
      "$call_number" "$command_name" "$expected" >&2
    if [[ -f "$args_file" ]]; then
      printf 'Actual arguments:\n' >&2
      cat "$args_file" >&2
    fi
    return 1
  fi
}

refute_mock_arg() {
  local command_name="$1"
  local call_number="$2"
  local unexpected="$3"
  local args_file

  args_file="$(mock_call_dir "$command_name" "$call_number")/args"
  if [[ -f "$args_file" ]] && grep -Fx -- "$unexpected" "$args_file" >/dev/null; then
    printf 'Expected call %s to %s not to contain argument:\n%s\n' \
      "$call_number" "$command_name" "$unexpected" >&2
    return 1
  fi
}
