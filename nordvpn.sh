#!/bin/bash
#: Title: nordvpn.sh
#: Author: Neal T. Bailey <nealosis@gmail.com>
#: Date: 07/10/2015
#: Updated: 02/09/2024
#: Purpose: Create a split VPN tunnel
#
#: Usage: ./nordvpn.sh [options]
#: Options:
#:  -s,	     : start the VPN split tunnel
#:  -t,      : do not make any changes on the server
#:  -l,      : create a new log file instead of appending
#:  -o,      : send stdout/stderr messages to the console along with the log
#:  -h,      : display help page
#:  -v,      : display version info
#
# Example: 
# # ./nordvpn.sh -s
#
# Changes:
# V1.0   - initial release
# V2.0   - echo new ip address after establishing tunnel
# V2.3   - added feature to close tunnel without having to restart the server
# V2.4   - added feature to reset firewall rules when closing tunnel
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

# NordVPN working Directory
VPN_CWD="/etc/openvpn"                   
# NordVPN config file 
NORDVPN_CONF="$VPN_CWD/ovpn_tcp/ca1681.nordvpn.com.tcp.ovpn"     
# NordVPN credentials file
NORDVPN_CRED="$VPN_CWD/login_nord.txt"
# NordVPN ovn command 
VPN_CMD="openvpn --config $NORDVPN_CONF --auth-user-pass $NORDVPN_CRED --script-security 2"

TORRENT_SERVICE="transmission-daemon"    # Optional torrent daemon
TORRENT_SERVICE_INSTALLED="true"         # Flag to indicate whether to do torrent steps
APPEND_LOG="true"                        # Append to existing log file
STDOUT_LOG_ONLY="true"                   # Send messages to terminal and log file
TEST_RUN="false"                         # Simulate tasks but do not execute them
CREATE_TUNNEL="false"                    # Create a new openvpn tunnel
DESTROY_TUNNEL="false"                   # Close any existing openvpn tunnel

# Metadata
scriptname=${0##*/}
description="Establishes a split-tunnel VPN connection."
usage="$scriptname [-d|-s|-t|-l|-o|-h|-v]"
optionusage="-d:\tDestroy existing openVPN tunnel and stop transmission-daemon\n  -s:\tStart openVPN tunnel and start transmission-daemon\n  -t:\tTest run (commands are logged but not run)\n  -l:\tNew log file (existing log is clobbered)\n  -o:\tLog to console & file (default is file only)\n  -h:\tPrint help (this screen)\n  -v:\tPrint version info\n"
optionexamples=" ./"$scriptname"\n  ./"$scriptname" -so \n\n" 
date_of_creation="2024-02-09"
version=2.4.0
author="Neal T. Bailey"
copyright="Copyright, Baileysoft Solutions"

LOGFILE="/var/log/$scriptname.log"       # Log file path

# Add admin bin to current PATH
export PATH=$PATH:/sbin

# Start Function Definitions

#@ DESCRIPTION: Injects DNS and local LAN routes into routing table.
#@ RETURNS: Exit code.
function configureSplitTunnel 
{
  log "Configuring split tunnel."
  log "Starting internet ip: $(dig +short myip.opendns.com @resolver1.opendns.com)"
  
  # Stop the transmission daemon  
  if [[ $TORRENT_SERVICE_INSTALLED = "true" ]]; then
    log "Stopping service $TORRENT_SERVICE."
    eval_exec "service $TORRENT_SERVICE stop 2>&1"
  fi

  EstablishVpnTunnel

  # Wait for the background ovpn tunnel to connect
  sleep 5
  log "Current internet ip: $(dig +short myip.opendns.com @resolver1.opendns.com)"
  
  # Start the transmission daemon
  if [[ $TORRENT_SERVICE_INSTALLED = "true" ]]; then
    sleep 3
    log "Starting service $TORRENT_SERVICE"
    eval_exec "service $TORRENT_SERVICE start 2>&1"
  fi  
  
  return 0
}

#@ DESCRIPTION: Establishes the VPN tunnel.
#@ RETURNS: Exit code.
function EstablishVpnTunnel()
{ 
  cd $VPN_CWD
  log "Establishing OpenVPN tunnel."
  log "$VPN_CMD 2>&1 &"
  $VPN_CMD 2>&1 >> "$LOGFILE" &
  
  if [ $? -ne 0 ]; then
    log "Error: OpenVPN returned an error code."
	  exit 1
  fi
}

#@ DESCRIPTION: Tears down the existing vpn tunnel.
#@ RETURNS: Exit code.
function destroyVpnTunnel()
{
  local pid="$(pidof openvpn)"
  if [[ "$pid" -le 0 ]]; then
    echo "Info: No OpenVPN tunnels found to close."
    return 0
  fi

  log "Closing split tunnel ovpn connection."
  #log "Starting internet ip: $(dig +short myip.opendns.com @resolver1.opendns.com)"
  
  # Stop the transmission daemon  
  if [[ $TORRENT_SERVICE_INSTALLED = "true" ]]; then
    log "Stopping service $TORRENT_SERVICE."
    eval_exec "service $TORRENT_SERVICE stop 2>&1"
  fi

  log "Killing ovpn pid $pid."
  eval_exec "kill $pid 2>&1"
  
  # Reset firewall settings (killswitch)
  log "Disable killswitch firewall configration"
  eval_exec "ufw --force reset 2>&1"

  # Wait for the background ovpn tunnel to close
  sleep 5
  log "Current internet ip: $(dig +short myip.opendns.com @resolver1.opendns.com)"

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
  printf "%s (v%s)\n" "$scriptname" "$version"
  printf "by %s, %d\n" "$author"  "${date_of_creation%%-*}"
  printf "%s\n" "$copyright"
}

# End Function Definitions

# Command-line arguments processing
optstring=dstlhov
while getopts $optstring opt
do
  case $opt in
  d) DESTROY_TUNNEL="true" ;;
  s) CREATE_TUNNEL="true" ;;
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
  # Zero out log file
  cat /dev/null > "$LOGFILE"
fi

# Start the application trace log
if [[ ! -e "$LOGFILE" ]] ; then
  touch "$LOGFILE"
fi 

chmod 755 "$LOGFILE" && log "Started executing script tasks."

# Ensure openvpn package is installed
if [ $(which openvpn | grep -c "openvpn") -eq 0 ] ; then
  STDOUT_LOG_ONLY="false"
  log "OpenVPN is not installed on this device."
  log "https://support.nordvpn.com/Connectivity/Linux/1047409422/How-can-I-connect-to-NordVPN-using-Linux-Terminal.htm"
  exit 102
fi

# Check if transmission-daemon is installed
if [ $(which transmission-daemon | grep -c "daemon") -eq 0 ] ; then
  STDOUT_LOG_ONLY="false"
  log "transmission-daemon is not installed on this device."
  TORRENT_SERVICE_INSTALLED="false"
fi

# Tear down any existing tunnel before establishing a new one
if [ "$DESTROY_TUNNEL" == "true" ]; then
  destroyVpnTunnel
fi 

# Ensure there is not already a tunnel established
if [ $(ifconfig | grep -ic tun0) -ne 0 ] ; then
  STDOUT_LOG_ONLY="false"
  log "A tunnel is already established on iface tun0."
  exit 101
fi

# Check for test-run action - write log preamble
if [[ "$TEST_RUN" == "true" ]]; then
  log "THIS IS A TEST RUN! EXEC COMMANDS WILL NOT BE ISSUED TO THE SERVER!"
fi

# Kickstart the tunnel creation process
if [ "$CREATE_TUNNEL" == "true" ]; then

  # Ensure the NordVPN configuration file exists.
  if [[ ! -f "$NORDVPN_CONF" ]] ; then
    STDOUT_LOG_ONLY="false"
    log "Could not find the NordVPN configuration file necessary to open a connection."
    log "https://nordvpn.com/ovpn/"
    exit 103
  fi

  # Ensure the NordVPN credentials file exists.
  if [[ ! -f "$NORDVPN_CRED" ]] ; then
    STDOUT_LOG_ONLY="false"
    log "Could not find the NordVPN credentials file necessary to authenticate a connection."
    log "Not found: $NORDVPN_CRED"
    exit 104
  fi

  # Create the tunnel
  configureSplitTunnel
fi 

if [ $? -eq 0 ]; then
  log "Script tasks completed successfully."

  if [ "$CREATE_TUNNEL" == "true" ]; then
    log "Be sure to enable the killswitch before downloading anything!"
  fi   
else
  log "Error: Script tasks failed."
  exit 1
fi
