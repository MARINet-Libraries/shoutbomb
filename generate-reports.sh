#!/usr/bin/env bash
set -u
set -o pipefail

usage() {
  cat <<'EOF'
Usage: ./generate-reports.sh [--headers|--no-headers] [--help]

Runs every .sql file in ./sql using psql and writes CSV output to ./data.
The script loads PostgreSQL connection details from ./.env in the project root.
The .env file must define: PGHOST, PGPORT, PGDATABASE, PGUSER, and PGPASSWORD.
Output filenames use the pattern <report-name>-<epoch-seconds>.csv.

Options:
  --headers     Include CSV headers (default)
  --no-headers  Omit CSV headers
  -h, --help    Show this help text
EOF
}

load_env_file() {
  local env_file="$1"
  local source_status

  if [[ ! -f "$env_file" ]]; then
    echo "Error: Environment file not found: $env_file" >&2
    cat >&2 <<'EOF'

Create the file with PostgreSQL connection settings, for example:
  PGHOST=hostname
  PGPORT=5432
  PGDATABASE=database_name
  PGUSER=username
  PGPASSWORD=secret
EOF
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

check_pg_env() {
  local env_file="$1"
  local required_vars=(PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD)
  local missing_vars=()
  local var

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing_vars+=("$var")
    fi
  done

  if [[ ${#missing_vars[@]} -ne 0 ]]; then
    echo "Error: Missing required PostgreSQL settings in $env_file:" >&2
    printf '  %s\n' "${missing_vars[@]}" >&2
    cat >&2 <<'EOF'

Update the file so it contains values for:
  PGHOST
  PGPORT
  PGDATABASE
  PGUSER
  PGPASSWORD
EOF
    return 1
  fi
}

include_headers=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --headers)
      include_headers=1
      ;;
    --no-headers)
      include_headers=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="$script_dir/.env"

if ! command -v psql >/dev/null 2>&1; then
  echo "Error: psql was not found on PATH." >&2
  exit 127
fi

if ! load_env_file "$env_file"; then
  exit 1
fi

if ! check_pg_env "$env_file"; then
  exit 1
fi

sql_dir="$script_dir/sql"
data_dir="$script_dir/data"

[[ -d "$sql_dir" ]] || {
  echo "Error: SQL directory not found: $sql_dir" >&2
  exit 1
}

mkdir -p "$data_dir"

shopt -s nullglob
sql_files=("$sql_dir"/*.sql)
shopt -u nullglob

if [[ ${#sql_files[@]} -eq 0 ]]; then
  echo "Error: No .sql files found in $sql_dir" >&2
  exit 1
fi

timestamp="$(date +%s)"
psql_args=(
  -X
  --set ON_ERROR_STOP=1
  --pset footer=off
  --csv
)

if [[ $include_headers -eq 0 ]]; then
  psql_args+=(--tuples-only)
fi

had_failure=0

for sql_file in "${sql_files[@]}"; do
  report_name="$(basename "$sql_file" .sql)"
  output_file="$data_dir/${report_name}-${timestamp}.csv"

  echo "Running $sql_file -> $output_file"

  if psql "${psql_args[@]}" --file "$sql_file" > "$output_file"; then
    echo "Wrote $output_file"
  else
    echo "Failed $sql_file" >&2
    rm -f "$output_file"
    had_failure=1
  fi
done

if [[ $had_failure -ne 0 ]]; then
  echo "Completed with one or more failures." >&2
  exit 1
fi

echo "All queries completed successfully."
