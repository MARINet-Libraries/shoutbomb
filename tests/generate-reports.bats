#!/usr/bin/env bats

load test_helper

setup() {
  setup_project_fixture
}

@test "generate-reports discovers every SQL report and uses one timestamp" {
  write_pg_env

  run bash -c 'cd -- "$1" && shift && exec "$@"' \
    test-runner "$TEST_OUTSIDE_DIR" "$TEST_PROJECT/generate-reports"

  assert_status 0
  assert_output_contains "All queries completed successfully."
  assert_call_count psql 5
  assert_file_content "$MOCK_STATE_DIR/psql/reports" \
    $'holds\nloanrules\noverdue\nrenew\ntext-patrons'

  local report_name
  for report_name in holds loanrules overdue renew text-patrons; do
    assert_file_exists "$TEST_PROJECT/data/$report_name-1700000000.csv"
  done

  assert_mock_arg psql 1 "--csv"
  assert_mock_arg psql 1 "--set"
  assert_mock_arg psql 1 "ON_ERROR_STOP=1"
  refute_mock_arg psql 1 "--tuples-only"
  assert_file_contains "$(mock_call_dir psql 1)/environment" "PGHOST=test-db.example"
  assert_file_content "$TEST_PROJECT/data/holds-1700000000.csv" \
    $'header_holds\nvalue_holds'
}

@test "generate-reports limits generation and omits headers when requested" {
  write_pg_env

  run "$TEST_PROJECT/generate-reports" \
    --no-headers \
    --reports renew holds

  assert_status 0
  assert_call_count psql 2
  assert_file_content "$MOCK_STATE_DIR/psql/reports" $'holds\nrenew'
  assert_mock_arg psql 1 "--tuples-only"
  assert_mock_arg psql 2 "--tuples-only"
  assert_file_exists "$TEST_PROJECT/data/holds-1700000000.csv"
  assert_file_exists "$TEST_PROJECT/data/renew-1700000000.csv"
  assert_file_not_exists "$TEST_PROJECT/data/overdue-1700000000.csv"
}

@test "generate-reports rejects every invalid report before loading configuration" {
  run "$TEST_PROJECT/generate-reports" --reports missing holds.sql

  assert_status 1
  assert_output_contains "Error: Invalid report name(s) for --reports:"
  assert_output_contains "missing"
  assert_output_contains "holds.sql"
  assert_output_contains "Valid reports:"
  assert_call_count psql 0
}

@test "generate-reports reports shared environment-loading failures without running psql" {
  run "$TEST_PROJECT/generate-reports" --reports holds

  assert_status 1
  assert_output_contains "Error: Environment file not found: $TEST_PROJECT/.env"
  assert_output_contains "Create the file with PostgreSQL connection settings"
  assert_call_count psql 0

  printf '%s\n' 'false' > "$TEST_PROJECT/.env"

  run "$TEST_PROJECT/generate-reports" --reports holds

  assert_status 1
  assert_output_contains "Error: Failed to load environment file: $TEST_PROJECT/.env"
  assert_call_count psql 0
}

@test "generate-reports reports missing PostgreSQL settings without running psql" {
  cat > "$TEST_PROJECT/.env" <<'EOF'
PGHOST=test-db.example
PGPORT=5432
PGDATABASE=test_database
PGUSER=test_user
EOF

  run "$TEST_PROJECT/generate-reports" --reports holds

  assert_status 1
  assert_output_contains "Missing required PostgreSQL settings"
  assert_output_contains "PGPASSWORD"
  assert_call_count psql 0
}

@test "generate-reports removes failed output, continues, and returns failure" {
  write_pg_env
  export MOCK_PSQL_FAIL_REPORTS="holds"

  run "$TEST_PROJECT/generate-reports" --reports holds renew

  assert_status 1
  assert_output_contains "Failed $TEST_PROJECT/sql/holds.sql"
  assert_output_contains "Completed with one or more failures."
  assert_call_count psql 2
  assert_file_not_exists "$TEST_PROJECT/data/holds-1700000000.csv"
  assert_file_exists "$TEST_PROJECT/data/renew-1700000000.csv"
}

@test "generate-reports preserves its documented usage-error status" {
  # Characterization of the current CLI contract.
  run "$TEST_PROJECT/generate-reports" --unknown

  assert_status 2
  assert_output_contains "Unknown option: --unknown"
}
