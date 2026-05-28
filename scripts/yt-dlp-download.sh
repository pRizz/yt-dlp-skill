#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

usage() {
  printf 'Usage: %s [--output-dir <dir>] [--no-compat-convert] [--keep-original] <url> [source-comment]\n' "$(basename "$0")" >&2
  printf '       YTDLP_DOWNLOAD_DIR=<dir> %s <url> [source-comment]\n' "$(basename "$0")" >&2
  printf '       YTDLP_COMPAT_CONVERT=never %s <url> [source-comment]\n' "$(basename "$0")" >&2
  printf '       YTDLP_COMPAT_KEEP_ORIGINAL=1 %s <url> [source-comment]\n' "$(basename "$0")" >&2
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

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
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

probe_first_stream_codec() {
  local filepath="$1"
  local stream_selector="$2"

  ffprobe -v error \
    -select_streams "$stream_selector" \
    -show_entries stream=codec_name \
    -of default=nokey=1:noprint_wrappers=1 \
    "$filepath" | sed -n '1p'
}

ffmpeg_has_encoder() {
  local encoder="$1"

  ffmpeg -hide_banner -encoders 2>/dev/null |
    awk -v encoder="$encoder" '$2 == encoder { found = 1 } END { exit found ? 0 : 1 }'
}

select_h264_encoder() {
  if ffmpeg_has_encoder "libx264"; then
    printf 'libx264\n'
    return 0
  fi

  if ffmpeg_has_encoder "h264_videotoolbox"; then
    printf 'h264_videotoolbox\n'
    return 0
  fi

  return 1
}

is_mp4_audio_codec() {
  local audio_codec

  audio_codec="$(lowercase "$1")"

  case "$audio_codec" in
    aac | ac3 | alac | eac3 | mp3)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

unique_filepath() {
  local desired_filepath="$1"
  local dirname=""
  local filename=""
  local extension=""
  local stem=""
  local candidate=""
  local counter=1

  if [[ ! -e "$desired_filepath" ]]; then
    printf '%s\n' "$desired_filepath"
    return 0
  fi

  dirname="$(dirname -- "$desired_filepath")"
  filename="$(basename -- "$desired_filepath")"

  if [[ "$filename" == *.* ]]; then
    extension=".${filename##*.}"
    stem="${filename%.*}"
  else
    extension=""
    stem="$filename"
  fi

  while true; do
    candidate="$dirname/$stem-$counter$extension"
    if [[ ! -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi

    counter=$((counter + 1))
  done
}

conversion_target_filepath() {
  local source_filepath="$1"
  local keep_original="$2"
  local dirname=""
  local filename=""
  local extension=""
  local extension_lower=""
  local stem=""
  local desired_filepath=""

  dirname="$(dirname -- "$source_filepath")"
  filename="$(basename -- "$source_filepath")"

  if [[ "$filename" == *.* ]]; then
    extension="${filename##*.}"
    stem="${filename%.*}"
  else
    extension=""
    stem="$filename"
  fi

  extension_lower="$(lowercase "$extension")"

  if [[ "$keep_original" -eq 0 && "$extension_lower" == "mp4" ]]; then
    printf '%s\n' "$source_filepath"
    return 0
  fi

  if [[ "$extension_lower" == "mp4" ]]; then
    desired_filepath="$dirname/$stem.h264.mp4"
  else
    desired_filepath="$dirname/$stem.mp4"
  fi

  unique_filepath "$desired_filepath"
}

convert_vp9_to_h264_mp4() {
  local source_filepath="$1"
  local keep_original="$2"
  local encoder=""
  local audio_codec=""
  local target_filepath=""
  local target_dirname=""
  local target_filename=""
  local temp_filepath=""
  local -a video_args=()
  local -a audio_args=()
  local -a ffmpeg_args=()

  if ! command -v ffmpeg >/dev/null 2>&1; then
    log "Warning: ffmpeg is not available; leaving VP9 file unchanged: $source_filepath"
    return 1
  fi

  if ! encoder="$(select_h264_encoder)"; then
    log "Warning: ffmpeg does not provide libx264 or h264_videotoolbox; leaving VP9 file unchanged: $source_filepath"
    return 1
  fi

  target_filepath="$(conversion_target_filepath "$source_filepath" "$keep_original")"
  target_dirname="$(dirname -- "$target_filepath")"
  target_filename="$(basename -- "$target_filepath")"

  if [[ "$target_filepath" != "$source_filepath" && -e "$target_filepath" ]]; then
    log "Warning: conversion target already exists; leaving VP9 file unchanged: $target_filepath"
    return 1
  fi

  if [[ "$encoder" == "libx264" ]]; then
    video_args=(-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p)
  else
    video_args=(-c:v h264_videotoolbox -q:v 65 -pix_fmt yuv420p)
  fi

  if audio_codec="$(probe_first_stream_codec "$source_filepath" "a:0")"; then
    if [[ -n "$audio_codec" ]] && is_mp4_audio_codec "$audio_codec"; then
      audio_args=(-c:a copy)
    elif [[ -n "$audio_codec" ]]; then
      audio_args=(-c:a aac -b:a 192k)
    fi
  else
    log "Warning: ffprobe could not inspect audio codec for: $source_filepath"
  fi

  temp_filepath="$(mktemp "$target_dirname/.$target_filename.tmp.XXXXXX")"

  log "Converting VP9 video to H.264 MP4 for QuickTime compatibility: $source_filepath"

  ffmpeg_args=(
    -hide_banner
    -loglevel error
    -y
    -i "$source_filepath"
    -map 0:v:0
    -map 0:a?
    -map_metadata 0
    "${video_args[@]}"
  )

  if [[ "${#audio_args[@]}" -gt 0 ]]; then
    ffmpeg_args+=("${audio_args[@]}")
  fi

  ffmpeg_args+=(
    -movflags +faststart
    -f mp4
    "$temp_filepath"
  )

  if ffmpeg "${ffmpeg_args[@]}"; then
    mv -f -- "$temp_filepath" "$target_filepath"

    if [[ "$keep_original" -eq 0 && "$target_filepath" != "$source_filepath" ]]; then
      rm -f -- "$source_filepath"
    fi

    log "Converted VP9 video: $target_filepath"
    CONVERTED_ORIGINAL_RETAINED=0
    if [[ "$target_filepath" != "$source_filepath" && -e "$source_filepath" ]]; then
      CONVERTED_ORIGINAL_RETAINED=1
    fi
    CONVERTED_FILEPATH="$target_filepath"
    return 0
  fi

  rm -f -- "$temp_filepath"
  log "Warning: ffmpeg conversion failed; leaving VP9 file unchanged: $source_filepath"
  return 1
}

process_downloaded_file() {
  local filepath="$1"
  local compat_convert_enabled="$2"
  local keep_original="$3"
  local video_codec=""

  PROCESSED_FILEPATH="$filepath"
  PROCESSED_ORIGINAL_RETAINED=0

  if [[ "$compat_convert_enabled" -eq 0 ]]; then
    return 0
  fi

  if ! command -v ffprobe >/dev/null 2>&1; then
    log "Warning: ffprobe is not available; skipping VP9 compatibility conversion for: $filepath"
    return 0
  fi

  if ! video_codec="$(probe_first_stream_codec "$filepath" "v:0")"; then
    log "Warning: ffprobe could not inspect video codec for: $filepath"
    return 0
  fi

  if [[ "$(lowercase "$video_codec")" != "vp9" ]]; then
    return 0
  fi

  CONVERTED_FILEPATH=""
  CONVERTED_ORIGINAL_RETAINED=0
  if convert_vp9_to_h264_mp4 "$filepath" "$keep_original"; then
    PROCESSED_FILEPATH="$CONVERTED_FILEPATH"
    PROCESSED_ORIGINAL_RETAINED="$CONVERTED_ORIGINAL_RETAINED"
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

output_dir=""
compat_convert_enabled=1
keep_original=0

if [[ "${YTDLP_COMPAT_CONVERT:-}" == "never" ]]; then
  compat_convert_enabled=0
fi

case "${YTDLP_COMPAT_KEEP_ORIGINAL:-}" in
  1 | true | TRUE | yes | YES | on | ON)
    keep_original=1
    ;;
esac

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
    --no-compat-convert)
      compat_convert_enabled=0
      shift
      ;;
    --keep-original)
      keep_original=1
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
downloaded_paths_template="${TMPDIR:-/tmp}/yt-dlp-download-paths.XXXXXX"
downloaded_paths_file="$(mktemp "$downloaded_paths_template")"
yt_dlp_embed_metadata_enabled=1
if ! command -v ffmpeg >/dev/null 2>&1; then
  yt_dlp_embed_metadata_enabled=0
fi

export YTDLP_SOURCE_COMMENT="$source_comment"

cleanup() {
  rm -f "$downloaded_paths_file"
}

trap cleanup EXIT

prepare_download_dir "$download_dir"

log "Starting download."
log "URL: $url"
log "Source comment: $source_comment"
log "Output directory: $download_dir"
if [[ "$yt_dlp_embed_metadata_enabled" -eq 1 ]]; then
  log "Embedded metadata: enabled"
else
  log "Warning: ffmpeg is not available; skipping yt-dlp embedded metadata postprocessing."
fi
if [[ "$compat_convert_enabled" -eq 1 ]]; then
  log "VP9 compatibility conversion: enabled"
else
  log "VP9 compatibility conversion: disabled"
fi
if [[ "$keep_original" -eq 1 ]]; then
  log "VP9 compatibility conversion original policy: keep original"
else
  log "VP9 compatibility conversion original policy: replace after successful conversion"
fi
if [[ "$yt_dlp_embed_metadata_enabled" -eq 1 ]]; then
  log "Command: yt-dlp --embed-metadata --paths \"$download_dir\" --print-to-file after_move:filepath <temp-file> \"$url\""
  yt-dlp --embed-metadata \
    --paths "$download_dir" \
    --print-to-file "after_move:filepath" "$downloaded_paths_file" \
    "$url"
else
  log "Command: yt-dlp --paths \"$download_dir\" --print-to-file after_move:filepath <temp-file> \"$url\""
  yt-dlp \
    --paths "$download_dir" \
    --print-to-file "after_move:filepath" "$downloaded_paths_file" \
    "$url"
fi

if [[ -s "$downloaded_paths_file" ]]; then
  while IFS= read -r filepath; do
    if [[ -n "$filepath" ]]; then
      absolute_filepath="$(absolute_path "$filepath")"
      log "Downloaded file: $absolute_filepath"
      process_downloaded_file "$absolute_filepath" "$compat_convert_enabled" "$keep_original"

      if [[ "$PROCESSED_ORIGINAL_RETAINED" -eq 1 ]]; then
        log "Original VP9 file kept: $absolute_filepath"
        set_finder_comment "$absolute_filepath"
      fi

      log "Final media file: $PROCESSED_FILEPATH"
      set_finder_comment "$PROCESSED_FILEPATH"
      print_tags "$PROCESSED_FILEPATH"
    fi
  done < "$downloaded_paths_file"
else
  log "Warning: yt-dlp did not report any final file paths for tag inspection."
fi

log "Finished successfully."
