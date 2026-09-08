#!/usr/bin/env bash

mock_begin_call() {
  local command_name="$1"
  local command_dir
  local count=0
  local counter_file

  : "${MOCK_STATE_DIR:?MOCK_STATE_DIR must be set}"

  command_dir="$MOCK_STATE_DIR/$command_name"
  counter_file="$command_dir/count"
  mkdir -p -- "$command_dir"

  if [[ -f "$counter_file" ]]; then
    IFS= read -r count < "$counter_file"
  fi

  count=$((count + 1))
  printf '%s\n' "$count" > "$counter_file"
  mkdir -p -- "$command_dir/$count"
  printf '%s\n' "$count" >> "$command_dir/calls"
  printf '%s\n' "$command_dir/$count"
}

mock_record_args() {
  local output_file="$1"
  shift

  : > "$output_file"
  printf '%s\n' "$@" > "$output_file"
}

mock_list_contains() {
  local list=" $1 "
  local value="$2"

  [[ "$list" == *" $value "* ]]
}
