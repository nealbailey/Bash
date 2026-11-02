#!/bin/bash
#: Title: yt-download.sh
#: Purpose: Download YouTube playlist audio into Audiobookshelf podcast folders.
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#: Changes:
#:  10/31/2026: V1.0.0 - Initial release based on bash_template.sh
#:  10/31/2026: V1.0.1 - Embed metadata/artwork and number files by playlist order
#:  11/02/2026: V1.1.0 - Add playlist limits and interactive playlist setup
#:
#: Usage: ./yt-download.sh [options]
#: Depends:
#:   yt-dlp: https://github.com/yt-dlp/yt-dlp
#:   ffmpeg: https://ffmpeg.org/
#:   jq, util-linux (flock), coreutils (date, mkdir, realpath, chmod), tee
#:
#: Install dependencies on Ubuntu:
#:   sudo apt update
#:   sudo apt install -y yt-dlp ffmpeg jq util-linux coreutils
#:
#: Playlist definitions are read from the adjacent file:
#:   yt-download.json
#: The JSON file contains a `playlists` array of objects with `name`, `url`,
#: and `path` strings. Paths must be inside /mnt/md0/Files/Audiobooks/Podcasts.
#:
#: Basic JSON file structure:
#: {
#:   "playlists": [
#:     {
#:       "name": "Playlist Name",
#:       "url": "YouTube Playlist URL",
#:       "path": "/mnt/md0/Files/Audiobooks/Podcasts/Playlist Name",
#:       "limit": 5
#:     }
#:   ]
#: }
#: A limit of 0 downloads the full playlist; a positive limit caps downloaded
#: items starting from the first playlist item.
#:
#: Cron setup (runs as root so it can write into the server's podcast folder):
#:   1. Install this script and its JSON file under /opt/audiobookshelf/.
#:   2. Make it executable: sudo chmod 0755 /opt/audiobookshelf/yt-download.sh
#:   3. Edit root's crontab: sudo crontab -e
#:   4. Add this line to run at minute 0, every 6 hours:
#:      0 */6 * * * /opt/audiobookshelf/yt-download.sh --quiet
#: The archive is stored outside the watched media folder at
#: /mnt/md0/Audiobookshelf/youtube-download-archive.txt. In Audiobookshelf,
#: enable library watching/scheduled scans or scan the Podcast library after
#: downloads so new episode files appear.
#:
# ----------------------------------------------------------------------
# GNU GENERAL PUBLIC LICENSE
# ----------------------------------------------------------------------
# Version 2, June 1991
# Copyright (C) 1989, 1991 Free Software Foundation, Inc.
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#
# Everyone is permitted to copy and distribute verbatim copies
# of this license document, but changing it is not allowed.
#
# https://www.gnu.org/licenses/gpl-2.0.html
#-----------------------------------------------------------------------
# Copyright (c) 2016-2026 Baileysoft Solutions
#-----------------------------------------------------------------------

set -euo pipefail

# Script metadata
scriptname=${0##*/}
description="Download YouTube playlist audio for Audiobookshelf"
date_of_creation="2026-10-31"
script_version="1.1.0"
author="Neal T. Bailey"
copyright="Baileysoft Solutions"

# Defaults can be overridden with --config.
source_path=${BASH_SOURCE[0]}
case "$source_path" in
  */*) script_dir=${source_path%/*} ;;
  *) script_dir=. ;;
esac
SCRIPT_DIR=$(cd -- "$script_dir" && pwd -P)
CONFIG_FILE="$SCRIPT_DIR/yt-download.json"
PODCAST_ROOT="/mnt/md0/Files/Audiobooks/Podcasts"
ARCHIVE_FILE="/mnt/md0/Audiobookshelf/youtube-download-archive.txt"
LOG_FILE="/tmp/$scriptname.log"
LOCK_FILE="/tmp/$scriptname.running"
STDOUT_LOG_ONLY="false"
IS_SIMULATION="false"
ADD_PLAYLIST="false"
EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_ALREADY_RUNNING=101
EXIT_MISSING_DEPENDENCY=102
EXIT_MISSING_FILE=104
EXIT_MISSING_DIRECTORY=105

optionusage="Usage: $scriptname [options]\n\nOptions:\n  -c, --config FILE\tUse a playlist definition file\n  -q, --quiet\t\tLog to file only; suppress terminal output\n  -t, --test-run\tValidate definitions and show planned downloads without changes\n  -h, --help\t\tDisplay this help message\n  -v, --version\t\tDisplay version information"
optionusage="${optionusage}\n  -a, --add-playlist\tInteractively add a playlist to the JSON config"
optionexamples="Examples:\n  $scriptname\t\tDownload every configured playlist\n  $scriptname --quiet\tRun silently for cron; output goes to the log\n  $scriptname --test-run\tValidate configuration without downloading"
optionexamples="${optionexamples}\n  $scriptname --add-playlist\tAdd a playlist and create its destination folder"

# Template functions: help, version, logging, and exit metrics.
function usage() {
  printf '%s - %s\n' "$scriptname" "$description"
  printf '%b\n\n' "$optionusage"
  printf '%b\n' "$optionexamples"
}

function show_version() {
  printf '%s: %s\n' "$scriptname" "$description"
  printf 'Release Date: %s\n' "$date_of_creation"
  printf 'Version: %s\n' "$script_version"
  printf 'Copyright: %s, %s\n' "$author" "$copyright"
}

function log() {
  local timestamp
  timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf 'time-unavailable')
  if [[ "$STDOUT_LOG_ONLY" == "false" ]]; then
    printf '%s %s\n' "$timestamp" "$1"
  fi
  printf '%s %s\n' "$timestamp" "$1" >> "$LOG_FILE"
}

function on_exit() {
  local exit_code=$?
  if [[ -f "$LOG_FILE" ]]; then
    log "Completed executing process: $scriptname"
    log "Process executed for: $((SECONDS / 3600))h:$((SECONDS % 3600 / 60))m:$((SECONDS % 60))s"
    log "Exit code: $exit_code"
  fi
}

function check_dependencies() {
  local missing=()
  local tool
  local required_tools=(yt-dlp ffmpeg jq flock tee date mkdir realpath dirname chmod id)
  if [[ "${1:-}" == "add-playlist" ]]; then
    required_tools=(jq flock date mkdir realpath chmod id mktemp mv rm)
  fi
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if ((${#missing[@]} > 0)); then
    log "ERROR: Required command(s) missing: ${missing[*]}"
    log "Install the dependencies on Ubuntu with:"
    if [[ "${1:-}" == "add-playlist" ]]; then
      log "  sudo apt update && sudo apt install -y jq util-linux coreutils"
    else
      log "  sudo apt update && sudo apt install -y yt-dlp ffmpeg jq util-linux coreutils"
    fi
    return "$EXIT_MISSING_DEPENDENCY"
  fi
}

function is_youtube_playlist_url() {
  case "$1" in
    https://youtube.com/playlist\?*|https://www.youtube.com/playlist\?*|https://music.youtube.com/playlist\?*) return 0 ;;
    *) return 1 ;;
  esac
}

function is_valid_config() {
  jq -e '
    type == "object" and
    (.playlists | type == "array" and length > 0) and
    all(.playlists[];
      type == "object" and
      (.name | type == "string" and length > 0 and (contains("\u0000") | not)) and
      (.url | type == "string" and length > 0 and (contains("\u0000") | not)) and
      (.path | type == "string" and length > 0 and (contains("\u0000") | not)) and
      (.limit | type == "number" and floor == . and . >= 0)
    )
  ' "$1" >/dev/null
}

function add_playlist() {
  local playlist_name=""
  local playlist_url=""
  local resolved_root
  local resolved_path
  local temporary_config=""

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR: Playlist definition file not found: $CONFIG_FILE"
    return "$EXIT_MISSING_FILE"
  fi
  if ! is_valid_config "$CONFIG_FILE"; then
    log "ERROR: Invalid JSON or playlist schema in $CONFIG_FILE"
    log 'Expected a non-empty "playlists" array with non-empty name, url, and path strings, plus a non-negative integer limit.'
    return "$EXIT_GENERAL_ERROR"
  fi

  if ! IFS= read -r -p "Playlist name: " playlist_name ||
     [[ -z "${playlist_name//[[:space:]]/}" || "$playlist_name" == "." ||
        "$playlist_name" == ".." || "$playlist_name" == */* ||
        "$playlist_name" == *$'\r'* ]]; then
    log "ERROR: Playlist name must be non-empty and cannot contain a slash."
    return "$EXIT_GENERAL_ERROR"
  fi
  if ! IFS= read -r -p "YouTube playlist URL: " playlist_url; then
    log "ERROR: Could not read playlist URL."
    return "$EXIT_GENERAL_ERROR"
  fi
  if ! is_youtube_playlist_url "$playlist_url"; then
    log "ERROR: Only HTTPS YouTube playlist URLs are supported: $playlist_url"
    return "$EXIT_GENERAL_ERROR"
  fi
  if jq -e --arg name "$playlist_name" \
      'any(.playlists[]; .name == $name)' "$CONFIG_FILE" >/dev/null; then
    log "ERROR: A playlist with this name already exists: $playlist_name"
    return "$EXIT_GENERAL_ERROR"
  fi

  resolved_root=$(realpath -m -- "$PODCAST_ROOT")
  resolved_path=$(realpath -m -- "$resolved_root/$playlist_name")
  case "$resolved_path" in
    "$resolved_root"/*) ;;
    *)
      log "ERROR: Destination must be below $resolved_root: $playlist_name"
      return "$EXIT_GENERAL_ERROR"
      ;;
  esac

  if ! temporary_config=$(mktemp "${CONFIG_FILE}.tmp.XXXXXX"); then
    log "ERROR: Could not create a temporary config file beside $CONFIG_FILE"
    return "$EXIT_GENERAL_ERROR"
  fi
  if ! jq --arg name "$playlist_name" --arg url "$playlist_url" \
      --arg path "$resolved_path" \
      '.playlists += [{name: $name, url: $url, path: $path, limit: 5}]' \
      "$CONFIG_FILE" > "$temporary_config"; then
    rm -f -- "$temporary_config"
    log "ERROR: Could not update playlist config: $CONFIG_FILE"
    return "$EXIT_GENERAL_ERROR"
  fi
  if ! chmod --reference="$CONFIG_FILE" "$temporary_config"; then
    rm -f -- "$temporary_config"
    log "ERROR: Could not preserve permissions for the updated config."
    return "$EXIT_GENERAL_ERROR"
  fi
  if ! mkdir -p -- "$resolved_path"; then
    rm -f -- "$temporary_config"
    log "ERROR: Could not create destination directory: $resolved_path"
    return "$EXIT_MISSING_DIRECTORY"
  fi
  if ! mv -- "$temporary_config" "$CONFIG_FILE"; then
    rm -f -- "$temporary_config"
    log "ERROR: Could not replace playlist config: $CONFIG_FILE"
    return "$EXIT_GENERAL_ERROR"
  fi

  log "Added playlist '$playlist_name' with download limit 5."
  log "Destination: $resolved_path"
}

function run_ytdlp() {
  local url=$1
  local destination=$2
  local dl_limit=$3
  local status

  if [[ "$IS_SIMULATION" == "true" ]]; then
    if [[ "$dl_limit" != "0" ]]; then
      log "TEST RUN: would download $url into $destination with --playlist-items 1:$dl_limit"
    else
      log "TEST RUN: would download $url into $destination"
    fi
    return "$EXIT_SUCCESS"
  fi

  if [[ ! -d "$destination" ]] && ! mkdir -p -- "$destination"; then
    log "ERROR: Could not create destination: $destination"
    return "$EXIT_MISSING_DIRECTORY"
  fi
  if [[ ! -w "$destination" ]]; then
    log "ERROR: Destination is not writable by user $(id -un): $destination"
    log "Run the scheduled job as root or grant its account write access to this folder."
    return "$EXIT_MISSING_DIRECTORY"
  fi
  if [[ ! -w "$(dirname -- "$ARCHIVE_FILE")" ]]; then
    log "ERROR: Archive directory is not writable: $(dirname -- "$ARCHIVE_FILE")"
    log "Run the scheduled job as root or grant its account write access to that directory."
    return "$EXIT_MISSING_DIRECTORY"
  fi

  log "Downloading playlist: $url"
  log "Destination: $destination"
  local -a command=(yt-dlp
    --format bestaudio
    --extract-audio
    --audio-format mp3
    --embed-thumbnail
    --embed-metadata
    --parse-metadata "playlist_index:%(track_number)s"
    --download-archive "$ARCHIVE_FILE"
    --output "$destination/%(playlist_index)03d - %(title)s [%(id)s].%(ext)s"
    --no-progress
    --yes-playlist)

  if [[ "$dl_limit" != "0" ]]; then
    command+=(--playlist-items "1:$dl_limit")
  fi
  command+=("$url")

  if [[ "$STDOUT_LOG_ONLY" == "true" ]]; then
    if "${command[@]}" >> "$LOG_FILE" 2>&1; then
      log "Playlist completed: $url"
    else
      status=$?
      log "ERROR: yt-dlp failed with exit code $status for $url"
      return "$status"
    fi
  else
    if "${command[@]}" 2>&1 | tee -a "$LOG_FILE"; then
      log "Playlist completed: $url"
    else
      status=$?
      log "ERROR: yt-dlp failed with exit code $status for $url"
      return "$status"
    fi
  fi
}

function process_config() {
  local pending_url=""
  local pending_path=""
  local dl_limit=""
  local record_count=0
  local failed_count=0
  local resolved_root
  local resolved_path

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR: Playlist definition file not found: $CONFIG_FILE"
    log "Refer to the head of this script for the expected JSON structure."
    return "$EXIT_MISSING_FILE"
  fi

  if ! is_valid_config "$CONFIG_FILE"; then
    log "ERROR: Invalid JSON or playlist schema in $CONFIG_FILE"
    log 'Expected a non-empty "playlists" array with non-empty name, url, and path strings, plus a non-negative integer limit.'
    return "$EXIT_GENERAL_ERROR"
  fi

  resolved_root=$(realpath -m -- "$PODCAST_ROOT")
  while IFS= read -r -d '' pending_url &&
        IFS= read -r -d '' pending_path &&
        IFS= read -r -d '' dl_limit; do
    if ! is_youtube_playlist_url "$pending_url"; then
      log "ERROR: Only HTTPS YouTube playlist URLs are supported: $pending_url"
      return "$EXIT_GENERAL_ERROR"
    fi
    if [[ "$pending_path" != /* ]]; then
      log "ERROR: Destination path must be an absolute path: $pending_path"
      return "$EXIT_GENERAL_ERROR"
    fi
    resolved_path=$(realpath -m -- "$pending_path")
    case "$resolved_path" in
      "$resolved_root"/*) ;;
      *)
        log "ERROR: Destination must be below $resolved_root: $pending_path"
        return "$EXIT_GENERAL_ERROR"
        ;;
    esac
    ((record_count += 1))
    if ! run_ytdlp "$pending_url" "$resolved_path" "$dl_limit"; then
      failed_count=$((failed_count + 1))
    fi
  done < <(jq -j '.playlists[] | .url, "\u0000", .path, "\u0000", (.limit | floor | tostring), "\u0000"' "$CONFIG_FILE")

  if ((failed_count > 0)); then
    log "ERROR: $failed_count of $record_count playlist download(s) failed."
    return "$EXIT_GENERAL_ERROR"
  fi
  log "Processed $record_count playlist definition(s) successfully."
}

# Parse arguments before opening the run log/lock, so help/version are side-effect free.
while (($# > 0)); do
  case "$1" in
    -c|--config)
      if (($# < 2)); then
        printf 'ERROR: %s requires a file path.\n' "$1" >&2
        exit "$EXIT_GENERAL_ERROR"
      fi
      CONFIG_FILE=$2
      shift 2
      ;;
    -q|--quiet)
      STDOUT_LOG_ONLY="true"
      shift
      ;;
    -a|--add-playlist)
      ADD_PLAYLIST="true"
      shift
      ;;
    -t|--test-run)
      IS_SIMULATION="true"
      shift
      ;;
    -h|--help)
      usage
      exit "$EXIT_SUCCESS"
      ;;
    -v|--version)
      show_version
      exit "$EXIT_SUCCESS"
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit "$EXIT_GENERAL_ERROR"
      ;;
  esac
done

if [[ "$ADD_PLAYLIST" == "true" && "$IS_SIMULATION" == "true" ]]; then
  printf 'ERROR: --add-playlist cannot be combined with --test-run.\n' >&2
  exit "$EXIT_GENERAL_ERROR"
fi

# Match the template's per-run log and non-blocking singleton lock behavior.
# Use shell redirection so a missing `touch` does not prevent dependency reporting.
: > "$LOG_FILE"
trap on_exit EXIT
log "Started executing process: $scriptname"
log "LOG_FILE is: $LOG_FILE"
log "LOCK_FILE is: $LOCK_FILE"
log "CONFIG_FILE is: $CONFIG_FILE"
if [[ "$IS_SIMULATION" == "true" ]]; then
  log "THIS IS A TEST RUN: no directories or downloads will be created."
fi

if [[ "$ADD_PLAYLIST" == "true" ]]; then
  check_dependencies add-playlist
else
  check_dependencies
fi
chmod 644 "$LOG_FILE"

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  STDOUT_LOG_ONLY="false"
  log "A previous instance is already running."
  log "Exit code: $EXIT_ALREADY_RUNNING"
  exit "$EXIT_ALREADY_RUNNING"
fi
echo "$$" >&200
if [[ "$ADD_PLAYLIST" == "true" ]]; then
  add_playlist
else
  process_config
fi
