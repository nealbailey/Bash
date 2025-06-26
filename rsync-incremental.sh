#!/bin/bash
#: Title: Rsync-incremental Backup
#: Author: Neal T. Bailey <neal.bailey@hp.com>
#: Date: 07/10/2015
#: Updated: 02/28/2019 - new Seagate HDD volume
#: Updated: 06/24/2025 - new Seagate (22TB) HDD volume
#: Purpose: Data backup management
#
#: Usage: ./rsync-incremental [options]
#: Options:
#:  -t,      : do not make any changes on the server
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
usage="$scriptname [-c|-f|-t|-o|-l|-h|-v]"
optionusage="-c:\t\t Cleanup backups (delete obsolete files)\n  -f:\t\t Full backup (all files, not just new ones)\n  -t:\t\t Test run (commands are logged but not run)\n  -l:\t\t New log file (existing log is clobbered)\n  -o:\t\t Log to console & file (default is file only)\n  -h:\t\t Print help (this screen)\n  -v:\t\t Print version info\n"
optionexamples=" ./"$scriptname"\n  ./"$scriptname" -tl \n\n" 
date_of_creation="2025-06-26"
version=1.0.5
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

  # Verify exclusions file
  if [ ! -f "$BAK_SOURCE/rsync-exclude" ]; then
    log "Exclusions file does not exist: \"$BAK_SOURCE/rsync-exclude\""
    exit 105
  fi

  # Verify rysnc backup is not currently in progress
  if [[ -f "$BAK_SOURCE/Backup_In_Progress" ]]; then
    log "Backup process is currently running. Exiting."
    exit 106
  fi

  # Backup Files and Movies
  touch "$BAK_SOURCE/Backup_In_Progress"

  # Delete files from destination that are missing from source
  if [[ "$CLEAN_BACKUPS" == "true" ]]; then
    log "Executing rsync workflow: Cleanup --delete from destination where missing from source."
    eval_exec "rsync --verbose --recursive --ignore-existing --ignore-non-existing --delete --exclude-from=rsync-exclude \"$BAK_SOURCE\"/* \"$BAK_DEST\" 2>/dev/null | tee -a \"$LOGFILE\""
    return 0
  fi

  # Backup all files and check for changes on source that need to be synced to destination
  if [[ "$FULL_BACKUP" == "true" ]]; then
    log "Executing rsync workflow: Full and complete backup --source to destination."
    eval_exec "rsync --archive --verbose --no-compress --exclude-from=rsync-exclude \"$BAK_SOURCE\"/* \"$BAK_DEST\" 2>/dev/null | tee -a \"$LOGFILE\""
    return 0
  fi

  # Backup only files that exist on source but not destination
  log "Executing rsync workflow: Incremental backup --only new files"
  eval_exec "rsync --archive --verbose --no-compress --ignore-existing --exclude-from=rsync-exclude \"$BAK_SOURCE\"/* \"$BAK_DEST\" 2>/dev/null | tee -a \"$LOGFILE\""   
  return 0
}

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
  if [[ -f "$BAK_SOURCE/Backup_In_Progress" ]]; then
    rm -f "$BAK_SOURCE/Backup_In_Progress"
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
  printf "Usage: %s\n" "$usage"
  printf "%s  $optionusage"
  printf "\nExamples: %s\n $optionexamples"
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

# Ensure zip package is installed on server (and we know where it is)
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
  log "THIS IS A TEST RUN! EXEC COMMANDS WILL NOT BE ISSUED TO THE SERVER! THIS MODE IS FOR DEBUG OPERATIONS ONLY!"
fi

# Configure IFS to use '\n' delimiter
IFS=$'\n'

# Execute backup tasks
do_backup

# End Script logic

# Log completion
log "Completed processing backup tasks."

# Cleanup tasks
on_exit
