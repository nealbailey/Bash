#!/bin/bash
#: Title: audiobookshelf-youtube-download.sh
#: Purpose: Download YouTube playlist audio into Audiobookshelf podcast folders.
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#: Changes:
#:  10/31/2026: V1.0.0 - Initial release based on bash_template.sh
#:  10/31/2026: V1.0.1 - Embed metadata/artwork and number files by playlist order
#:
#: Usage: ./audiobookshelf-youtube-download.sh [options]
#: Depends:
#:   yt-dlp: https://github.com/yt-dlp/yt-dlp
#:   ffmpeg: https://ffmpeg.org/
#:   util-linux (flock), coreutils (date, mkdir, realpath, chmod), tee
#:
#: Install dependencies on Ubuntu:
#:   sudo apt update
#:   sudo apt install -y yt-dlp ffmpeg util-linux coreutils
#:
#: Playlist definitions are read from the adjacent file:
#:   audiobookshelf-youtube-playlists.conf
#: Each entry has a `url:` line followed by a `path:` line. Paths must be
#: inside /mnt/md0/Files/Audiobooks/Podcasts.
#:
#: Cron setup (runs as root so it can write into the server's podcast folder):
#:   1. Install this script and its .conf file under /opt/audiobookshelf/.
#:   2. Make it executable: sudo chmod 0755 /opt/audiobookshelf/audiobookshelf-youtube-download.sh
#:   3. Edit root's crontab: sudo crontab -e
#:   4. Add this line to run at minute 0, every 3 hours:
#:      0 */3 * * * /opt/audiobookshelf/audiobookshelf-youtube-download.sh --quiet
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
script_version="1.0.1"
author="Neal T. Bailey"
copyright="Baileysoft Solutions"

# Defaults can be overridden with --config.
source_path=${BASH_SOURCE[0]}
case "$source_path" in
  */*) script_dir=${source_path%/*} ;;
  *) script_dir=. ;;
esac
SCRIPT_DIR=$(cd -- "$script_dir" && pwd -P)
CONFIG_FILE="$SCRIPT_DIR/audiobookshelf-youtube-playlists.conf"
PODCAST_ROOT="/mnt/md0/Files/Audiobooks/Podcasts"
ARCHIVE_FILE="/mnt/md0/Audiobookshelf/youtube-download-archive.txt"
LOG_FILE="/tmp/$scriptname.log"
LOCK_FILE="/tmp/$scriptname.running"
STDOUT_LOG_ONLY="false"
IS_SIMULATION="false"
EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_ALREADY_RUNNING=101
EXIT_MISSING_DEPENDENCY=102
EXIT_MISSING_FILE=104
EXIT_MISSING_DIRECTORY=105

optionusage="Usage: $scriptname [options]\n\nOptions:\n  -c, --config FILE\tUse a playlist definition file\n  -q, --quiet\t\tLog to file only; suppress terminal output\n  -t, --test-run\tValidate definitions and show planned downloads without changes\n  -h, --help\t\tDisplay this help message\n  -v, --version\t\tDisplay version information"
optionexamples="Examples:\n  $scriptname\t\tDownload every configured playlist\n  $scriptname --quiet\tRun silently for cron; output goes to the log\n  $scriptname --test-run\tValidate configuration without downloading"

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

function trim() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

function check_dependencies() {
  local missing=()
  local tool
  for tool in yt-dlp ffmpeg flock tee date mkdir realpath dirname chmod id; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if ((${#missing[@]} > 0)); then
    log "ERROR: Required command(s) missing: ${missing[*]}"
    log "Install the dependencies on Ubuntu with:"
    log "  sudo apt update && sudo apt install -y yt-dlp ffmpeg util-linux coreutils"
    return "$EXIT_MISSING_DEPENDENCY"
  fi
}

function run_ytdlp() {
  local url=$1
  local destination=$2
  local status

  if [[ "$IS_SIMULATION" == "true" ]]; then
    log "TEST RUN: would download $url into $destination"
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
    --yes-playlist
    "$url")

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
  local line=""
  local pending_url=""
  local pending_path=""
  local record_count=0
  local failed_count=0
  local resolved_root
  local resolved_path

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR: Playlist definition file not found: $CONFIG_FILE"
    log "Create it using the adjacent .conf file as an example."
    return "$EXIT_MISSING_FILE"
  fi

  resolved_root=$(realpath -m -- "$PODCAST_ROOT")
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim "$line")
    [[ -z "$line" || "$line" == \#* ]] && continue

    case "$line" in
      url:*)
        if [[ -n "$pending_url" || -n "$pending_path" ]]; then
          log "ERROR: Each url: line must be followed by one path: line before another entry."
          return "$EXIT_GENERAL_ERROR"
        fi
        pending_url=$(trim "${line#url:}")
        if [[ -z "$pending_url" ]]; then
          log "ERROR: Empty url: value in $CONFIG_FILE"
          return "$EXIT_GENERAL_ERROR"
        fi
        case "$pending_url" in
          https://youtube.com/playlist\?*|https://www.youtube.com/playlist\?*|https://music.youtube.com/playlist\?*) ;;
          *)
            log "ERROR: Only HTTPS YouTube playlist URLs are supported: $pending_url"
            return "$EXIT_GENERAL_ERROR"
            ;;
        esac
        ;;
      path:*)
        if [[ -z "$pending_url" || -n "$pending_path" ]]; then
          log "ERROR: A path: line must follow exactly one url: line."
          return "$EXIT_GENERAL_ERROR"
        fi
        pending_path=$(trim "${line#path:}")
        if [[ -z "$pending_path" || "$pending_path" != /* ]]; then
          log "ERROR: Destination path must be a non-empty absolute path: $pending_path"
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
        if ! run_ytdlp "$pending_url" "$resolved_path"; then
          failed_count=$((failed_count + 1))
        fi
        pending_url=""
        pending_path=""
        ;;
      *)
        log "ERROR: Unrecognized definition line in $CONFIG_FILE: $line"
        log "Expected url: https://... followed by path: /absolute/path"
        return "$EXIT_GENERAL_ERROR"
        ;;
    esac
  done < "$CONFIG_FILE"

  if [[ -n "$pending_url" || -n "$pending_path" ]]; then
    log "ERROR: Incomplete final entry in $CONFIG_FILE; every URL needs a path."
    return "$EXIT_GENERAL_ERROR"
  fi
  if ((record_count == 0)); then
    log "ERROR: No playlist definitions found in $CONFIG_FILE"
    return "$EXIT_GENERAL_ERROR"
  fi
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

check_dependencies
chmod 644 "$LOG_FILE"

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  STDOUT_LOG_ONLY="false"
  log "A previous instance is already running."
  log "Exit code: $EXIT_ALREADY_RUNNING"
  exit "$EXIT_ALREADY_RUNNING"
fi
echo "$$" >&200
process_config
