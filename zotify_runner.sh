#!/bin/bash
#: Title: zotify_runner.sh
#: Purpose: Rips spotify tracks and copies them to a file server
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#:
#: Changes: 
#:  11/19/2022: V0.1.0 - Initial release
#:  08/20/2026: V0.2.0 - Added test-run option and improved logging
#:
#: Usage: $ ./zotify_runner.sh
#: Depends: requires package(s)
#:   zotify: https://github.com/Googolplexed0/zotify
#:   NTag flatpak: https://flathub.org/apps/com.github.nrittsti.NTag
#:
# ----------------------------------------------------------------------
# GNU GENERAL PUBLIC LICENSE
# ----------------------------------------------------------------------
# Version 2, June 1991 
# Copyright (C) 1989, 1991 Free Software Foundation, Inc.  
# 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA
#
# Everyone is permitted to copy and distribute verbatim copies
# of this license document, but changing it is not allowed.
#
# https://www.gnu.org/licenses/gpl-2.0.html
#-----------------------------------------------------------------------
# Copyright (c) 2016-2026 Baileysoft Solutions
#-----------------------------------------------------------------------

# Sets the script to exit immediately if a command exits with a non-zero status,
# treat unset variables as an error and exit immediately, and prevents errors in a pipeline from being masked.
#set -euo pipefail

#
# Program Variables
#
# Mouted network file share path to copy mp3s to
file_share="$HOME/Network/baileyfs02.baileysoft.lan/Files/Uploads/Music"
# The path where zotify will download music files to. This is the default path for zotify.
zotify_dl_path="$HOME/Music/Zotify Music"
# The path where zotify will stage music files to so their ID3 Tags can be edited before copying to the network file share.
stage_path="$HOME/Music/New"
# Flag to determine if the script is running in simulation mode (test-run)
isSimulation=false

# Metadata
scriptname=${0##*/}
description="Spotify Ripper and ID3Tag Editor"
optionusage="Usage: $0 [options]\n\n Options:\n  -t, --test-run\tSimulate workflow without calling Spotify or copying files\n  -h, --help\t\tDisplay this help message\n  -v, --version\t\tDisplay version information"
optionexamples="Examples:\n  $0 -t\t\tSimulate the workflow\n"
date_of_creation="2026-08-20"
version=0.2.0
author="Neal T. Bailey"
copyright="Baileysoft Solutions"

# Log file path
LOGFILE="/tmp/$scriptname.log"
PID_FILE="/tmp/$scriptname.running"

#@ DESCRIPTION: Calculates the amounts of seconds that have passed since a file was modified.
#@ REMARKS: You must use $? to get result.
#@ PARAM $1: The full file name (including path).
#@ USAGE: get_seconds_since_modification "$FILE_NAME"
#@        seconds=$?
#@        echo $seconds
#@ RETURNS: Exit code. 
function get_seconds_since_modification 
{
  local seconds=0
  if [[ -f "$1" ]] ; then
    seconds=`echo $(($(date +%s)-$(date +%s -r "$1")))`
  fi
  return $seconds
}

#@ DESCRIPTION: Unlocks the process
#@ REMARKS: Handles the SIGTERM EXIT broadcast
function on_exit() 
{ 
  if [[ -f "$PID_FILE" ]] ; then
    log "Completed executing process: $scriptname"
    get_seconds_since_modification "$PID_FILE" ; local seconds=$?
    printf 'Process executed for:\t%dh:%dm:%ds\n' $(($seconds/3600)) $(($seconds%3600/60)) $(($seconds%60))
    rm -f "$PID_FILE"
  fi  
}

#@ DESCRIPTION: Executes or suppresses a trusted shell command based on isSimulation.
#@ PARAM $1: The trusted shell command to execute.
#@ REMARKS:
#@   - The command is logged before execution.
#@   - Command stdout/stderr is written to both the terminal and LOGFILE.
#@   - When isSimulation=true, the command is logged but not executed.
#@   - The argument is evaluated as shell syntax and MUST NOT contain unvalidated input.
#@ WARNING: Only the exit code for the first command in the pipeline will get returned!
#@ USAGE: eval_exec "ls \"*.txt\" ; echo $?
#@ RETURNS: Exit code returned by the executed command.
function eval_exec()
{
  local command="$1"
  local result=0

  log "Exec: $command"

  if [[ "${isSimulation:-false}" == "true" ]]; then
    return 0
  fi

  # The if statement intentionally places the pipeline in a conditional
  # context so errexit does not terminate the script before PIPESTATUS
  # can be captured.
  if eval "$command" 2>&1 | tee -a "$LOGFILE"; then
    result=${PIPESTATUS[0]}
  else
    result=${PIPESTATUS[0]}
  fi

  return "$result"
}

#@ DESCRIPTION: Prints usage information
function usage {
    printf "%s - %s\n" "$scriptname" "$description"
    printf "%s\n $optionusage"
    printf "%s\n\n $optionexamples"
}

#@ DESCRIPTION: Print version information
function version {
    printf "%s: %s\n" "$scriptname" "$description"
    printf "Release Date: %s\n" "$date_of_creation"
    printf "Version: %s\n" "$version"
    printf "Copyright: %s, %s\n" "$author" "$copyright"
}

#@ DESCRIPTION: Log message.
#@ PARAM $1: The message to log.
#@ REMARKS: Sends message to stdout with -o flag
function log() {  
  local timestamp
  timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
  printf '%s\n' "$1"
  printf '%s %s\n' "$timestamp" "$1" >> "$LOGFILE"
}

#@ DESCRIPTION: Prompt user for spotify URLs to download using zotify.
function PromptForSpotifyUrls
{
  while true; do
    read -p "Paste the full Spotify URL to download: " url    
    ExecuteZotifyDownload "$url"

    # Ask if the user wants to download another URL
    read -p "Download another spotify link? (y/n): " answer
    case "$answer" in
      [nN]) break ;;
      [yY]) ;;
      *) log "Please answer y or n."; continue ;;
  esac
  done
}

#@ DESCRIPTION: Executes zotify to download music from Spotify.
#@ PARAM $1: The Spotify URL (track, playlist, album, etc.) to download.
function ExecuteZotifyDownload
{
  if [[ $isSimulation == true ]]; then
    log "Simulation mode enabled - skipping Spotify actions."
    return 0
  fi

  if [[ -z "$1" ]]; then
    log "No Spotify URL provided. Skipping download."
    return 1
  fi

  log "Downloading from URL: $1"
  log "Exec: zotify \"$1\" --codec=mp3 --download-quality=very_high 2>&1"  
  #eval_exec "zotify \"$1\" --codec=mp3 --download-quality=very_high 2>&1  | tee -a \"$LOGFILE\""
  zotify "$1" --codec=mp3 --download-quality=very_high 2>&1
}

#@ DESCRIPTION: Launch ntag package to update file ID3Tags.
function LaunchNTag
{  
  # Verify ntag is installed
  if ! flatpak info com.github.nrittsti.NTag &>/dev/null; then
    log "Ntag flatpak not installed: com.github.nrittsti.NTag"
    log "https://flathub.org/apps/com.github.nrittsti.NTag"
    exit 100
  fi

  # Launch NTag
  log "Launching ntag: com.github.nrittsti.NTag"
  log "Don't forget to rename in ntag before editing the ID3Tags data."
  eval_exec "flatpak run com.github.nrittsti.NTag"  
}

#@ DESCRIPTION: Copies rips from download path to temp staging path.
function StageDownloadedRips
{
  # Verify the stage path exists before attempting to copy files into it.  
  [[ -d "$stage_path" ]] || {
    log "Error: Staging directory does not exist: $stage_path"
    return 1
  }

  # Delete mp3 files in New staging folder
  log "Delete previous staged mp3 files in the New staging folder"
  eval_exec "rm -frv \"$stage_path\"/*.mp3"
  #eval_exec "find \"$stage_path\" -mindepth 1 -maxdepth 1 -iname \".mp3\" -exec rm -rfv -- {} + "

  log "Searching for new songs to sync with server"  
  #local find_count=$(find ./Zotify\ Albums/ \( -name '*.mp3' \) -mtime -1 | wc -l)
  log "Exec: find \"$zotify_dl_path\" \( -name '*.mp3' \) -mtime -1 | wc -l)"
  local find_count=$(find "$zotify_dl_path" \( -name '*.mp3' \) -mtime -1 | wc -l)
    
  log "Found '$find_count' new music files to stage"

  # Copy any music files created in the previous 24 hours into New folder
  log "Copying new zotify music downloads into staging folder"
  
  if [ "$find_count" -gt 0 ]; then
    eval_exec "find \"$zotify_dl_path\" \( -name '*.mp3' \) -mtime -1  -exec cp -uv {} \"$stage_path\" \;"
  fi

  if [[ $find_count -eq 0 ]]; then
    log "Warn: No files were staged so no need to continue. Exiting."
    exit 1
  fi
}

# #@ DESCRIPTION: Copies rips from temp staging path to network file share.
function CopyRipsToServer
{   
  log "Copying new music files to server share: $file_share"
  
  if [[ $isSimulation == true ]]; then
    log "Simulation mode enabled - skipping copying files to server."
    return 0
  fi

  eval_exec "cp -uv \"$stage_path\"/*.mp3 \"$file_share\""  
}

# Create the log file and set permissions to be readable and writable by the user only.
touch "$LOGFILE"
chmod 600 "$LOGFILE"
: > "$LOGFILE"

# Ensure the script is not currently in a RUNNING state.
if [[ -f "$PID_FILE" ]] ; then
  STDOUT_LOG_ONLY="false"
  log "A previous instance of this process is currently executing."
  exit 101
fi

#
# Pre-requisite sanity check. These segments ensure nothing unexpected will prevent
# the process from completing at runtime due to unknown or invalid machine configuration. 
#
# Verify that zotify is installed
if ! command -v zotify &> /dev/null; then
    log "Error: zotify is not installed. Please install zotify to use this script."
    exit 101
fi

# Verify correct Python version is in use
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then  
  log "Error: This script requires Python version 3.11 or newer to run zotify properly."
  log "INFO: If installed, you can set it as the default version using this command:"
  log "'sudo update-alternatives --config python3' or 'sudo ln -sf /usr/bin/python3.11 /usr/bin/python3'"
  exit 102
fi

# Ensure the spotify auth_token exists. If missing zotify will not be able to log in.
# The credentials.json file is required for zotify to authenticate with the Spotify API.
#
# If the token expires, delete the credentials.json file and re-run the zotify command to generate a new token json file.
# When the token is bad you usually get a 'MercuryException: status: 403' error message from zotify.
credentials_file="$HOME/.config/zotify/credentials.json"
if [[ ! -f "$credentials_file" ]]; then
  log "Error: zotify credentials.json file not found in ~/.config!"
  log "Please create the file with your Spotify API credentials." 
  exit 103
fi

# Command line argument handling
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test-run)
            isSimulation=true; shift 1 ;;
        -h|--help)
            usage; exit 0 ;;
        -v|--version)
            version; exit 0 ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Ensure the server directory exists
if [ ! -d "$file_share" ]; then
  log "The file share directory: '$file_share' does not exist."
  log "Please ensure the directory exists and is accessible and try again."
  exit 104
fi

#
# Execute the main script functions
#

# Start the application trace log
log "Started executing process: $scriptname"
log "logfile is: \"$LOGFILE\""
log "pidfile is: \"$PID_FILE\""
log "download_path is: \"$zotify_dl_path\""
log "id3tag stage_path is: \"$stage_path\""
log "file_share is: \"$file_share\""
echo ""

# Create a PID lock to create singleton execution. 
# Need to sleep for at least one second so the timestamp 
# of the PID_FILE does not match the timestamp of any files
# being actively processed by the application.
echo "$(date +"%d%b%Y.%H%M")" > "$PID_FILE"
#sleep 1s

# Trap SIGTERM broadcast to ensure the PID lock is released on exit. 
trap on_exit EXIT

# Prompt user for Spotify URLs to download
PromptForSpotifyUrls
echo ""

# Stage the downloaded rips for ID3Tag editing
StageDownloadedRips
echo ""

# Launch NTag to edit ID3Tags of the staged files
LaunchNTag
echo ""

# Copy the rips to the network file share
CopyRipsToServer
echo ""

# Cleanup: Remove the PID lock file to allow future executions of this script.
on_exit
