#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

usage() {
  printf 'Usage: %s [--output-dir <dir>] <url> [source-comment]\n' "$(basename "$0")" >&2
  printf '       YTDLP_DOWNLOAD_DIR=<dir> %s <url> [source-comment]\n' "$(basename "$0")" >&2
}

absolute_path() {
  local filepath="$1"
  local dirname=""
  local basename=""

  if [[ "$filepath" == /* ]]; then
    printf '%s\n' "$filepath"
    return 0
  fi

  dirname="$(dirname -- "$filepath")"
  basename="$(basename -- "$filepath")"

  if [[ -d "$dirname" ]]; then
    printf '%s/%s\n' "$(cd -- "$dirname" && pwd -P)" "$basename"
    return 0
  fi

  printf '%s/%s\n' "$(pwd -P)" "$filepath"
}

home_download_dir() {
  if [[ -z "${HOME:-}" ]]; then
    log "Error: HOME is not set; pass --output-dir or set YTDLP_DOWNLOAD_DIR." >&2
    return 1
  fi

  printf '%s/Downloads\n' "$HOME"
}

default_download_dir() {
  local uname_name=""
  local maybe_download_dir=""

  if ! uname_name="$(uname -s)"; then
    log "Error: could not determine the current platform with uname." >&2
    return 1
  fi

  case "$uname_name" in
    Darwin)
      home_download_dir
      ;;
    MINGW* | MSYS* | CYGWIN*)
      if [[ -n "${USERPROFILE:-}" ]] && command -v cygpath >/dev/null 2>&1; then
        if maybe_download_dir="$(cygpath -u "${USERPROFILE}\\Downloads" 2>/dev/null)"; then
          if [[ -n "$maybe_download_dir" ]]; then
            printf '%s\n' "$maybe_download_dir"
            return 0
          fi
        fi
      fi

      home_download_dir
      ;;
    *)
      if command -v xdg-user-dir >/dev/null 2>&1; then
        if maybe_download_dir="$(xdg-user-dir DOWNLOAD 2>/dev/null)"; then
          if [[ -n "$maybe_download_dir" && "$maybe_download_dir" == /* ]]; then
            printf '%s\n' "$maybe_download_dir"
            return 0
          fi
        fi
      fi

      home_download_dir
      ;;
  esac
}

resolve_download_dir() {
  local maybe_output_dir="$1"

  if [[ -n "$maybe_output_dir" ]]; then
    absolute_path "$maybe_output_dir"
    return 0
  fi

  if [[ -n "${YTDLP_DOWNLOAD_DIR:-}" ]]; then
    absolute_path "$YTDLP_DOWNLOAD_DIR"
    return 0
  fi

  default_download_dir
}

prepare_download_dir() {
  local download_dir="$1"

  if ! mkdir -p -- "$download_dir"; then
    log "Error: could not create output directory: $download_dir"
    return 1
  fi

  if [[ ! -d "$download_dir" ]]; then
    log "Error: output path is not a directory: $download_dir"
    return 1
  fi

  if [[ ! -w "$download_dir" ]]; then
    log "Error: output directory is not writable: $download_dir"
    return 1
  fi
}

print_tags() {
  local filepath="$1"

  if ! command -v ffprobe >/dev/null 2>&1; then
    log "Warning: ffprobe is not available; skipping tag output for: $filepath"
    return 0
  fi

  log "Metadata tags for: $filepath"
  if ! ffprobe -v quiet -print_format json -show_entries format_tags "$filepath"; then
    log "Warning: ffprobe could not read metadata tags for: $filepath"
  fi
}

set_finder_comment() {
  local filepath="$1"
  local comment="${YTDLP_SOURCE_COMMENT:-}"
  local maybe_comment_hex=""

  if [[ -z "$comment" ]]; then
    log "Warning: no source comment was provided for: $filepath"
    return 0
  fi

  if [[ "$(uname -s)" != "Darwin" ]]; then
    log "Warning: macOS Finder comments are unavailable on this platform; skipping comment for: $filepath"
    return 0
  fi

  if ! command -v xattr >/dev/null 2>&1; then
    log "Warning: xattr is not available; skipping Finder comment for: $filepath"
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log "Warning: python3 is not available; skipping Finder comment for: $filepath"
    return 0
  fi

  maybe_comment_hex="$(
    python3 -c 'import binascii, plistlib, sys; print(binascii.hexlify(plistlib.dumps(sys.argv[1], fmt=plistlib.FMT_BINARY)).decode())' "$comment"
  )"

  if xattr -wx com.apple.metadata:kMDItemFinderComment "$maybe_comment_hex" "$filepath"; then
    log "Applied macOS Finder comment to: $filepath"
  else
    log "Warning: failed to apply macOS Finder comment to: $filepath"
  fi
}

if [[ "${1-}" == "__set-finder-comment" ]]; then
  if [[ $# -ne 2 ]]; then
    log "Warning: internal Finder comment helper received unexpected arguments."
    exit 0
  fi

  set_finder_comment "$2"
  exit 0
fi

output_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        log "Error: --output-dir requires a directory path."
        usage
        exit 1
      fi

      output_dir="$2"
      shift 2
      ;;
    --output-dir=*)
      output_dir="${1#--output-dir=}"
      if [[ -z "$output_dir" ]]; then
        log "Error: --output-dir requires a directory path."
        usage
        exit 1
      fi

      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      log "Error: unknown option: $1"
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

if ! command -v yt-dlp >/dev/null 2>&1; then
  log "Error: yt-dlp is not installed or not on PATH."
  exit 1
fi

url="$1"
source_comment="${2:-Source URL: $url}"
download_dir="$(resolve_download_dir "$output_dir")"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script_path="$script_dir/$(basename -- "${BASH_SOURCE[0]}")"
downloaded_paths_template="${TMPDIR:-/tmp}/yt-dlp-download-paths.XXXXXX"
downloaded_paths_file="$(mktemp "$downloaded_paths_template")"

printf -v quoted_script_path '%q' "$script_path"
after_move_command="$quoted_script_path __set-finder-comment"

export YTDLP_SOURCE_COMMENT="$source_comment"

cleanup() {
  rm -f "$downloaded_paths_file"
}

trap cleanup EXIT

prepare_download_dir "$download_dir"

log "Starting download with embedded metadata."
log "URL: $url"
log "Source comment: $source_comment"
log "Output directory: $download_dir"
log "Command: yt-dlp --embed-metadata --paths \"$download_dir\" --exec after_move:<helper> --print-to-file after_move:filepath <temp-file> \"$url\""

yt-dlp --embed-metadata \
  --paths "$download_dir" \
  --exec "after_move:$after_move_command" \
  --print-to-file "after_move:filepath" "$downloaded_paths_file" \
  "$url"

if [[ -s "$downloaded_paths_file" ]]; then
  while IFS= read -r filepath; do
    if [[ -n "$filepath" ]]; then
      absolute_filepath="$(absolute_path "$filepath")"
      log "Downloaded file: $absolute_filepath"
      print_tags "$absolute_filepath"
    fi
  done < "$downloaded_paths_file"
else
  log "Warning: yt-dlp did not report any final file paths for tag inspection."
fi

log "Finished successfully."
