#!/bin/bash
#: Title: Rsync-incremental Backup
#: Author: Neal T. Bailey <neal.bailey@hp.com>
#: Date: 07/10/2015
#: Updated: 02/28/2019 - new Seagate HDD volume
#: Updated: 06/24/2025 - new Seagate (22TB) HDD 
#: Updated: 07/07/2026 - added check to ensure backup volume is mounted
#: Updated: 10/28/2026 - added rsync checking so success code isn't returned when rsync fails
#: Purpose: Data backup management
#
#: Usage: ./rsync-incremental [options]
#: Options:
#:  -t,      : preview rsync changes without modifying backup data
#:  -l,      : create a new log file instead of appending
#:  -o,      : send stdout/stderr messages to the console along with the log
#:  -h,      : display help page
#:  -v,      : display version info
#
# Example: 
# # ./rsync-incremental -lo 
#
# Changes:
# V1.0   - initial release
# V1.0.1 - bugfix: fixed issue where incorrect runtime message is being reported
# V1.0.2 - refactor
# V1.0.3 - moved TV Shows-Kids to alternate backup volume
# V1.0.4 - cleaned up code so there is only 2 backup tasks; Files and Videos
# V1.0.5 - cleaned up code so that there is only 1 backup task: full server
# V1.0.6 - added check to ensure backup volume is mounted before proceeding with backup tasks
# V1.0.7 - added rsync checking so success code isn't returned when rsync fails
#
# ----------------------------------------------------------------------
# GNU General Public License
# ----------------------------------------------------------------------
# Copyright (C) 2010-2013 Neal T. Bailey
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
#
# ----------------------------------------------------------------------

# Metadata
scriptname=${0##*/}
description="Creates incremental data backups."
usage="$scriptname [options]"
date_of_creation="2026-10-28"
version=1.0.7
author="Neal T. Bailey"
copyright="Baileysoft Solutions"

# User defined variables

# Files backup source & destination
BAK_SOURCE="/mnt/md0"
BAK_DEST="/mnt/seagate22tb"

# Global application variables
LOGFILE="/var/log/$scriptname.log"
APPEND_LOG="true"
STDOUT_LOG_ONLY="true"
CLEAN_BACKUPS="false"
FULL_BACKUP="false"
TEST_RUN="false"
BACKUP_MARKER_CREATED="false"
PID_FILE="/tmp/$scriptname.running"
BAK_IFS="$IFS" # Backup Internal Field Separator (IFS) 

# Function Definitions

#@ DESCRIPTION: Creates the server backup.
#@ REMARKS: This method will back up everything except: Downloads, Backup, lost+found
function do_backup
{
  # Verify source
  if [ ! -d "$BAK_SOURCE" ]; then
    log "Source path does not exist: \"$BAK_SOURCE\""
	exit 103
  fi

  # Verify destination
  if [ ! -d "$BAK_DEST" ]; then
    log "Backup destination path does not exist: \"$BAK_DEST\""
    exit 104
  fi

  # Both paths must be mount points, not directories on the root filesystem.
  if ! mountpoint -q -- "$BAK_SOURCE"; then
    STDOUT_LOG_ONLY="false"
    log "ERROR: Source \"$BAK_SOURCE\" is not mounted. Aborting backup."
    return 105
  fi

  if ! mountpoint -q -- "$BAK_DEST"; then
    STDOUT_LOG_ONLY="false"
    log "ERROR: Destination \"$BAK_DEST\" is not mounted. Aborting backup."
    return 105
  fi

  # Verify exclusions file
  if [ ! -f "$BAK_SOURCE/rsync-exclude" ]; then
    log "Exclusions file does not exist: \"$BAK_SOURCE/rsync-exclude\""
    log "Create \"$BAK_SOURCE/rsync-exclude\" with one relative folder name per line."
    log "These folders will be ignored during rsync:"
    log "  Backup"
    log "  Downloads"
    log "  VMWare VMs"
    log "  VirtualBox VMs"
    log "  lost+found"
    exit 106
  fi

  # Verify rysnc backup is not currently in progress
  if [[ -f "$BAK_SOURCE/Backup_In_Progress" ]]; then
    log "Backup process is currently running. Exiting."
    exit 107
  fi

  if [[ "$TEST_RUN" != "true" ]]; then
    if ! touch "$BAK_SOURCE/Backup_In_Progress"; then
      log "ERROR: Cannot create backup in-progress marker."
      return 108
    fi
    BACKUP_MARKER_CREATED="true"
  fi

  # Set working directory
  if ! cd "$BAK_SOURCE"; then
    log "ERROR: Cannot enter backup source \"$BAK_SOURCE\"."
    return 109
  fi

  local -a rsync_options=(-av --modify-window=1 --no-perms --no-owner --no-group --exclude-from=rsync-exclude)
  if [[ "$TEST_RUN" == "true" ]]; then
    rsync_options+=(--dry-run --itemize-changes)
  fi

  # Delete files from destination that are missing from source
  if [[ "$CLEAN_BACKUPS" == "true" ]]; then
    log "Executing rsync workflow: Cleanup --delete from destination where missing from source."
    rsync_options+=(--delete --ignore-existing)
  elif [[ "$FULL_BACKUP" == "true" ]]; then
    log "Executing rsync workflow: Full and complete backup --source to destination."
    # exFat USB filesystem needs special switches 
    rsync_options+=(--delete --no-compress)
  else
    log "Executing rsync workflow: Incremental backup --only new files"
    rsync_options+=(--no-compress --ignore-existing)
  fi

  run_rsync "${rsync_options[@]}" "$BAK_SOURCE/" "$BAK_DEST/"
  return $?
}

#@ DESCRIPTION: Runs rsync and logs output, reporting either pipeline failure.
#@ PARAM: Arguments passed directly to rsync.
function run_rsync
{
  local command_text
  local -a pipeline_status
  printf -v command_text '%q ' rsync "$@"
  if ! log "Exec: $command_text"; then
    printf 'ERROR: Cannot write to log file: %s\n' "$LOGFILE" >&2
    return 1
  fi

  if [[ "$STDOUT_LOG_ONLY" == "false" ]]; then
    rsync "$@" 2>&1 | tee -a "$LOGFILE"
    pipeline_status=("${PIPESTATUS[@]}")
  else
    rsync "$@" 2>&1 | tee -a "$LOGFILE" > /dev/null
    pipeline_status=("${PIPESTATUS[@]}")
  fi

  if (( pipeline_status[0] != 0 )); then
    printf 'ERROR: rsync failed with exit status %s.\n' "${pipeline_status[0]}" >&2
  fi
  if (( pipeline_status[1] != 0 )); then
    printf 'ERROR: tee failed with exit status %s; backup log may be incomplete.\n' "${pipeline_status[1]}" >&2
  fi
  if (( pipeline_status[0] != 0 )); then
    return "${pipeline_status[0]}"
  fi
  return "${pipeline_status[1]}"
}

#@ DESCRIPTION: Calculates the amounts of seconds that have passed since a file was modified.
#@ REMARKS: You must use $? to get result.
#@ PARAM $1: The full file name (including path).
#@ USAGE: seconds=$(get_seconds_since_modification "$FILE_NAME")
#@        echo $seconds
#@ RETURNS: Exit code. 
function get_seconds_since_modification 
{
  local seconds=0
  if [[ -f "$1" ]] ; then
    seconds=`echo $(($(date +%s)-$(date +%s -r "$1")))`
  fi
  echo $seconds
}

#@ DESCRIPTION: Log message.
#@ PARAM $1: The message to log.
#@ REMARKS: Sends message to stdout with -o flag
function log()     
{
  if [[ $STDOUT_LOG_ONLY == "false" ]] ; then
    echo "$1"
  fi  
  echo $(date +%Y-%m-%dT%H:%M) "$1" >> "$LOGFILE"
}

#@ DESCRIPTION: Unlocks the process
#@ REMARKS: Handles the SIGTERM EXIT broadcast
function on_exit() 
{
  if [[ "$BACKUP_MARKER_CREATED" == "true" ]]; then
    rm -f "$BAK_SOURCE/Backup_In_Progress"
    BACKUP_MARKER_CREATED="false"
  fi
  
  if [[ -f "$PID_FILE" ]] ; then
    local seconds=$(get_seconds_since_modification "$PID_FILE")
    printf 'Process executed for:\t%dh:%dm:%ds\n' $(($seconds/3600)) $(($seconds%3600/60)) $(($seconds%60))
    # ToDo: log above message -->what if error accessing log?	
    rm -f "$PID_FILE"
  fi
  IFS=$BAK_IFS 
}

#@ DESCRIPTION: Prints usage information
function usage()   
{ 
  printf "%s - %s\n" "$scriptname" "$description"
  printf "\nUsage: %s\n" "$usage"
  printf "\nOptions:\n"
  printf "  %-4s  %s\n" \
    "-c" "Cleanup backups (delete obsolete files)" \
    "-f" "Full backup (all files, not just new ones)" \
    "-t" "Dry run (preview changes; backup data is unchanged)" \
    "-l" "New log file (existing log is clobbered)" \
    "-o" "Log to console & file (default is file only)" \
    "-h" "Print help (this screen)" \
    "-v" "Print version info"
  printf "\nExamples:\n"
  printf "  ./%s\n  ./%s -tl\n  ./%s -tco\n\n" "$scriptname" "$scriptname" "$scriptname"
}

#@ DESCRIPTION: Print version information
function version() 
{                  
  printf "%s v%s (%s)\n" "$scriptname" "$version" "$date_of_creation"
  #printf "By: %s, %d\n" "$author"  "${date_of_creation%%-*}"
  printf "%s, %s\n" "$copyright" "${date_of_creation%%-*}"
}

# End Function Definitions


# Ensure user is root
if [[ $EUID -ne 0 ]]; then
   # If user does not have root access then we cannot log the error. 
   # If user is not root they need to run this script in a terminal to see this message. 
   echo "You must be root to execute this application." 1>&2
   exit 100
fi

# Command-line arguments processing
optstring=cftlohv
while getopts $optstring opt
do
  case $opt in
  c) CLEAN_BACKUPS="true" ;;
  f) FULL_BACKUP="true" ;;
  t) TEST_RUN="true" ;;
  l) APPEND_LOG="false" ;;
  o) STDOUT_LOG_ONLY="false" ;;
  h) usage; exit ;;
  v) version; exit ;;
  *) usage; exit ;;
  esac
done
shift "$(( $OPTIND - 1 ))"

# Ensure the script is not currently in a RUNNING state.
if [[ -f "$PID_FILE" ]] ; then
  echo "A previous instance of this process is currently executing."
  exit 101
fi

if [[ "$APPEND_LOG" == "false" ]]; then
  # Zero out log file
  cat /dev/null > "$LOGFILE"
fi

# Start the application trace log
log "Started processing backup tasks."

#
# Pre-requisite sanity check. These segments ensure nothing unexpected will prevent
# the process from completing at runtime due to unknown or invalid machine configuration. 
#

# Ensure rsync package is installed on server (and we know where it is)
if [ $(which rsync | grep -c "rsync") -eq 0 ]; then
  log "Error: rsync package is not installed on this machine (not found)!" 
  exit 102
fi 

# End Pre-requisite sanity check

# Begin Script logic

# Create a PID lock to create singleton execution. 
# Need to sleep for at least one second so the timestamp 
# of the PID_FILE does not match the timestamp of any files
# being actively processed by the application.
echo "$(date +"%d%b%Y.%H%M")" > "$PID_FILE"
sleep 2s

# Trap SIGTERM broadcast to ensure the PID lock is released on exit. 
trap on_exit EXIT

# Check for test-run action - write log preamble
if [[ "$TEST_RUN" == "true" ]]; then
  log "DRY RUN: rsync will preview changes without modifying backup data."
fi

# Configure IFS to use '\n' delimiter
IFS=$'\n'

# Execute backup tasks
do_backup
backup_status=$?

if (( backup_status != 0 )); then
  log "ERROR: Backup task failed with exit status $backup_status."
  exit "$backup_status"
fi

# End Script logic

# Log completion only after a successful task
log "Completed processing backup tasks."

# Cleanup tasks
on_exit
