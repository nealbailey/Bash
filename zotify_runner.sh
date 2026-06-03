#!/bin/bash
#: Title: zotify_runner.sh
#: Purpose: Rips spotify tracks and copies them to a file server
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#:
#: Changes: 
#:  11/19/2025: V0.1 - Initial release
#:
#: Usage: $ ./zotify_runner.sh
#: Depends: requires package(s)
#:   zotify: https://github.com/DraftKinner/zotify.git
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
# Copyright (c) 2014-2024 Baileysoft Solutions
#-----------------------------------------------------------------------

new_file_count=0
file_share="/home/nealosis/Network/baileyfs02.baileysoft.lan/Files/Uploads/Music"
python_changed=false

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

#@ DESCRIPTION: Log message.
#@ PARAM $1: The message to log.
#@ REMARKS: Sends message to stdout with -o flag
function log   
{
  echo $(date +%Y-%m-%dT%H:%M) "$1" # >> "$LOGFILE"
}

#@ DESCRIPTION: Launch OnTheSpot spotify ripping tool.
function LaunchOnTheSpotRipper
{
  local appFolder="/home/nealosis/Applications"
  local appImg="OnTheSpot-x86_64.AppImage"
  if [[ ! -f "$appFolder/$appImg" ]] ; then    
    log "Could not find OnTheSpot AppImage: '$appFolder/$appImg'"
    log "https://github.com/casualsnek/onthespot"
    exit 101
  fi

  log "Launching Spotify Ripping Tool"
  cd "$appFolder" && ./$appImg
}

#@ DESCRIPTION: Prompt user for spotify URLs to download using zotify.
function PromptForSpotifyUrls
{
  while true; do
    read -p "Paste the full Spotify URL to download: " url
    log "Downloading from URL: $url"
    zotify "$url" --audio-format=mp3 --download-quality=very_high

    # Ask if the user wants to download another URL
    read -p "Download another spotify link? (y/n): " answer
    if [[ "$answer" =~ ^[nN]$ ]]; then
      log "zotify downloads completed."
      break
    fi
  done
}

#@ DESCRIPTION: Launch ntag package to update file ID3Tags.
function LaunchNTag
{
  if [[ $new_file_count -gt 0 ]]; then
    # Verify ntag is installed
    if [ $(flatpak list --columns=name,application | grep -ic com.github.nrittsti.NTag) -eq 0 ] ; then
      log "Ntag flatpak not installed: com.github.nrittsti.NTag"
      log "https://flathub.org/apps/com.github.nrittsti.NTag"
      exit 100
    fi
    # Launch NTag
    log "Launching ntag: com.github.nrittsti.NTag"
    log "Don't forget to rename in ntag before editing the ID3Tags data."
    eval_exec "flatpak run com.github.nrittsti.NTag"
  else
    log "INFO: No files were staged so no need to continue. Exiting."
    exit 1
  fi
}

#@ DESCRIPTION: Copies rips from download path to temp staging path.
function StageDownloadedRips
{
  # Delete everything in New staging folder
  log "Delete everything in the New staging folder"
  eval_exec "rm -frv ~/Music/New/* 2>&1"
  eval_exec "cd /home/nealosis/Music"

  # Copy any music files created in the previous 24 hours into New folder
  log "Copying new zotify music downloads into staging folder"
  #local find_count=$(find ./Zotify\ Albums/ \( -name '*.mp3' \) -mtime -1 | wc -l)
  local find_count=$(find ./Zotify\ Playlists/ \( -name '*.mp3' \) -mtime -1 | wc -l)
  log "Found '$find_count' new music files to stage"

  if [ "$find_count" -gt 0 ]; then
    eval_exec "find ./Zotify\ Playlists \( -name '*.mp3' \) -mtime -1  -exec cp -uv {} ~/Music/New \; 2>&1"
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
  eval_exec "cp -uv ~/Music/New/* $file_share"  
}

#
# Pre-requisite sanity check. These segments ensure nothing unexpected will prevent
# the process from completing at runtime due to unknown or invalid machine configuration. 
#
# Verify that zotify is installed
if ! command -v zotify &> /dev/null; then
    log "Error: zotify is not installed. Please install zotify to use this script."
    exit 101
fi

# Verify correct python version is in use
if [ $(python3 --version | grep 3.11 | wc -l) -eq 0 ]; then
  python_changed=true
  log "Error: This script requires Python version 3.11 to run zotify properly." 
  log "INFO: If installed, you can set it as the default version using this command:"
  log "'sudo update-alternatives --config python3' or 'sudo ln -sf /usr/bin/python3.11 /usr/bin/python3'"
  exit 102
fi 

# Ensure the spotify auth_token exists. If missing zotify will not be able to log in.
# The credentials.json file is required for zotify to authenticate with the Spotify API.
# If the token expires, delete the credentials.json file and re-run the zotify command to generate a new token json file.
if [ $(find ~/.config -iname credentials.json 2>/dev/null | wc -l) -eq 0 ]; then
  log "Error: zotify credentials.json file not found in ~/.config!"
  log "Please create the file with your Spotify API credentials." 
  exit 103
fi 

#LaunchOnTheSpotRipper
PromptForSpotifyUrls
StageDownloadedRips
LaunchNTag
CopyRipsToServer

# Old version of Ubuntu uses python 3.10 but zotify requires 3.11 but changing the python version
# and not restoring the original version breaks the terminal. 
# So we are reminding the user to change it back if we had to change it to run zotify.
if [ $(python3 --version | grep 3.11 | wc -l) -eq 1 ]; then
  python_changed=true  
fi

# Remind user to change python version back if we had to change it to run zotify.
if [ "$python_changed" = true ]; then
  log "INFO: Python version was changed to run zotify."
  log "INFO: You must restore the previous version or your terminal will not function correctly."
  log "'sudo update-alternatives --config python3'"
fi