#!/usr/bin/env bats

load test_helper

setup() {
  setup_project_fixture
  write_ssh_env
  monthly_dir="$TEST_PROJECT/data/monthly-reports"
  receipts="$monthly_dir/.arrival-state/pending"
  current=sb_generate_monthly_report_feb88521e8_2026-11-05_00_10_18.csv
  older=sb_generate_monthly_report_other-id_2026-10-04_12_00_00.csv
  future=sb_generate_monthly_report_other-id_2026-12-04_12_00_00.csv
  export MOCK_DATE_MONTH=2026-11
  mkdir -p -- "$MOCK_STATE_DIR/monthly-remote"
  cat >> "$TEST_PROJECT/.env" <<EOF
HEALTHCHECKS_TEST_URL=https://hc.example.test/daily
HEALTHCHECKS_MONTHLY_ARRIVAL_URL=https://hc.example.test/arrival
SHOUTBOMB_LOGGER_PATH='$MOCK_BIN/logger'
EOF
}

add_file() {
  printf 'monthly fixture\n' > "$MOCK_STATE_DIR/monthly-remote/$1"
  printf '%s\n' "$1" >> "$MOCK_STATE_DIR/monthly-listing"
}

poll() {
  run "$TEST_PROJECT/services/download-monthly-reports" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL \
    --arrival-healthcheck-url-env HEALTHCHECKS_MONTHLY_ARRIVAL_URL "$@"
}

@test "arrival pings only for current-month completed downloads, not backfills or repeats" {
  add_file "$current"
  add_file "$older"
  add_file "$future"

  poll

  assert_status 0
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/daily/start\nhttps://hc.example.test/arrival\nhttps://hc.example.test/daily'
  assert_file_exists "$monthly_dir/$current"
  assert_file_exists "$monthly_dir/$older"
  assert_file_not_exists "$receipts/$current"
  assert_file_not_exists "$receipts/$older"
  assert_file_not_exists "$receipts/$future"
  refute_file_contains "$MOCK_STATE_DIR/sftp/transcript" 'https://'
  refute_file_contains "$(mock_call_dir logger 2)/stdin" 'https://'
  assert_directory_not_exists "$monthly_dir/.arrival.lock"

  poll
  assert_status 0
  assert_call_count curl 5
  assert_call_count sftp 5
}

@test "arrival does not ping for only historical or future files or an empty listing" {
  poll
  assert_status 0
  assert_call_count curl 2
  add_file "$older"
  add_file "$future"
  poll
  assert_status 0
  assert_call_count curl 4
  refute_file_contains "$MOCK_STATE_DIR/curl/urls" '/arrival'
}

@test "arrival retries a failed ping on a no-op day without redownloading" {
  add_file "$current"
  export MOCK_CURL_FAIL_MATCH=/arrival

  poll

  assert_status 0
  assert_file_content "$receipts/$current" 2026-11
  assert_call_count sftp 2
  assert_file_contains "$(mock_call_dir logger 2)/stdin" 'pending receipts will retry'
  unset MOCK_CURL_FAIL_MATCH

  poll

  assert_status 0
  assert_call_count sftp 3
  assert_call_count curl 6
  assert_file_not_exists "$receipts/$current"

  poll
  assert_status 0
  assert_call_count curl 8
}

@test "arrival expires failed notifications at month rollover instead of masking the next month" {
  add_file "$current"
  export MOCK_CURL_FAIL_MATCH=/arrival
  poll
  assert_status 0
  assert_file_exists "$receipts/$current"
  unset MOCK_CURL_FAIL_MATCH
  export MOCK_DATE_MONTH=2026-12

  poll

  assert_status 0
  assert_call_count curl 5
  assert_file_not_exists "$receipts/$current"
  add_file "$future"
  poll
  assert_status 0
  assert_call_count curl 8
}

@test "arrival accepts completed current-month files despite failure of another transfer" {
  add_file "$current"
  add_file "$older"
  export MOCK_SFTP_FAIL_MATCH="$older"

  poll

  assert_status 1
  assert_file_exists "$monthly_dir/$current"
  assert_file_not_exists "$monthly_dir/$older"
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/daily/start\nhttps://hc.example.test/arrival\nhttps://hc.example.test/daily/fail'
}

@test "arrival never pings for an incomplete current-month download" {
  add_file "$current"
  export MOCK_SFTP_FAIL_MATCH="$current"

  poll

  assert_status 1
  assert_file_not_exists "$receipts/$current"
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/daily/start\nhttps://hc.example.test/daily/fail'
}

@test "arrival ignores crash-gap receipts without completed CSVs and recovers completed ones" {
  mkdir -p -- "$receipts"
  printf '2026-11\n' > "$receipts/$current"

  poll
  assert_status 0
  assert_call_count curl 2
  assert_file_exists "$receipts/$current"

  printf 'completed fixture\n' > "$monthly_dir/$current"
  export MOCK_SFTP_FAIL_MATCH=@ls
  poll
  assert_status 1
  assert_call_count curl 5
  assert_file_not_exists "$receipts/$current"
  assert_file_content "$MOCK_STATE_DIR/curl/urls" \
    $'https://hc.example.test/daily/start\nhttps://hc.example.test/daily\nhttps://hc.example.test/daily/start\nhttps://hc.example.test/arrival\nhttps://hc.example.test/daily/fail'
}

@test "arrival uses the current calendar month rather than hard-coding the example date" {
  export MOCK_DATE_MONTH=2026-12
  add_file "$current"
  add_file "$future"

  poll

  assert_status 0
  assert_call_count curl 3
  assert_file_contains "$(mock_call_dir logger 2)/stdin" '1 newly downloaded report(s)'
  assert_file_not_exists "$receipts/$current"
  assert_file_not_exists "$receipts/$future"
}

@test "invalid calendar month prevents receipt and CSV publication without an arrival ping" {
  export MOCK_DATE_MONTH=invalid
  add_file "$current"

  poll

  assert_status 1
  assert_file_not_exists "$monthly_dir/$current"
  assert_file_not_exists "$receipts/$current"
  refute_file_contains "$MOCK_STATE_DIR/curl/urls" '/arrival'
  export MOCK_DATE_MONTH=2026-11
  poll
  assert_status 0
  assert_file_exists "$monthly_dir/$current"
  assert_call_count curl 5
}

@test "arrival service rejects invalid, missing, duplicate, or shared URL settings before any ping" {
  run "$TEST_PROJECT/services/download-monthly-reports" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL --arrival-healthcheck-url-env
  assert_status 2
  poll --arrival-healthcheck-url-env HEALTHCHECKS_MONTHLY_ARRIVAL_URL
  assert_status 2
  run "$TEST_PROJECT/services/download-monthly-reports" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL --arrival-healthcheck-url-env PRIVATE_URL
  assert_status 1
  run "$TEST_PROJECT/services/download-monthly-reports" \
    --healthcheck-url-env HEALTHCHECKS_TEST_URL --arrival-healthcheck-url-env HEALTHCHECKS_MISSING_URL
  assert_status 1
  printf 'HEALTHCHECKS_MONTHLY_ARRIVAL_URL=https://hc.example.test/daily/\n' >> "$TEST_PROJECT/.env"
  poll
  assert_status 1
  assert_output_contains 'must use different Healthchecks.io URLs'
  assert_call_count curl 0
  assert_call_count sftp 0
}

@test "receipt interface records only completed new basenames and rejects relative or conflicting paths" {
  add_file "$current"
  add_file "$older"
  export MOCK_SFTP_FAIL_MATCH="$older"

  run "$TEST_PROJECT/download-monthly-reports" --receipt-dir "$receipts"

  assert_status 1
  assert_file_content "$receipts/$current" 2026-11
  assert_file_not_exists "$receipts/$older"
  assert_file_exists "$monthly_dir/$current"
  run "$TEST_PROJECT/download-monthly-reports" --receipt-dir relative
  assert_status 2
  run "$TEST_PROJECT/download-monthly-reports" --receipt-dir "$monthly_dir"
  assert_status 1
  assert_directory_not_exists "$monthly_dir/.download.lock"
}

@test "receipt publication failure prevents CSV publication and is retried next time" {
  add_file "$current"
  mkdir -p -- "$receipts/$current"

  poll

  assert_status 1
  assert_file_not_exists "$monthly_dir/$current"
  refute_file_contains "$MOCK_STATE_DIR/curl/urls" '/arrival'
  rmdir -- "$receipts/$current"
  poll
  assert_status 0
  assert_file_exists "$monthly_dir/$current"
  assert_file_not_exists "$receipts/$current"
}

@test "arrival lock contention defers notification but preserves successful download status" {
  add_file "$current"
  mkdir -p -- "$monthly_dir/.arrival.lock"

  poll

  assert_status 0
  assert_file_content "$receipts/$current" 2026-11
  assert_call_count curl 2
  assert_directory_exists "$monthly_dir/.arrival.lock"
  rmdir -- "$monthly_dir/.arrival.lock"
  poll
  assert_status 0
  assert_call_count curl 5
  assert_file_not_exists "$receipts/$current"
}

@test "arrival remains independent of logger failure and manual downloads do not fabricate arrivals" {
  add_file "$current"
  run "$TEST_PROJECT/download-monthly-reports"
  assert_status 0
  poll
  assert_status 0
  assert_call_count curl 2
  rm -- "$monthly_dir/$current"
  export MOCK_LOGGER_STATUS=24
  poll
  assert_status 24
  assert_call_count curl 5
  assert_file_not_exists "$receipts/$current"
}
