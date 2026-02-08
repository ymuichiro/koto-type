#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${ROOT_DIR}/artifacts/runtime/${TIMESTAMP}"
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--dry-run] [--output-dir DIR]

Collect runtime and crash-related artifacts into a timestamped folder.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --output-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

run_cmd() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

copy_glob_limited() {
  local src_glob="$1"
  local dest_dir="$2"
  local max_files="$3"
  mkdir -p "$dest_dir"
  local count=0
  shopt -s nullglob
  for file in $src_glob; do
    if [[ $count -ge $max_files ]]; then
      break
    fi
    if [[ -f "$file" ]]; then
      run_cmd "cp -p \"$file\" \"$dest_dir/\" || true"
      count=$((count + 1))
    fi
  done
  shopt -u nullglob
}

run_cmd "mkdir -p \"$OUT_DIR\""

run_cmd "printf 'captured_at=%s\n' \"$(date '+%Y-%m-%d %H:%M:%S %z')\" > \"$OUT_DIR/manifest.txt\""
run_cmd "printf 'hostname=%s\n' \"$(hostname)\" >> \"$OUT_DIR/manifest.txt\""
run_cmd "printf 'user=%s\n' \"${USER:-unknown}\" >> \"$OUT_DIR/manifest.txt\""

run_cmd "sw_vers > \"$OUT_DIR/sw_vers.txt\""
run_cmd "uname -a > \"$OUT_DIR/uname.txt\""
run_cmd "date '+%Y-%m-%d %H:%M:%S %z' > \"$OUT_DIR/date.txt\""

run_cmd "ps aux > \"$OUT_DIR/ps_aux.txt\""
run_cmd "pgrep -fal 'KotoType|whisper_server|python.*whisper|uv run' > \"$OUT_DIR/pgrep_backend.txt\" || true"

run_cmd "cd \"$ROOT_DIR\" && git rev-parse --abbrev-ref HEAD > \"$OUT_DIR/git_branch.txt\""
run_cmd "cd \"$ROOT_DIR\" && git rev-parse HEAD > \"$OUT_DIR/git_commit.txt\""
run_cmd "cd \"$ROOT_DIR\" && git status --short > \"$OUT_DIR/git_status_short.txt\""
run_cmd "cd \"$ROOT_DIR\" && git diff -- KotoType/Sources/KotoType/Transcription/MultiProcessManager.swift python/whisper_server.py > \"$OUT_DIR/git_diff_focus.patch\" || true"

APP_LOG_DIR="$HOME/Library/Application Support/koto-type"
run_cmd "mkdir -p \"$OUT_DIR/app_logs\""
copy_glob_limited "${APP_LOG_DIR}/*.log" "$OUT_DIR/app_logs" 20
copy_glob_limited "${APP_LOG_DIR}/*.json" "$OUT_DIR/app_logs" 20

run_cmd "mkdir -p \"$OUT_DIR/diagnostics_user\""
copy_glob_limited "$HOME/Library/Logs/DiagnosticReports/KotoType-*.ips" "$OUT_DIR/diagnostics_user" 30
copy_glob_limited "$HOME/Library/Logs/DiagnosticReports/*whisper*.ips" "$OUT_DIR/diagnostics_user" 30

run_cmd "mkdir -p \"$OUT_DIR/diagnostics_system\""
copy_glob_limited "/Library/Logs/DiagnosticReports/ResetCounter-*.diag" "$OUT_DIR/diagnostics_system" 20
copy_glob_limited "/Library/Logs/DiagnosticReports/JetsamEvent-*.ips" "$OUT_DIR/diagnostics_system" 20
copy_glob_limited "/Library/Logs/DiagnosticReports/WindowServer-*.ips" "$OUT_DIR/diagnostics_system" 10

run_cmd "echo \"$OUT_DIR\" > \"$ROOT_DIR/artifacts/runtime/latest_bundle.txt\""

echo "Artifact bundle: $OUT_DIR"
