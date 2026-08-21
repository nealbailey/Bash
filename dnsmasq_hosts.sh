#!/bin/bash
#: Title: dnsmasq_hosts.sh
#: Purpose: Updates dnsmasq hosts file to block ads for all network devices 
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#: Changes: 
#:  08/21/2026: V1.0.0 - Initial release
#:
#: Usage: $ ./dnsmasq_hosts.sh
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
# hosts_blocklist_url: the url to the blocklist
# hosts_blocklist_file: the addn-hosts path value defined in dnsmasq to load extra hosts
# known_ad_domain: known advertiser domain (should get blocked)
# dnsmasq_host_dns: the dns server running dnsmasq
# dnsmasq_conf: the path to the dnsmasq configuration
# dnl_hosts_count: the number of downloaded host entries (remote)
# dns_hosts_count: the number of host entries loaded into dnsmasq (local)
hosts_blocklist_url="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
hosts_blocklist_file="/etc/hosts_adblock"
known_ad_domain="analytics.google.com"
dnsmasq_host_dns="192.168.2.1"
dnsmasq_conf="/etc/dnsmasq.conf"
dnl_hosts_count="0"
dns_hosts_count="0"
#
# Metadata
#
scriptname=${0##*/}
description="Updates dnsmasq hosts file with latest ads blocklist"
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
EXIT_ALREADY_RUNNING=1
EXIT_GENERAL_ERROR=2
EXIT_GENERAL_DNS_ERROR=3
EXIT_INVALID_CONFIGURATION=4
EXIT_MISSING_DEPENDENCY=5
EXIT_MISSING_FILE=6
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

  log "EXEC: $command"

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

#@ DESCRIPTION: Download the remote blocklist
function download_blocklist() {

  # Make a backup of the downloaded hosts, if there are more than 10K entries (meaning its probably a good file)
  if [ -f "$hosts_blocklist_file" ] && [ $(wc -l < "$hosts_blocklist_file") -gt 10000 ]; then
    log "Backing up existing dnsmasq_hosts table."
    eval_exec "mv -f \"$hosts_blocklist_file\" \"$hosts_blocklist_file\".orig"
  fi

  log "Downloading the latest ad-block hosts file"

  # Rules:
  # * Ignore comments beginning with #
  # * Ignore blank lines
  # * Ignore 127.0.0.1 entries
  # * Ignore the ::1 entries already present in the source
  # * Ignore the 255.255.255.255 entry
  # * Process only 0.0.0.0 domain entries
  # * Output both 0.0.0.0 domain and ::1 domain
  eval_exec 'curl "$hosts_blocklist_url" 2>/dev/null |
  awk '\''$1 == "0.0.0.0" && $2 != "0.0.0.0" && !a[$2]++ {
    print "0.0.0.0", $2
    print "::1", $2
  }'\'' > "$hosts_blocklist_file"'

  # Save the number of hosts parsed in the downloaded hosts table
  dnl_hosts_count=$(wc -l < "$hosts_blocklist_file")
}

#@ DESCRIPTION: Load the downloaded blocklist into dnsmasq
function apply_blocklist() {
  # Reload hosts table
  log "Restarting dnsmasq service to apply the new blocklist"
  eval_exec "sudo /etc/init.d/dnsmasq restart"

  # Have to wait for the service restart to complete or we always get 0 as the count below
  log "Pausing for 5 seconds to allow service to fully reload"
  sleep 5s

  # Count host enties loaded into dnsmasq
  dns_hosts_count=$(systemctl status dnsmasq.service | grep "$hosts_blocklist_file" | awk '{print $9}')
  log "Loaded $dns_hosts_count host entries into dns hosts table to block"
}

#@ DESCRIPTION: Validate the blocklist was loaded and is working as expected 
function validate_blocklist() {
  log "Starting validation tasks"
  log "Host entries downloaded = $dnl_hosts_count"
  log "Host entries loaded into DNS = $dns_hosts_count"

  if [[ $dnl_hosts_count -ne $dns_hosts_count ]]; then
    log "WARN: the downloaded host count doesn't match the loaded host count"
  fi

  log "Testing ad-blocking functionality"
  log "EXEC: host $known_ad_domain $dnsmasq_host_dns | grep \"has address 0.0.0.0\""

  if ! host "$known_ad_domain" "$dnsmasq_host_dns" grep -q 'has address 0\.0\.0\.0'; then
    log "WARN: known ad domain was NOT blocked!"
    eval_exec "host $known_ad_domain $dnsmasq_host_dns"
    exit "$EXIT_GENERAL_DNS_ERROR"
  fi

  log "Adblock tests passed. Network ad blocking is enabled and working correctly"
  return $EXIT_SUCCESS
}

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

# Ensure user is root
if [[ $EUID -ne 0 ]]; then  
  # If user is not root they need to run this script in a terminal to see this message.  
  echo "You must be root to execute this application."
  exit 100
fi

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
# Verify that curl is installed
if ! command -v curl &> /dev/null; then
    log "Error: curl is not installed. Please install curl to use this script."
    exit "$EXIT_MISSING_DEPENDENCY"
fi

# Verify that dnsmasq is installed
if ! command -v dnsmasq &> /dev/null; then
    log "Error: dnsmasq is not installed. Please install dnsmasq to use this script."
    exit "$EXIT_MISSING_DEPENDENCY"
fi

# Ensure a file exists 
if [[ ! -f "$dnsmasq_conf" ]]; then
  log "Error: $dnsmasq_conf not found. Please install and setup dnsmasq and try again."
  exit "$EXIT_MISSING_FILE"
fi

# Ensure dnsmasq is setup to load external host entries
external_host_file=$(grep -i 'addn-hosts' "$dnsmasq_conf" | cut -d'=' -f2)
if [[ -z $external_host_file ]]; then
  log "Error: addn-hosts key in $dnsmasq_conf is empty"    
  exit $EXIT_INVALID_CONFIGURATION
fi

# Warn the user that the file they are downloading won't be loaded into dnsmasq
# If the path defined in this script doesn't match the path defined in the dnsmasq.conf
if [[ "$hosts_blocklist_file" != "$external_host_file" ]] ; then
  log "WARN: Defined block list file doesn't match the dnsmasq addn-hosts setting!"
  log "hosts_blocklist_file: $hosts_blocklist_file"
  log "external_host_file: $external_host_file"
  log "This will lead to unexpected results."  
fi

#
# Execute the main script functions
#

# Start the application trace log
# Log important variables for troubleshooting
log "Started executing process: $scriptname"
log "logfile is: $LOG_FILE"
log "lockfile is: $LOCK_FILE"
log "hosts_blocklist_url is: $hosts_blocklist_url"
log "hosts_blocklist_file is: $hosts_blocklist_file"
log "known_ad_domain is: $known_ad_domain"
log "dnsmasq_host_dns is: $dnsmasq_host_dns"
log "dnsmasq_conf is: $dnsmasq_conf"

# Check for test-run action - write log preamble
if [[ $IS_SIMULATION == "true" ]]; then
  log "THIS IS A TEST RUN! EXEC COMMANDS WILL NOT BE ISSUED TO THE SERVER!"
fi

# Main Script Logic

# Download the advertising and malware blocklist
download_blocklist

# Load the blocklist into dnsmasq DNS
apply_blocklist

# Validate the blocklist was loaded and is functional
validate_blocklist
