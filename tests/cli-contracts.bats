#!/usr/bin/env bats

load test_helper

setup() {
  setup_project_fixture
}

@test "command entrypoints provide help without external calls" {
  local entrypoint
  local -a entrypoints=(
    check
    generate-reports
    upload
    archive-reports
    services/generate-and-upload
    services/archive-reports
  )

  for entrypoint in "${entrypoints[@]}"; do
    run "$TEST_PROJECT/$entrypoint" --help
    assert_status 0
    assert_output_contains "Usage:"
  done

  assert_call_count psql 0
  assert_call_count sftp 0
  assert_call_count curl 0
  assert_call_count logger 0
}

@test "known end-of-options handling remains characterized" {
  # These assertions document current behavior; they do not endorse it as the
  # eventual common contract.
  run "$TEST_PROJECT/generate-reports" -- --help
  assert_status 2
  assert_output_contains "Unknown option: --"

  run "$TEST_PROJECT/upload" -- --help
  assert_status 1
  assert_output_contains "Unexpected arguments: --help"

  run "$TEST_PROJECT/archive-reports" -- --archive 0
  assert_status 2
  assert_output_contains "Unexpected arguments: --archive 0"

  run "$TEST_PROJECT/services/generate-and-upload" -- --help
  assert_status 2
  assert_output_contains "Error: Unknown option: --"
}

@test "archive service leaves archive option validation to the root entrypoint" {
  # The archive wrapper's pass-through parser differs intentionally from the
  # generate/upload wrapper's service-specific parser.
  install_workflow_stubs
  write_monitoring_env

  run "$TEST_PROJECT/services/archive-reports" \
    --healthcheck-url-env HEALTHCHECKS_ARCHIVE_URL \
    --future-option value

  assert_status 0
  assert_file_content "$MOCK_STATE_DIR/workflow/calls" \
    $'archive-reports\t--future-option\tvalue'
}
