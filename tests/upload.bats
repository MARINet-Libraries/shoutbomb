#!/usr/bin/env bats

load test_helper

setup() {
  setup_project_fixture
}

@test "upload sends the numerically latest file for every supported report" {
  write_ssh_env
  create_report_file holds 9
  create_report_file holds 10
  create_report_file renew 20
  create_report_file overdue 30
  create_report_file text-patrons 40
  create_report_file loanrules 999
  printf '%s\n' malformed > "$TEST_PROJECT/data/holds-current.csv"

  run bash -c 'cd -- "$1" && shift && exec "$@"' \
    test-runner "$TEST_OUTSIDE_DIR" "$TEST_PROJECT/upload"

  assert_status 0
  assert_output_contains "All uploads completed successfully."
  assert_call_count sftp 4

  assert_file_contains "$(mock_call_dir sftp 1)/stdin" "/Holds/holds-10.csv"
  refute_file_contains "$(mock_call_dir sftp 1)/stdin" "holds-9.csv"
  assert_file_contains "$(mock_call_dir sftp 2)/stdin" "/Renew/renew-20.csv"
  assert_file_contains "$(mock_call_dir sftp 3)/stdin" "/Overdue/overdue-30.csv"
  assert_file_contains "$(mock_call_dir sftp 4)/stdin" "/text_patrons/text-patrons-40.csv"
  refute_file_contains "$MOCK_STATE_DIR/sftp/transcript" "loanrules"

  assert_mock_arg sftp 1 "-b"
  assert_mock_arg sftp 1 "-P"
  assert_mock_arg sftp 1 "22"
  assert_mock_arg sftp 1 "BatchMode=yes"
  assert_mock_arg sftp 1 "StrictHostKeyChecking=yes"
  assert_mock_arg sftp 1 "IdentitiesOnly=yes"
  assert_mock_arg sftp 1 "$TEST_IDENTITY_FILE"
  assert_mock_arg sftp 1 "test-user@ftp.shoutbomb.com"
}

@test "upload passes overrides, verbosity, known-hosts path, and quoted paths to sftp" {
  write_ssh_env_with_overrides
  create_report_file text-patrons 123

  run "$TEST_PROJECT/upload" \
    --reports text-patrons \
    --host cli-sftp.example \
    --port 2222 \
    --verbose

  assert_status 0
  assert_call_count sftp 1
  assert_mock_arg sftp 1 "-v"
  assert_mock_arg sftp 1 "2222"
  assert_mock_arg sftp 1 "UserKnownHostsFile=$TEST_KNOWN_HOSTS_FILE"
  assert_mock_arg sftp 1 "test-user@cli-sftp.example"
  assert_file_contains "$(mock_call_dir sftp 1)/stdin" \
    "put \"$TEST_PROJECT/data/text-patrons-123.csv\" \"/text_patrons/text-patrons-123.csv\""
}

@test "upload validates requested reports before configuration or SFTP" {
  run "$TEST_PROJECT/upload" --reports loanrules holds.sql

  assert_status 1
  assert_output_contains "Error: Invalid report name(s) for --reports:"
  assert_output_contains "loanrules"
  assert_output_contains "holds.sql"
  assert_output_contains "Valid reports:"
  assert_call_count sftp 0
}

@test "upload fails when a selected report has no valid timestamped CSV" {
  write_ssh_env
  printf '%s\n' malformed > "$TEST_PROJECT/data/holds-current.csv"
  printf '%s\n' malformed > "$TEST_PROJECT/data/holds-123.csv.bak"

  run "$TEST_PROJECT/upload" --reports holds

  assert_status 1
  assert_output_contains "Missing report file for holds"
  assert_call_count sftp 0
}

@test "upload continues after one SFTP failure and returns failure" {
  write_ssh_env
  create_report_file holds 10
  create_report_file overdue 20
  export MOCK_SFTP_FAIL_MATCH="holds-10.csv"

  run "$TEST_PROJECT/upload" --reports holds overdue

  assert_status 1
  assert_output_contains "Failed to upload"
  assert_output_contains "Completed with one or more upload failures."
  assert_call_count sftp 2
  assert_file_contains "$(mock_call_dir sftp 2)/stdin" "/Overdue/overdue-20.csv"
}

@test "upload rejects invalid key paths and ports before SFTP" {
  cat > "$TEST_PROJECT/.env" <<'EOF'
SSH_USERNAME=test-user
SSH_IDENTITY_FILE=relative/key
EOF

  run "$TEST_PROJECT/upload" --reports holds
  assert_status 1
  assert_output_contains "SSH identity file must be an absolute path"
  assert_call_count sftp 0

  write_ssh_env
  run "$TEST_PROJECT/upload" --reports holds --port not-a-port
  assert_status 1
  assert_output_contains "SSH port must be a number"
  assert_call_count sftp 0
}

@test "upload preserves its known usage-error status" {
  # Characterization of the current CLI contract.
  run "$TEST_PROJECT/upload" --unknown

  assert_status 1
  assert_output_contains "Error: Invalid option: --unknown"
}
