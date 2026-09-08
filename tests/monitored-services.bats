#!/usr/bin/env bats

load test_helper

setup() {
  setup_project_fixture
  install_workflow_stubs
  write_monitoring_env
}

@test "generate-and-upload passes independent report lists and records successful lifecycle" {
  run "$TEST_PROJECT/services/generate-and-upload" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL \
    --generate-reports holds overdue loanrules \
    --upload-reports holds overdue

  assert_status 0
  assert_file_content "$MOCK_STATE_DIR/workflow/calls" \
    $'generate-reports\t--reports\tholds\toverdue\tloanrules\nupload\t--reports\tholds\toverdue'
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/test-id/start\nhttps://hc.example.test/test-id'
  assert_file_content "$(mock_call_dir curl 1)/args" \
    $'-fsS\n--connect-timeout\n2\n--max-time\n5\n--retry\n5\n--retry-max-time\n30\n-o\n/dev/null\nhttps://hc.example.test/test-id/start'
  assert_file_content "$MOCK_STATE_DIR/logger/tags" \
    $'shoutbomb-generate-reports\nshoutbomb-upload'
  assert_file_content "$MOCK_STATE_DIR/logger/1/stdin" \
    "mock output from generate-reports"
  assert_file_content "$MOCK_STATE_DIR/logger/2/stdin" \
    "mock output from upload"
  assert_file_content "$MOCK_STATE_DIR/workflow/1/cwd" "$TEST_PROJECT"
  assert_file_content "$MOCK_STATE_DIR/workflow/2/cwd" "$TEST_PROJECT"
  refute_output_contains "https://hc.example.test/test-id"
  refute_file_contains "$MOCK_STATE_DIR/workflow/calls" "https://hc.example.test/test-id"
}

@test "generate-and-upload skips upload, preserves generation failure, and pings fail" {
  export MOCK_GENERATE_REPORTS_STATUS=7

  run "$TEST_PROJECT/services/generate-and-upload" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL

  assert_status 7
  assert_file_content "$MOCK_STATE_DIR/workflow/calls" "generate-reports"
  assert_file_content "$MOCK_STATE_DIR/logger/tags" "shoutbomb-generate-reports"
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/test-id/start\nhttps://hc.example.test/test-id/fail'
}

@test "generate-and-upload preserves upload failure and sends one fail ping" {
  export MOCK_UPLOAD_STATUS=9

  run "$TEST_PROJECT/services/generate-and-upload" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL

  assert_status 9
  assert_file_content "$MOCK_STATE_DIR/workflow/calls" \
    $'generate-reports\nupload'
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/test-id/start\nhttps://hc.example.test/test-id/fail'
}

@test "Healthchecks failures remain best-effort" {
  export MOCK_CURL_STATUS=22

  run "$TEST_PROJECT/services/generate-and-upload" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL

  assert_status 0
  assert_call_count curl 2
  assert_file_content "$MOCK_STATE_DIR/workflow/calls" \
    $'generate-reports\nupload'
}

@test "logger pipeline failure gates upload and remains the workflow status" {
  export MOCK_LOGGER_FAIL_TAG=shoutbomb-generate-reports
  export MOCK_LOGGER_FAILURE_STATUS=24

  run "$TEST_PROJECT/services/generate-and-upload" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL

  assert_status 24
  assert_file_content "$MOCK_STATE_DIR/workflow/calls" "generate-reports"
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/test-id/start\nhttps://hc.example.test/test-id/fail'
}

@test "generate-and-upload rejects invalid Healthchecks variable names before workflow" {
  run "$TEST_PROJECT/services/generate-and-upload" \
    --healthcheck-url-env UNAPPROVED_URL

  assert_status 1
  assert_output_contains "Invalid Healthchecks.io variable name"
  assert_call_count curl 0
  assert_file_not_exists "$MOCK_STATE_DIR/workflow/calls"
}

@test "generate-and-upload preserves service usage-error status" {
  # Characterization of the current CLI contract.
  run "$TEST_PROJECT/services/generate-and-upload" --unknown

  assert_status 2
  assert_output_contains "Error: Unknown option: --unknown"
  assert_call_count curl 0
}

@test "archive service passes arguments unchanged and records successful lifecycle" {
  run "$TEST_PROJECT/services/archive-reports" \
    --healthcheck-url-env HEALTHCHECKS_ARCHIVE_URL \
    --dry-run \
    --archive 2 \
    --delete-archived 30

  assert_status 0
  assert_file_content "$MOCK_STATE_DIR/workflow/calls" \
    $'archive-reports\t--dry-run\t--archive\t2\t--delete-archived\t30'
  assert_file_content "$MOCK_STATE_DIR/logger/tags" \
    "shoutbomb-archive-reports"
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/archive-id/start\nhttps://hc.example.test/archive-id'
}

@test "archive service preserves archive failure and sends fail ping" {
  export MOCK_ARCHIVE_REPORTS_STATUS=13

  run "$TEST_PROJECT/services/archive-reports" \
    --healthcheck-url-env HEALTHCHECKS_ARCHIVE_URL \
    --archive 2

  assert_status 13
  assert_file_content "$MOCK_STATE_DIR/workflow/calls" \
    $'archive-reports\t--archive\t2'
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/archive-id/start\nhttps://hc.example.test/archive-id/fail'
}
