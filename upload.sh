#!/usr/bin/env bash
set -u
set -o pipefail

usage() {
  cat <<'EOF'
Usage: ./upload.sh [--reports REPORT [REPORT ...]] [--help] [-H HOST] [-P PORT] [-v]

Uploads the latest generated CSV for each supported report in ./data by default:
  holds         -> /Holds
  renew         -> /Renew
  overdue       -> /Overdue
  text-patrons  -> /text_patrons

The script loads SSH/SFTP settings from ./.env in the project root.
Strict host key checking is always enabled.
Remote destination directories must already exist.

Required .env variables:
  SSH_USERNAME
  SSH_IDENTITY_FILE     Absolute path to SSH private key

Optional .env variables:
  SSH_HOST              SSH host (default: ftp.shoutbomb.com)
  SSH_PORT              SSH port (default: 22)
  SSH_KNOWN_HOSTS_FILE  Absolute path to known_hosts override

Options:
  --reports REPORT [...]  Upload only the selected supported report basenames
  -h, --help             Show this help text
  -H, --host HOST        SSH host override
  -P, --port PORT        SSH port override
  -v, --verbose          Verbose sftp output
EOF
}

load_env_file() {
  local env_file="$1"
  local source_status

  if [[ ! -f "$env_file" ]]; then
    echo "Error: Environment file not found: $env_file" >&2
    cat >&2 <<'EOF'

Create the file with SSH/SFTP settings, for example:
  SSH_HOST=ftp.shoutbomb.com
  SSH_PORT=22
  SSH_USERNAME=your_username
  SSH_IDENTITY_FILE=/full/path/to/private_key
  # Optional:
  # SSH_KNOWN_HOSTS_FILE=/full/path/to/known_hosts

SSH_IDENTITY_FILE and SSH_KNOWN_HOSTS_FILE must use absolute paths.
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

check_absolute_path() {
  local description="$1"
  local path_value="$2"

  if [[ "$path_value" != /* ]]; then
    echo "Error: $description must be an absolute path: $path_value" >&2
    return 1
  fi
}

check_readable_file() {
  local description="$1"
  local file_path="$2"

  if [[ ! -f "$file_path" ]]; then
    echo "Error: $description not found: $file_path" >&2
    return 1
  fi

  if [[ ! -r "$file_path" ]]; then
    echo "Error: $description is not readable: $file_path" >&2
    return 1
  fi
}

check_ssh_env() {
  local env_file="$1"
  local required_vars=(SSH_USERNAME SSH_IDENTITY_FILE)
  local missing_vars=()
  local var

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing_vars+=("$var")
    fi
  done

  if [[ ${#missing_vars[@]} -ne 0 ]]; then
    echo "Error: Missing required SSH/SFTP settings in $env_file:" >&2
    printf '  %s\n' "${missing_vars[@]}" >&2
    cat >&2 <<'EOF'

Update the file so it contains values for:
  SSH_USERNAME
  SSH_IDENTITY_FILE
EOF
    return 1
  fi

  if ! check_absolute_path "SSH identity file" "$SSH_IDENTITY_FILE"; then
    return 1
  fi

  if ! check_readable_file "SSH identity file" "$SSH_IDENTITY_FILE"; then
    return 1
  fi

  if [[ -n "${SSH_KNOWN_HOSTS_FILE:-}" ]]; then
    if ! check_absolute_path "SSH known_hosts file" "$SSH_KNOWN_HOSTS_FILE"; then
      return 1
    fi

    if ! check_readable_file "SSH known_hosts file" "$SSH_KNOWN_HOSTS_FILE"; then
      return 1
    fi
  fi
}

check_port() {
  local port_value="$1"

  if [[ ! "$port_value" =~ ^[0-9]+$ ]]; then
    echo "Error: SSH port must be a number: $port_value" >&2
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

sftp_quote() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"

  printf '"%s"' "$value"
}

upload_file() {
  local local_file="$1"
  local remote_dir="$2"
  local remote_file="${remote_dir%/}/$(basename "$local_file")"
  local target="${SSH_USERNAME}@${HOST}"
  local sftp_args=(
    -b -
    -P "$PORT"
    -o BatchMode=yes
    -o StrictHostKeyChecking=yes
    -o IdentitiesOnly=yes
    -i "$SSH_IDENTITY_FILE"
  )

  if [[ -n "${SSH_KNOWN_HOSTS_FILE:-}" ]]; then
    sftp_args+=( -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS_FILE" )
  fi

  if [[ "$VERBOSE" -eq 1 ]]; then
    sftp_args=( -v "${sftp_args[@]}" )
  fi

  printf 'put %s %s\nbye\n' \
    "$(sftp_quote "$local_file")" \
    "$(sftp_quote "$remote_file")" | sftp "${sftp_args[@]}" "$target"
}

array_contains() {
  local needle="$1"
  shift
  local value

  for value in "$@"; do
    if [[ "$value" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

print_valid_reports() {
  local report_name

  echo "Valid reports:" >&2
  for report_name in "${supported_report_names[@]}"; do
    printf '  %s\n' "$report_name" >&2
  done
}

validate_requested_reports() {
  local invalid_reports=()
  local report_name

  for report_name in "${requested_reports[@]}"; do
    if ! array_contains "$report_name" "${supported_report_names[@]}"; then
      invalid_reports+=("$report_name")
    fi
  done

  if [[ ${#invalid_reports[@]} -ne 0 ]]; then
    echo "Error: Invalid report name(s) for --reports:" >&2
    printf '  %s\n' "${invalid_reports[@]}" >&2
    echo "Report names must be basenames such as holds, not filenames such as holds.sql." >&2
    print_valid_reports
    return 1
  fi
}

reports=(
  "holds:/Holds"
  "renew:/Renew"
  "overdue:/Overdue"
  "text-patrons:/text_patrons"
)
requested_reports=()
supported_report_names=()
selected_reports=()

for report in "${reports[@]}"; do
  supported_report_names+=("${report%%:*}")
done

HOST=""
PORT=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reports)
      shift
      if [[ $# -eq 0 || "$1" == -* ]]; then
        echo "Error: Option --reports requires at least one report name." >&2
        usage >&2
        exit 1
      fi

      while [[ $# -gt 0 && "$1" != -* ]]; do
        requested_reports+=("$1")
        shift
      done
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -H|--host)
      if [[ $# -lt 2 ]]; then
        echo "Error: Option $1 requires a value." >&2
        usage >&2
        exit 1
      fi
      HOST="$2"
      shift 2
      ;;
    -P|--port)
      if [[ $# -lt 2 ]]; then
        echo "Error: Option $1 requires a value." >&2
        usage >&2
        exit 1
      fi
      PORT="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "Error: Invalid option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      echo "Error: Unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  echo "Error: Unexpected arguments: $*" >&2
  usage >&2
  exit 1
fi

if [[ ${#requested_reports[@]} -eq 0 ]]; then
  selected_reports=("${reports[@]}")
else
  if ! validate_requested_reports; then
    exit 1
  fi

  for report in "${reports[@]}"; do
    report_name="${report%%:*}"

    if array_contains "$report_name" "${requested_reports[@]}"; then
      selected_reports+=("$report")
    fi
  done
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="$script_dir/.env"
data_dir="$script_dir/data"

if ! command -v sftp >/dev/null 2>&1; then
  echo "Error: sftp was not found on PATH." >&2
  exit 127
fi

if ! load_env_file "$env_file"; then
  exit 1
fi

if ! check_ssh_env "$env_file"; then
  exit 1
fi

HOST="${HOST:-${SSH_HOST:-ftp.shoutbomb.com}}"
PORT="${PORT:-${SSH_PORT:-22}}"

if ! check_port "$PORT"; then
  exit 1
fi

had_failure=0

for report in "${selected_reports[@]}"; do
  report_name="${report%%:*}"
  remote_path="${report#*:}"

  if latest_file="$(find_latest_report_file "$report_name" "$data_dir")"; then
    remote_file="${remote_path%/}/$(basename "$latest_file")"
    echo "Uploading $latest_file -> $remote_file"

    if upload_file "$latest_file" "$remote_path"; then
      echo "Upload complete: $(basename "$latest_file") -> $remote_file"
    else
      echo "Error: Failed to upload $latest_file -> $remote_file" >&2
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
