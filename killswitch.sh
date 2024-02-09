#!/bin/bash
#: Title: killswitch.sh
#: Author: Neal T. Bailey <nealosis@gmail.com>
#: Date: 03/25/2019
#: Updated: 04/09/2024
#: Purpose: Establish or terminate VPN killswitch
#
#: Usage: ./killswitch.sh [options]
#: Options:
#:  -s,	     : start the VPN kill-switch
#:  -d       : disable the kill-switch
#:  -t,      : do not make any changes on the server
#:  -l,      : create a new log file instead of appending
#:  -o,      : send stdout/stderr messages to the console along with the log
#:  -h,      : display help page
#:  -v,      : display version info
#
# Example: 
# # ./killswitch -s
#
# Changes:
# V1.0   - initial release
# V1.1   - added new required steps for ubuntu 22.04 UFW
#
# ----------------------------------------------------------------------
# GNU General Public License
# ----------------------------------------------------------------------
# Copyright (C) 2010-2018 Neal T. Bailey
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
SUBNET=192.168.2.0/24       	    # Local Subnet Mask
VPNIFACE=tun0			    # VPN interface
DISABLED="false"		    # Killswitch terminate flag
APPEND_LOG="true"           	    # Append to existing log file
STDOUT_LOG_ONLY="true"      	    # Send messages to terminal and log file
TEST_RUN="false"            	    # Simulate tasks but do not execute them
# This value must come from *.ovpn file (e.g. /etc/openvpn/ovpn_tcp/ca1681.nordvpn.com.tcp.ovpn)
TUNNEL="146.70.112.219 port 443 proto tcp"

# Metadata
scriptname=${0##*/}
description="Configures VPN killswitch (halt Internet if VPN drops)"
usage="$scriptname [-s|-d|-t|-l|-o|-h|-v]"
optionusage="-s:\tEnable the kill switch\n  -d:\tDisable the kill switch\n  -t:\tTest run (commands are logged but not run)\n  -l:\tNew log file (existing log is clobbered)\n  -o:\tLog to console & file (default is file only)\n  -h:\tPrint help (this screen)\n  -v:\tPrint version info\n"
optionexamples=" ./"$scriptname"\n  ./"$scriptname" -so \n\n" 
date_of_creation="2024-04-09"
version=1.1.0
author="Neal T. Bailey"
copyright="Baileysoft Solutions"
LOGFILE="/var/log/$scriptname.log"  # Log file path


# Start Function Definitions

#@ DESCRIPTION: Enables the VPN kill-switch.
function EnableKillSwitch {
  eval_exec "ufw --force reset 2>&1"
  eval_exec "ufw allow in to $SUBNET"
  eval_exec "ufw allow out to $SUBNET"
  eval_exec "ufw allow Samba 2>&1"
  eval_exec "ufw default deny incoming 2>&1"
  eval_exec "ufw default deny outgoing 2>&1"
  eval_exec "ufw allow out to $TUNNEL 2>&1"
  eval_exec "ufw allow out on $VPNIFACE from any to any 2>&1"
  eval_exec "ufw allow in on $VPNIFACE from any to any 2>&1"
  eval_exec "ufw --force enable 2>&1"
}

#@ DESCRIPTION: Enables the VPN kill-switch.
function DisableKillSwitch {
  eval_exec "ufw reset 2>&1"
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

#@ DESCRIPTION: Log message.
#@ PARAM $1: The message to log.
#@ REMARKS: Sends message to stdout with -o flag
function log   
{
  if [[ $STDOUT_LOG_ONLY == "false" ]] ; then
    echo "$1"
  fi  
  echo $(date +%Y-%m-%dT%H:%M) "$1" >> "$LOGFILE"
}

#@ DESCRIPTION: Prints usage information
function usage
{ 
  printf "%s - %s\n" "$scriptname" "$description"
  printf "Usage: %s\n" "$usage"
  printf "%s  $optionusage"
  printf "\nExamples: %s\n $optionexamples"
}

#@ DESCRIPTION: Print version information
function version
{ 
  printf "%s (v%s): %s\n" "$scriptname" "$version" "$description"
  printf "by %s, %d, %s\n" "$author"  "${date_of_creation%%-*}" "$copyright"
}

# End Function Definitions

# Command-line arguments processing
optstring=sdtlhov
while getopts $optstring opt
do
  case $opt in
  s) ;;
  d) DISABLED="true" ;;
  l) APPEND_LOG="false" ;;
  o) STDOUT_LOG_ONLY="false" ;;
  t) TEST_RUN="true" ;;
  h) usage; exit ;;
  v) version; exit ;;
  *) usage; exit ;;
  esac
done
shift "$(( $OPTIND - 1 ))"

#
# Pre-requisite sanity check. These segments ensure nothing unexpected will prevent
# the process from completing at runtime due to unknown or invalid machine configuration. 
#

# Ensure user is root
if [[ $EUID -ne 0 ]]; then
  # If user does not have root access then we cannot log the error. 
  # If user is not root they need to run this script in a terminal to see this message.
  echo "You must be root to execute this application."
  exit 100
fi

if [[ "$APPEND_LOG" == "false" ]]; then
  if [ -e "$LOGFILE" ]; then 
    # Zero out log file
    cat /dev/null > "$LOGFILE"
  fi
fi

# Start the application trace log
if [ ! -e "$LOGFILE" ]; then 
    log "Creating trace-log: $LOGFILE"
    touch "$LOGFILE" && chmod 755 "$LOGFILE"
fi

log "Started executing script tasks."

# Ensure there is a tunnel established
if [ $(ifconfig | grep -ic $VPNIFACE) -eq 0 ] ; then
  STDOUT_LOG_ONLY="false"
  log "There is no vpn tunnel established to secure (iface $VPNIFACE)."
  exit 101
fi

# Check for test-run action - write log preamble
if [[ "$TEST_RUN" == "true" ]]; then
  log "THIS IS A TEST RUN! EXEC COMMANDS WILL NOT BE ISSUED TO THE SERVER!"
fi

# Kickstart the tunnel creation process
if [[ $DISABLED == "true" ]]; then
	DisableKillSwitch
else
	EnableKillSwitch
fi

if [ $? -eq 0 ]; then
  log "Script tasks completed successfully."
else
  log "Error: Script tasks failed."
  exit 1
fi
