#!/usr/bin/env bash
set -u
set -o pipefail

usage() {
  cat <<'EOF'
Usage: ./upload.sh [--help] [-h HOST] [-P PORT] [-v]

Uploads the latest generated CSV for each supported report in ./data:
  holds         -> /Holds
  renew         -> /Renew
  overdue       -> /Overdue
  text-patrons  -> /text_patrons

The script loads FTPS settings from ./.env in the project root.

Required .env variables:
  FTPS_USERNAME
  FTPS_PASSWORD

Optional .env variables:
  FTPS_HOST  FTPS host (default: ftp.shoutbomb.com)
  FTPS_PORT  FTPS port (default: 990)

Options:
  -h HOST    FTPS host override
  -P PORT    FTPS port override
  -v         Verbose curl output
  --help     Show this help text
EOF
}

load_env_file() {
  local env_file="$1"
  local source_status

  if [[ ! -f "$env_file" ]]; then
    echo "Error: Environment file not found: $env_file" >&2
    cat >&2 <<'EOF'

Create the file with FTPS settings, for example:
  FTPS_HOST=ftp.shoutbomb.com
  FTPS_PORT=990
  FTPS_USERNAME=your_username
  FTPS_PASSWORD=secret
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

check_ftps_env() {
  local env_file="$1"
  local required_vars=(FTPS_USERNAME FTPS_PASSWORD)
  local missing_vars=()
  local var

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing_vars+=("$var")
    fi
  done

  if [[ ${#missing_vars[@]} -ne 0 ]]; then
    echo "Error: Missing required FTPS settings in $env_file:" >&2
    printf '  %s\n' "${missing_vars[@]}" >&2
    cat >&2 <<'EOF'

Update the file so it contains values for:
  FTPS_USERNAME
  FTPS_PASSWORD
EOF
    return 1
  fi
}

find_latest_report_file() {
  local report_name="$1"
  local data_dir="$2"
  local file
  local basename
  local epoch
  local epoch_number
  local latest_epoch=-1
  local latest_file=""

  shopt -s nullglob
  for file in "$data_dir"/"$report_name"-*.csv; do
    basename="$(basename "$file")"

    if [[ "$basename" =~ ^${report_name}-([0-9]+)\.csv$ ]]; then
      epoch="${BASH_REMATCH[1]}"
      epoch_number=$((10#$epoch))

      if (( epoch_number > latest_epoch )); then
        latest_epoch=$epoch_number
        latest_file="$file"
      fi
    fi
  done
  shopt -u nullglob

  if [[ -z "$latest_file" ]]; then
    return 1
  fi

  printf '%s\n' "$latest_file"
}

upload_file() {
  local local_file="$1"
  local remote_path="$2"
  local remote_url="ftps://${HOST}:${PORT}${remote_path%/}/"
  local curl_args=(
    --insecure
    --ftp-ssl-reqd
    --user "${FTPS_USERNAME}:${FTPS_PASSWORD}"
    --quote "PROT P"
    -T "$local_file"
    "$remote_url"
  )

  if [[ "$VERBOSE" -eq 1 ]]; then
    curl_args=(-v "${curl_args[@]}")
  fi

  curl "${curl_args[@]}"
}

HOST=""
PORT=""
VERBOSE=0

for arg in "$@"; do
  if [[ "$arg" == "--help" ]]; then
    usage
    exit 0
  fi
done

while getopts ":h:P:v" opt; do
  case "$opt" in
    h) HOST="$OPTARG" ;;
    P) PORT="$OPTARG" ;;
    v) VERBOSE=1 ;;
    :)
      echo "Error: Option -$OPTARG requires a value." >&2
      usage >&2
      exit 1
      ;;
    \?)
      echo "Error: Invalid option -$OPTARG" >&2
      usage >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

if [[ $# -gt 0 ]]; then
  echo "Error: Unexpected arguments: $*" >&2
  usage >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="$script_dir/.env"
data_dir="$script_dir/data"

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl was not found on PATH." >&2
  exit 127
fi

if ! load_env_file "$env_file"; then
  exit 1
fi

if ! check_ftps_env "$env_file"; then
  exit 1
fi

HOST="${HOST:-${FTPS_HOST:-ftp.shoutbomb.com}}"
PORT="${PORT:-${FTPS_PORT:-990}}"

report_names=(holds renew overdue text-patrons)
remote_paths=(/Holds /Renew /Overdue /text_patrons)
had_failure=0

for i in "${!report_names[@]}"; do
  report_name="${report_names[$i]}"
  remote_path="${remote_paths[$i]}"

  if latest_file="$(find_latest_report_file "$report_name" "$data_dir")"; then
    echo "Uploading $latest_file -> $remote_path"

    if upload_file "$latest_file" "$remote_path"; then
      echo "Upload complete: $(basename "$latest_file") -> $remote_path"
    else
      echo "Error: Failed to upload $latest_file -> $remote_path" >&2
      had_failure=1
    fi
  else
    echo "Error: Missing report file for $report_name. Expected a file matching $data_dir/${report_name}-<epoch>.csv" >&2
    had_failure=1
  fi
done

if [[ $had_failure -ne 0 ]]; then
  echo "Completed with one or more upload failures." >&2
  exit 1
fi

echo "All uploads completed successfully."
