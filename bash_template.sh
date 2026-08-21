#!/bin/bash
#: Title: bash_template.sh
#: Purpose: Purpose and intent of the script
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#: Changes: 
#:  08/21/2026: V1.0.0 - Initial release
#:
#: Usage: $ ./bash_template.sh
#: Depends: requires package(s)
#:   package_name: package_url
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

#
# User Provided Variables
#
#file_share="path/to/resource"

#
# Metadata
#
scriptname=${0##*/}
description="Bash Script Template"
optionusage="Usage: $0 [options]\n\n Options:\n  -q, --quiet\t\tLog to file only; suppress terminal output\n  -t, --test-run\tSimulate the workflow logic without making changes\n  -h, --help\t\tDisplay this help message\n  -v, --version\t\tDisplay version information"
optionexamples="Examples:\n  $0 -q\t\tWrites to the log but not the terminal\n"
date_of_creation="2026-08-21"
version="1.0.0"
author="Neal T. Bailey"
copyright="Baileysoft Solutions"

#
# Global Variables
#
# LOG_FILE: The log file used to record all script execution
# LOCK_FILE: The file used to enforce singleton execution
# STDOUT_LOG_ONLY: Do not send stdout to console, just the log file
# IS_SIMULATION: Execute as test-run, do not make changes to the file-system
LOG_FILE="/tmp/$scriptname.log"
LOCK_FILE="/tmp/$scriptname.running"
STDOUT_LOG_ONLY="false"
IS_SIMULATION="false"

## REGION: Exit Codes
EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_ALREADY_RUNNING=101
EXIT_MISSING_DEPENDENCY=102
EXIT_INVALID_PYTHON=103
EXIT_MISSING_FILE=104
EXIT_MISSING_DIRECTORY=105
## ENDREGION: Exit Codes

## REGION: Template function definitions

#@ DESCRIPTION: Performs script cleanup and logs execution metrics.
#@ REMARKS: Invoked automatically when the shell exits.
function on_exit() {
  local exit_code=$?
  log "Completed executing process: $scriptname"  

  local seconds=$SECONDS
  local exec_time  

  exec_time=$(printf 'Process executed for: %dh:%dm:%ds' \
      "$((seconds / 3600))" \
      "$((seconds % 3600 / 60))" \
      "$((seconds % 60))")

  log "$exec_time"  
  log "Exit code: $exit_code"
}

#@ DESCRIPTION: Executes or suppresses a trusted shell command based on IS_SIMULATION.
#@ PARAM $1: The trusted shell command to execute.
#@ REMARKS:
#@   - The command is logged before execution.
#@   - Command stdout/stderr is written to both the terminal and LOG_FILE.
#@   - When IS_SIMULATION=true, the command is logged but not executed.
#@   - The argument is evaluated as shell syntax and MUST NOT contain unvalidated input.
#@ WARNING: Only the exit code for the first command in the pipeline will get returned!
#@ USAGE: eval_exec "ls \"*.txt\" ; echo $?
#@ RETURNS: Exit code returned by the executed command.
function eval_exec() {
  local command="$1"
  local result=0

  log "Exec: $command"

  if [[ "$IS_SIMULATION" == "true" ]]; then
    return "$EXIT_SUCCESS"
  fi

  # The if statement intentionally places the pipeline in a conditional
  # context so errexit does not terminate the script before PIPESTATUS
  # can be captured.
  if eval "$command" 2>&1 | tee -a "$LOG_FILE"; then
    result=${PIPESTATUS[0]}
  else
    result=${PIPESTATUS[0]}
  fi

  return "$result"
}

#@ DESCRIPTION: Prints usage information
function usage() {
    printf "%s - %s\n" "$scriptname" "$description"
    printf "%s\n $optionusage"
    printf "%s\n\n $optionexamples"
}

#@ DESCRIPTION: Print version information
function version() {
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
  
  # Do not print message to terminal
  if [[ $STDOUT_LOG_ONLY == "false" ]] ; then
    printf "%s\n" "$1"
  fi
  
  printf '%s %s\n' "$timestamp" "$1" >> "$LOG_FILE"
}

## ENDREGION: Template function definitions

## REGION: Script function definitions

# ToDo: Script specific functions

## ENDREGION: Script function definitions

# Command line argument handling
while [[ $# -gt 0 ]]; do
  case $1 in
      -t|--test-run)
          IS_SIMULATION=true; shift 1 ;;
      -q|--quiet)
          STDOUT_LOG_ONLY=true; shift 1 ;;
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

# Create the log file and set permissions to be readable and writable by the owner and readable by others.
# This creates a new log for every run of the script. 
# Change the last line to : >> "$LOG_FILE" to append instead or overwriting.
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
: > "$LOG_FILE"

# Create/open the lock file and acquire an exclusive non-blocking lock.
# This prevents multiple instances of the script from executing at the same time.
exec 200>"$LOCK_FILE"

if ! flock -n 200; then
    STDOUT_LOG_ONLY="false"
    log "A previous instance of this process is currently executing."
    log "Exit code: $EXIT_ALREADY_RUNNING"
    exit $EXIT_ALREADY_RUNNING
fi

# Save the current PID to the lock file for informational purposes.
echo "$$" >&200
#sleep 1s

# Trap shell exit to ensure cleanup is performed regardless of how the script terminates.
trap on_exit EXIT

#
# Pre-requisite sanity check. These segments ensure nothing unexpected will prevent
# the process from completing at runtime due to unknown or invalid machine configuration. 
#
## Verify that package is installed
#if ! command -v pacakge_name &> /dev/null; then
#    log "Error: package_name is not installed. Please install package_name to use this script."
#    exit "$EXIT_MISSING_DEPENDENCY"
#fi

## Verify correct Python version is in use
#if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then  
#  log "Error: This script requires Python version 3.11 or newer to run zotify properly."
#  log "INFO: If installed, you can set it as the default version using this command:"
#  log "Change python version by running: sudo update-alternatives --config python3"
#  exit "$EXIT_INVALID_PYTHON"
#fi

## Ensure a file exists 
#required_file="$HOME/path_to_file"
#if [[ ! -f "$required_file" ]]; then
#  log "Error: $required_file not found in ~/HOME"
#  exit "$EXIT_MISSING_FILE"
#fi

## Ensure a directory exists
#file_share="path_to_folder"
#if [ ! -d "$file_share" ]; then
#  log "The file share directory: '$file_share' does not exist."
#  log "Please ensure the directory exists and is accessible and try again."
#  exit "$EXIT_MISSING_DIRECTORY"
#fi

#
# Execute the main script functions
#

# Start the application trace log
# Log important variables for troubleshooting
log "Started executing process: $scriptname"
log "LOG_FILE is: \"$LOG_FILE\""
log "LOCK_FILE is: \"$LOCK_FILE\""

# Check for test-run action - write log preamble
if [[ $IS_SIMULATION == "true" ]]; then
  log "THIS IS A TEST RUN! EXEC COMMANDS WILL NOT BE ISSUED TO THE SERVER!"
fi

# Main Script Logic
#  Write function calls and commands needed for the script to be functional
#
