#!/bin/bash
#: Title: zotify_runner.sh
#: Purpose: Rips spotify tracks and copies them to a file server
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#:
#: Changes: 
#:  11/19/2022: V0.1.0 - Initial release
#:  08/14/2026: V0.2.0 - Added test-run option and improved logging
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
set -euo pipefail

# Program Variables
new_file_count=0
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
date_of_creation="2026-08-14"
version=0.2.0
author="Neal T. Bailey"
copyright="Baileysoft Solutions"

# Log file path
LOGFILE="/tmp/$scriptname.log"

# Block eval_exec from executing commands when TEST_RUN is set to true.
TEST_RUN=false  

#@ DESCRIPTION: Executes or suppresses commands based on test-run setting.
#@ PARAM $1: The command to execute.
#@ REMARKS: You must use $? to get result. 
#@ WARNING: Only the exit code for the first command in the pipeline will get returned!
#@ USAGE: eval_exec "ls \"*.txt\" 2>&1 | tee -a \"$LOGFILE\"" ; echo $?
#@ RETURNS: Exit code. 
function eval_exec
{
  local result=0
  log "Exec: $1"
  if [[ "$TEST_RUN" != "true" ]]; then
    # We only care about the exit code of the sub-shell running under the eval shell
    # So we are dumping all output from eval to the bit-bucket but capturing the 
    # 1st exit code of the first command being executed in the sub-shell pipe-line. 
    eval "${1}; "'PIPE=${PIPESTATUS[0]}' &> /dev/null 
    result=$PIPE
  fi
  return $result
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
  if [[ $new_file_count -gt 0 ]]; then
    # Verify ntag is installed
    if ! flatpak info com.github.nrittsti.NTag &>/dev/null; then
      log "Ntag flatpak not installed: com.github.nrittsti.NTag"
      log "https://flathub.org/apps/com.github.nrittsti.NTag"
      exit 100
    fi
    # Launch NTag
    log "Launching ntag: com.github.nrittsti.NTag"
    log "Don't forget to rename in ntag before editing the ID3Tags data."
    eval_exec "flatpak run com.github.nrittsti.NTag 2>&1 | tee -a \"$LOGFILE\""
  else
    log "INFO: No files were staged so no need to continue. Exiting."
    exit 1
  fi
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
  eval_exec "rm -frv \"$stage_path\"/*.mp3 2>&1 | tee -a \"$LOGFILE\""
  #eval_exec "find \"$stage_path\" -mindepth 1 -maxdepth 1 -iname \".mp3\" -exec rm -rfv -- {} + 2>&1 | tee -a \"$LOGFILE\""
  
  # Copy any music files created in the previous 24 hours into New folder
  log "Copying new zotify music downloads into staging folder"
  
  #local find_count=$(find ./Zotify\ Albums/ \( -name '*.mp3' \) -mtime -1 | wc -l)
  local find_count=$(find "$zotify_dl_path" \( -name '*.mp3' \) -mtime -1 | wc -l)
  log "Found '$find_count' new music files to stage"

  if [ "$find_count" -gt 0 ]; then
    eval_exec "find \"$zotify_dl_path\" \( -name '*.mp3' \) -mtime -1  -exec cp -uv {} \"$stage_path\" \; 2>&1 | tee -a \"$LOGFILE\""
  fi
  new_file_count="$find_count"
}

# #@ DESCRIPTION: Copies rips from temp staging path to network file share.
function CopyRipsToServer
{ 
  # Ensure the server directory exists
  if [ ! -d "$file_share" ]; then
    log "The server directory \"$file_share\" does not exist. Is it mounted?"
    return 1
  fi
  log "Copying new music files to server share: $file_share"
  
  if [[ $isSimulation == true ]]; then
    log "Simulation mode enabled - skipping copying files to server."
    return 0
  fi

  eval_exec "cp -uv \"$stage_path\"/*.mp3 \"$file_share\" 2>&1 | tee -a \"$LOGFILE\""  
}

# Create the log file and set permissions to be readable and writable by the user only.
touch "$LOGFILE"
chmod 600 "$LOGFILE"
: > "$LOGFILE"

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

#
# Execute the main script functions
#

# Prompt user for Spotify URLs to download
PromptForSpotifyUrls

# Stage the downloaded rips for ID3Tag editing
StageDownloadedRips

# Launch NTag to edit ID3Tags of the staged files
LaunchNTag

# Copy the rips to the network file share
CopyRipsToServer
