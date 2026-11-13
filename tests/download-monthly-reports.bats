#!/usr/bin/env bats

load test_helper

setup() {
  bats_require_minimum_version 1.5.0
  setup_project_fixture
  write_ssh_env
  monthly_dir="$TEST_PROJECT/data/monthly-reports"
  first=sb_generate_monthly_report_feb88521e8_2026-11-05_00_10_18.csv
  older=sb_generate_monthly_report_other-id_2026-10-04_12_00_00.csv
  mkdir -p -- "$MOCK_STATE_DIR/monthly-remote"
}

add_remote_file() {
  local name="$1"
  printf '%s\n' "${2:-monthly statistics fixture}" > "$MOCK_STATE_DIR/monthly-remote/$name"
  printf '/monthly_report/%s\n' "$name" >> "$MOCK_STATE_DIR/monthly-listing"
}

run_service() {
  run "$TEST_PROJECT/services/download-monthly-reports" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL "$@"
}

add_monitoring_env() {
  cat >> "$TEST_PROJECT/.env" <<EOF
HEALTHCHECKS_TEST_URL=https://hc.example.test/monthly-poll/
SHOUTBOMB_LOGGER_PATH='$MOCK_BIN/logger'
EOF
}

@test "monthly download fetches all historical files from outside project and skips them on rerun" {
  add_remote_file "$first" 'current fixture'
  add_remote_file "$older" 'historical fixture'

  run bash -c 'cd -- "$1" && exec "$2"' test-runner \
    "$TEST_OUTSIDE_DIR" "$TEST_PROJECT/download-monthly-reports"

  assert_status 0
  assert_output_contains 'downloaded=2 skipped=0 ignored=0 failed=0'
  assert_file_content "$monthly_dir/$first" 'current fixture'
  assert_file_content "$monthly_dir/$older" 'historical fixture'
  assert_directory_not_exists "$monthly_dir/.download.lock"
  assert_call_count sftp 3
  assert_mock_arg sftp 1 'BatchMode=yes'
  assert_mock_arg sftp 1 'StrictHostKeyChecking=yes'
  assert_mock_arg sftp 1 'IdentitiesOnly=yes'
  assert_mock_arg sftp 1 "$TEST_IDENTITY_FILE"
  assert_mock_arg sftp 1 'test-user@ftp.shoutbomb.com'
  assert_mock_arg sftp 1 '22'
  assert_file_content "$(mock_call_dir sftp 1)/stdin" '@ls -1 /monthly_report'
  assert_file_contains "$(mock_call_dir sftp 2)/stdin" "@get \"/monthly_report/$first\""
  refute_file_contains "$MOCK_STATE_DIR/sftp/transcript" 'put '
  refute_file_contains "$MOCK_STATE_DIR/sftp/transcript" 'rm '

  run "$TEST_PROJECT/download-monthly-reports"
  assert_status 0
  assert_output_contains 'downloaded=0 skipped=2 ignored=0 failed=0'
  assert_call_count sftp 4
}

@test "monthly download accepts basename listing and ignores unsafe or unrelated entries" {
  add_remote_file "$first"
  printf '%s\n' "$first" '../escape.csv' \
    "/other/$first" 'unexpected.csv' \
    'sb_generate_monthly_report_$(touch hacked)_2026-11-05_00_10_18.csv' \
    > "$MOCK_STATE_DIR/monthly-listing"

  run "$TEST_PROJECT/download-monthly-reports"

  assert_status 0
  assert_output_contains 'downloaded=1 skipped=0 ignored=4 failed=0'
  assert_call_count sftp 2
  assert_file_exists "$monthly_dir/$first"
  assert_file_not_exists "$TEST_PROJECT/hacked"
  assert_file_not_exists "$TEST_PROJECT/data/escape.csv"
}

@test "monthly download treats empty listing as successful no-op" {
  run "$TEST_PROJECT/download-monthly-reports"

  assert_status 0
  assert_output_contains 'downloaded=0 skipped=0 ignored=0 failed=0'
  assert_call_count sftp 1
  assert_directory_not_exists "$monthly_dir/.download.lock"
}

@test "monthly download never treats failed listing as an empty directory" {
  add_remote_file "$first"
  export MOCK_SFTP_FAIL_MATCH='@ls'

  run "$TEST_PROJECT/download-monthly-reports"

  assert_status 1
  assert_output_contains 'Failed to list /monthly_report'
  refute_output_contains 'downloaded=0'
  assert_call_count sftp 1
  assert_file_not_exists "$monthly_dir/$first"
  assert_directory_not_exists "$monthly_dir/.download.lock"
}

@test "monthly download cleans partial transfers, continues, and retries only failed files" {
  add_remote_file "$first"
  add_remote_file "$older"
  export MOCK_SFTP_FAIL_MATCH="$first"

  run "$TEST_PROJECT/download-monthly-reports"

  assert_status 1
  assert_output_contains 'downloaded=1 skipped=0 ignored=0 failed=1'
  assert_file_not_exists "$monthly_dir/$first"
  assert_file_exists "$monthly_dir/$older"
  assert_directory_not_exists "$monthly_dir/.download.lock"
  assert_call_count sftp 3

  unset MOCK_SFTP_FAIL_MATCH
  run "$TEST_PROJECT/download-monthly-reports"
  assert_status 0
  assert_output_contains 'downloaded=1 skipped=1 ignored=0 failed=0'
  assert_file_exists "$monthly_dir/$first"
  assert_call_count sftp 5
}

@test "monthly download cleans interrupted transfers and preserves signal exit status" {
  add_remote_file "$first"
  export MOCK_SFTP_INTERRUPT_DOWNLOAD=1

  run "$TEST_PROJECT/download-monthly-reports"

  assert_status 143
  assert_file_not_exists "$monthly_dir/$first"
  assert_directory_not_exists "$monthly_dir/.download.lock"
}

@test "monthly download quotes local project paths containing quotes and backslashes" {
  local original_project="$TEST_PROJECT"
  TEST_PROJECT="$BATS_TEST_TMPDIR/project \"quoted\" \\ path"
  mv -- "$original_project" "$TEST_PROJECT"
  monthly_dir="$TEST_PROJECT/data/monthly-reports"
  add_remote_file "$first"

  run "$TEST_PROJECT/download-monthly-reports"

  assert_status 0
  assert_file_exists "$monthly_dir/$first"
  assert_directory_not_exists "$monthly_dir/.download.lock"
}

@test "monthly download reports a missing SFTP dependency without loading configuration" {
  local isolated_bin="$BATS_TEST_TMPDIR/no-sftp-bin"
  mkdir -p -- "$isolated_bin"
  ln -s -- "$(command -v bash)" "$isolated_bin/bash"
  ln -s -- "$(command -v dirname)" "$isolated_bin/dirname"
  rm -- "$TEST_PROJECT/.env"

  run -127 env PATH="$isolated_bin" "$TEST_PROJECT/download-monthly-reports"

  assert_status 127
  assert_output_contains 'sftp was not found on PATH'
  refute_output_contains 'Environment file not found'
}

@test "monthly download preserves existing content when a remote filename is reused" {
  add_remote_file "$first" 'remote replacement'
  mkdir -p -- "$monthly_dir"
  printf 'original local copy\n' > "$monthly_dir/$first"

  run "$TEST_PROJECT/download-monthly-reports"

  assert_status 0
  assert_output_contains 'downloaded=0 skipped=1'
  assert_file_content "$monthly_dir/$first" 'original local copy'
  assert_call_count sftp 1
}

@test "monthly download rejects symlink and directory destinations without writing through them" {
  add_remote_file "$first"
  add_remote_file "$older"
  mkdir -p -- "$monthly_dir/$older"
  printf 'untouched\n' > "$TEST_OUTSIDE_DIR/target"
  ln -s -- "$TEST_OUTSIDE_DIR/target" "$monthly_dir/$first"

  run "$TEST_PROJECT/download-monthly-reports"

  assert_status 1
  assert_output_contains 'downloaded=0 skipped=0 ignored=0 failed=2'
  assert_file_content "$TEST_OUTSIDE_DIR/target" untouched
  assert_directory_exists "$monthly_dir/$older"
  assert_call_count sftp 1
}

@test "monthly download lock contention fails without removing another run's lock" {
  mkdir -p -- "$monthly_dir/.download.lock"
  printf 'other run\n' > "$monthly_dir/.download.lock/owner"

  run "$TEST_PROJECT/download-monthly-reports"

  assert_status 1
  assert_output_contains 'Cannot acquire download lock'
  assert_file_content "$monthly_dir/.download.lock/owner" 'other run'
  assert_call_count sftp 0
}

@test "monthly download passes SSH overrides, verbosity and known-hosts setting" {
  write_ssh_env_with_overrides

  run "$TEST_PROJECT/download-monthly-reports" --host cli.example --port 2222 --verbose

  assert_status 0
  assert_mock_arg sftp 1 'test-user@cli.example'
  assert_mock_arg sftp 1 '2222'
  assert_mock_arg sftp 1 '-v'
  assert_mock_arg sftp 1 "UserKnownHostsFile=$TEST_KNOWN_HOSTS_FILE"
}

@test "monthly download validates port range and key paths before SFTP" {
  local port
  for port in abc 0 65536 999999999999999999999; do
    run "$TEST_PROJECT/download-monthly-reports" --port "$port"
    assert_status 1
    assert_output_contains 'SSH port must be a number from 1 to 65535'
  done
  printf "SSH_USERNAME=test\nSSH_IDENTITY_FILE=relative/key\n" > "$TEST_PROJECT/.env"
  run "$TEST_PROJECT/download-monthly-reports"
  assert_status 1
  assert_output_contains 'SSH_IDENTITY_FILE must be an absolute path to a readable file'
  write_ssh_env
  printf 'SSH_KNOWN_HOSTS_FILE=/nonexistent/test-known-hosts\n' >> "$TEST_PROJECT/.env"
  run "$TEST_PROJECT/download-monthly-reports"
  assert_status 1
  assert_output_contains 'SSH_KNOWN_HOSTS_FILE must be an absolute path to a readable file'
  assert_call_count sftp 0
}

@test "monthly download rejects missing or failed configuration" {
  rm -- "$TEST_PROJECT/.env"
  run "$TEST_PROJECT/download-monthly-reports"
  assert_status 1
  assert_output_contains 'Environment file not found'
  printf 'SSH_USERNAME=test\n' > "$TEST_PROJECT/.env"
  run "$TEST_PROJECT/download-monthly-reports"
  assert_status 1
  assert_output_contains 'Missing required SSH/SFTP settings'
  assert_output_contains 'SSH_IDENTITY_FILE'
  write_ssh_env
  printf 'return 8\n' >> "$TEST_PROJECT/.env"
  run "$TEST_PROJECT/download-monthly-reports"
  assert_status 1
  assert_output_contains 'Failed to load environment file'
  assert_call_count sftp 0
}

@test "monthly download usage errors do not require configuration" {
  rm -- "$TEST_PROJECT/.env"
  run "$TEST_PROJECT/download-monthly-reports" --unknown
  assert_status 2
  run "$TEST_PROJECT/download-monthly-reports" --host
  assert_status 2
  run "$TEST_PROJECT/download-monthly-reports" --port ''
  assert_status 2
  assert_call_count sftp 0
}

@test "monthly service records daily success even when no new files arrive" {
  add_monitoring_env

  run_service

  assert_status 0
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/monthly-poll/start\nhttps://hc.example.test/monthly-poll'
  assert_file_content "$MOCK_STATE_DIR/logger/tags" shoutbomb-download-monthly-reports
  assert_file_contains "$(mock_call_dir logger 1)/stdin" 'downloaded=0 skipped=0'
  refute_output_contains 'https://hc.example.test'
  refute_file_contains "$(mock_call_dir logger 1)/stdin" 'https://hc.example.test'
}

@test "monthly service sends fail on transfer failure and passes downloader flags" {
  add_monitoring_env
  add_remote_file "$first"
  export MOCK_SFTP_FAIL_MATCH="$first"

  run_service --host override.example --port 2222 --verbose

  assert_status 1
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/monthly-poll/start\nhttps://hc.example.test/monthly-poll/fail'
  assert_mock_arg sftp 1 'test-user@override.example'
  assert_mock_arg sftp 1 '2222'
  assert_mock_arg sftp 1 '-v'
}

@test "monthly service preserves best-effort monitoring and logger pipeline status" {
  add_monitoring_env
  export MOCK_CURL_STATUS=22
  run_service
  assert_status 0
  assert_call_count sftp 1

  export MOCK_LOGGER_STATUS=24
  run_service
  assert_status 24
  assert_file_contains "$MOCK_STATE_DIR/curl/urls" 'https://hc.example.test/monthly-poll/fail'
}

@test "monthly service validates its required monitoring variable before external calls" {
  run "$TEST_PROJECT/services/download-monthly-reports"
  assert_status 2
  run "$TEST_PROJECT/services/download-monthly-reports" --healthcheck-url-env
  assert_status 2
  run "$TEST_PROJECT/services/download-monthly-reports" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL --healthcheck-url-env HEALTHCHECKS_TEST_URL
  assert_status 2
  run "$TEST_PROJECT/services/download-monthly-reports" --healthcheck-url-env PRIVATE_URL
  assert_status 1
  assert_output_contains 'Invalid Healthchecks.io variable name'
  run_service
  assert_status 1
  assert_output_contains 'Missing required Healthchecks.io setting'
  assert_call_count sftp 0
  assert_call_count curl 0
}

@test "monthly service passes unknown downloader arguments through for validation" {
  add_monitoring_env

  run_service --unknown

  assert_status 2
  assert_call_count sftp 0
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/monthly-poll/start\nhttps://hc.example.test/monthly-poll/fail'
}
