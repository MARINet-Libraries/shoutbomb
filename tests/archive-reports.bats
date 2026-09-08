#!/usr/bin/env bats

load test_helper

setup() {
  setup_project_fixture
  export MOCK_DATE_EPOCH=1700000000
}

@test "archive-reports uses the embedded epoch with an inclusive day boundary" {
  create_report_file holds 1699827199 older
  create_report_file overdue 1699827200 boundary
  create_report_file renew 1699827201 recent
  create_report_file text-patrons 1700000001 future
  touch -t 203001010000 "$TEST_PROJECT/data/holds-1699827199.csv"

  run bash -c 'cd -- "$1" && shift && exec "$@"' \
    test-runner "$TEST_OUTSIDE_DIR" "$TEST_PROJECT/archive-reports" --archive 2

  assert_status 0
  assert_file_not_exists "$TEST_PROJECT/data/holds-1699827199.csv"
  assert_file_not_exists "$TEST_PROJECT/data/overdue-1699827200.csv"
  assert_file_exists "$TEST_PROJECT/data/_archive/holds-1699827199.csv"
  assert_file_exists "$TEST_PROJECT/data/_archive/overdue-1699827200.csv"
  assert_file_exists "$TEST_PROJECT/data/renew-1699827201.csv"
  assert_file_exists "$TEST_PROJECT/data/text-patrons-1700000001.csv"
  assert_output_contains "Archived: data/holds-1699827199.csv"
  assert_output_contains "Archived: 2 file(s)"
}

@test "archive-reports applies the same inclusive epoch boundary when deleting" {
  create_archived_report_file holds 1699827199 older
  create_archived_report_file overdue 1699827200 boundary
  create_archived_report_file renew 1699827201 recent
  create_archived_report_file text-patrons 1700000001 future

  run "$TEST_PROJECT/archive-reports" --delete-archived 2

  assert_status 0
  assert_file_not_exists "$TEST_PROJECT/data/_archive/holds-1699827199.csv"
  assert_file_not_exists "$TEST_PROJECT/data/_archive/overdue-1699827200.csv"
  assert_file_exists "$TEST_PROJECT/data/_archive/renew-1699827201.csv"
  assert_file_exists "$TEST_PROJECT/data/_archive/text-patrons-1700000001.csv"
  assert_output_contains "Deleted archived: 2 file(s)"
}

@test "archive-reports deletes archived collisions before moving active files" {
  create_report_file holds 1600000000 active-content
  create_archived_report_file holds 1600000000 archived-content

  run "$TEST_PROJECT/archive-reports" --archive 0 --delete-archived 0

  assert_status 0
  assert_file_not_exists "$TEST_PROJECT/data/holds-1600000000.csv"
  assert_file_content "$TEST_PROJECT/data/_archive/holds-1600000000.csv" "active-content"
  assert_output_contains "Deleted archived file: data/_archive/holds-1600000000.csv"
  assert_output_contains "Archived: data/holds-1600000000.csv"
  if [[ "$output" != *"Deleted archived file:"*"Archived:"* ]]; then
    printf 'Expected deletion output before archive output.\nActual output:\n%s\n' "$output" >&2
    return 1
  fi
  refute_output_contains "Overwriting archived file"
}

@test "archive-reports dry-run suppresses collisions cleared by planned deletions" {
  create_report_file holds 1600000000 active-content
  create_archived_report_file holds 1600000000 archived-content

  run "$TEST_PROJECT/archive-reports" \
    --dry-run \
    --archive 0 \
    --delete-archived 0

  assert_status 0
  assert_output_contains "Would delete archived file: data/_archive/holds-1600000000.csv"
  assert_output_contains "Would archive: data/holds-1600000000.csv"
  refute_output_contains "Overwriting archived file"
  assert_file_content "$TEST_PROJECT/data/holds-1600000000.csv" "active-content"
  assert_file_content "$TEST_PROJECT/data/_archive/holds-1600000000.csv" "archived-content"
}

@test "archive-reports warns and overwrites an archive collision" {
  create_report_file holds 1600000000 replacement
  create_archived_report_file holds 1600000000 original

  run "$TEST_PROJECT/archive-reports" --archive 0

  assert_status 0
  assert_output_contains "Warning: Overwriting archived file"
  assert_file_content "$TEST_PROJECT/data/_archive/holds-1600000000.csv" "replacement"
}

@test "archive-reports dry-run does not create, move, or delete anything" {
  create_report_file text-patrons 1600000000 active
  rmdir "$TEST_PROJECT/data/_archive"

  run "$TEST_PROJECT/archive-reports" \
    --dry-run \
    --delete-archived 30 \
    --archive 0

  assert_status 0
  assert_output_contains "Dry-run mode: no files will be changed."
  assert_output_contains "No archive directory present; nothing to delete"
  assert_output_contains "Would create archive directory"
  assert_output_contains "Would archive: data/text-patrons-1600000000.csv"
  assert_file_exists "$TEST_PROJECT/data/text-patrons-1600000000.csv"
  assert_directory_not_exists "$TEST_PROJECT/data/_archive"
}

@test "archive-reports warns and skips malformed files, symlinks, and directories" {
  printf '%s\n' malformed > "$TEST_PROJECT/data/manual-export.csv"
  printf '%s\n' target > "$BATS_TEST_TMPDIR/symlink-target"
  ln -s "$BATS_TEST_TMPDIR/symlink-target" "$TEST_PROJECT/data/link-1600000000.csv"
  mkdir "$TEST_PROJECT/data/directory-1600000000.csv"
  printf '%s\n' ignored > "$TEST_PROJECT/data/not-a-csv.txt"

  run "$TEST_PROJECT/archive-reports" --archive 0

  assert_status 0
  assert_output_contains "Skipping unexpected filename: data/manual-export.csv"
  assert_output_contains "Skipping non-regular file: data/link-1600000000.csv"
  assert_output_contains "Skipping non-regular file: data/directory-1600000000.csv"
  assert_output_contains "Warnings: 3"
  assert_output_contains "Skipped: 3"
  assert_file_exists "$TEST_PROJECT/data/manual-export.csv"
  [[ -L "$TEST_PROJECT/data/link-1600000000.csv" ]]
  assert_directory_exists "$TEST_PROJECT/data/directory-1600000000.csv"
  assert_file_exists "$TEST_PROJECT/data/not-a-csv.txt"
}

@test "archive-reports treats a missing archive directory as nothing to delete" {
  rmdir "$TEST_PROJECT/data/_archive"

  run "$TEST_PROJECT/archive-reports" --delete-archived 30

  assert_status 0
  assert_output_contains "No archive directory present; nothing to delete"
  assert_output_contains "Deleted archived: 0 file(s)"
}

@test "archive-reports preserves usage status for missing and invalid options" {
  # Characterization of the current CLI contract.
  run "$TEST_PROJECT/archive-reports"
  assert_status 2
  assert_output_contains "At least one of --archive or --delete-archived is required"

  run "$TEST_PROJECT/archive-reports" --archive -1
  assert_status 2
  assert_output_contains "requires a non-negative integer"

  run "$TEST_PROJECT/archive-reports" --unknown
  assert_status 2
  assert_output_contains "Error: Invalid option: --unknown"
}
