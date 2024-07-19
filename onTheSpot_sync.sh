#!/bin/bash
#: Title: onTheSpot_sync.sh
#: Purpose: Copies ripped spotify files to file server
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#:
#: Changes: 
#:  07/10/2024: V0.1 - Initial release
#:
#: Usage: $ ./onTheSpot_sync.sh
#: Depends: requires package(s)
#:   OnTheSpot AppImage: https://github.com/casualsnek/onthespot
#:   NTag flatpak: https://flathub.org/apps/com.github.nrittsti.NTag
#:
#
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
  local appImg="onthespot_linux"
  if [[ ! -f "$appFolder/$appImg" ]] ; then    
    log "Could not find OnTheSpot AppImage: '$appFolder/$appImg'"
    log "https://github.com/casualsnek/onthespot"
    exit 101
  fi

  log "Launching Spotify Ripping Tool"
  cd "$appFolder" && ./$appImg
}

#@ DESCRIPTION: Launch ntag package to update file ID3Tags.
function LaunchNTag()
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
  log "Copying new music files into New staging folder"
  local find_count=$(find ./OnTheSpot/ \( -name '*.mp3' \) -mtime -1 | wc -l)
  log "Found '$find_count' new music files to stage"

  if [ "$find_count" -gt 0 ]; then
    eval_exec "cd ~/Music && find ./OnTheSpot \( -name '*.mp3' \) -mtime -1  -exec cp -uv {} ~/Music/New \; 2>&1"
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

LaunchOnTheSpotRipper
StageDownloadedRips
LaunchNTag
CopyRipsToServer
