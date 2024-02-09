#!/bin/bash
#: Title: map-shares.sh
#: Purpose: Mounts windows shares
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#:
#: Changes: 
#:  03/31/2011: V0.1 - Initial release
#:              V0.2 - Removed required root access
#:                   - Changed mount points from /media to ~/network
#:              V0.3 - Dyamically determine mount point and shares
#:                   - Don't display shares that are already mounted
#:              V0.4 - Added support for external share definitions in .mount file
#:              V0.5 - Added support for existing .cifspw credentials file
#:  08/07/2015: V0.6 - Added support for Windows UNC paths
#:                   - Removed default shares if config file is absent
#:  08/13/2015: V0.7 - Added checks to ensure user is in group
#:                     Added checks to determine if sudoer rights are correct
#:  08/02/2022: V0.8 - Added vers=2.0 option since mount.cifs now defaults to encrypted V3.0 smbfs 
#:
#: Usage: $ ./map-shares.sh
#: Depends: requires package(s)
#:   cifs-utils
#:   zenity
#:
#
#  Install: copy into ~/.gnome2/nautilus-scripts or any sourced directory, e.g. $HOME/bin
#
#  Notes: users of this script must be in a group with permission to use mount.cifs.
#   -e.g. run visudo to edit /etc/sudoers:
#     # Find location of mount command
#     which mount && which mount.cifs
#
#     # Edit sudoers file
#     sudo visudo
#
#     # Add this line (based on location found above from 'which' commands)
#     %sambashare ALL=NOPASSWD:NOEXEC:/usr/sbin/mount.cifs, /usr/sbin/mount
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
# Copyright (c) 2010-2015 Baileysoft Solutions
#-----------------------------------------------------------------------

#
# Metadata
#
scriptname=${0##*/}
description="Mounts remote CIFS file shares."
usage="$scriptname"
optionusage="-l:\t New log file (existing log is clobbered)\n  -h:\t Print help (this screen)\n  -v:\t Print version info\n"
optionexamples=" ./"$scriptname" -l \n\n" 
date_of_creation="2015-08-13"
version=0.8.0
author="Neal T. Bailey"
copyright="Baileysoft Solutions"

#
# Default user defined values
#
# CUSER: Logged in linux user
# SMBUSER: Windows user account name
# SMBPASSWD: Windows user account passwd
# SMBDOM: Windows domain
# SMBOPTS: mount.cifs options
# SMBUSROPTS: mount.cifs user specific options
# BMOUNT: Mount base dir
# CREDSFILE: Credentials file
# CONFIG: File with list of SMB paths (e.g. //server/share). 1 per line.
# LOGFILE: The log file path.
# SUDO_GROUP: The group with NOPASSWD permissions to mount samba shares in /etc/sudoers
#
CUSER="$(whoami)"
SMBUSER="$CUSER"
SMBPASSWD=
SMBDOM="BAILEYSOFT"
SMBOPTS="rw,file_mode=0777,dir_mode=0777,domain=$SMBDOM,uid=$CUSER,vers=2.0"
SMBUSROPTS="username=$SMBUSER"
BMOUNT="$HOME/Network"
CREDSFILE="$HOME/etc/.cifspw"
CONFIG="$HOME/etc/map-shares.conf"
LOGFILE="/tmp/$scriptname.log"
SUDO_GROUP="sambashare"

# Global application variables
TEST_RUN="false"
APPEND_LOG="true"
STDOUT_LOG_ONLY="false"
CONVERT_ONLY="false"
PID_FILE="/tmp/$scriptname.running"
BAK_IFS="$IFS" # Backup Internal Field Separator (IFS) 
ZEN_COLUMNS=( ) # The zenity columns
SELECTED_ITEMS= # The zenity seleted items
LST_SHARES=( )  # The array of shares from config file

# Function definitions

#@ DESCRIPTION: Reads the share definition file into array.
#@ PARAM $1: The share definitions file.
#@ REMARKS: Populates the $LST_SHARES array. 
#@ USAGE: fill_shares_array "$CONFIG"
function fill_shares_array()
{
  local i=0
  while read -r line # Read a line
  do
    if [[ $(echo "$line" | grep -Ec "^#") -gt 0 ]]; then
      continue
    fi
    
    # Replace backslashes with forward slashes
    line=$(echo "$line" | sed 's|\\|\/|g')
    
    LST_SHARES[i]="$line" # Append array
    i=$(($i + 1))        # increment counter
    
    # ToDo: Regex to verify path is a UNC
  done < $1
}

#@ DESCRIPTION: Fill array to use to create dialog columns
function fill_dialog_columns() 
{  
  local array_len="${#LST_SHARES[@]}"

  for (( i=0; i < $array_len; ++i ))
  do
    local share="${LST_SHARES[$i]}"

    # Do not display mounted shares
    if [ $(mount | grep -ic "$share") -ne "1" ]; then   

      # Used to remove first 2 characters '//'
      local mnt=$(printf "$share" | sed 's/..\(.*\)/\1/')
      ZEN_COLUMNS+=( False "$share" "$BMOUNT/$mnt" )
    fi
  done
}

#@ DESCRIPTION: Display the share selection dialog form
function show_dialog() 
{
  fill_dialog_columns 

  SELECTED_ITEMS=$(zenity --list --checklist --width="500" --height="300" \
    --title="Baileysoft Solutions - Samba Share Manager"  \
    --text="Select the samba share(s) to mount" \
    --column="Mark" --column="Remote Share" \
    --column="Mount Point" "${ZEN_COLUMNS[@]}" \
    --print-column="ALL" --separator="|")

  if [ $? -eq 0 ]; then
    # Prompt for windows password
    if [ ! -e "$CREDSFILE" ]; then #ToDo: check for password already set
      zenity --height="200" --warning --text="`printf "You will be prompted for password.\n This password will appear in the log file.\n\nPlease consider creating a credentials file:    \n$CREDSFILE"`"
      SMBPASSWD=$(zenity --entry --title="Security" --hide-text="" --text="Enter password for $SMBUSER")
    fi
  else
    log "Error: Mount operation cancelled by user."
    exit 1
  fi
}

#@ DESCRIPTION: Mounts the selected windows shares
function do_mount() 
{
  IFS="|" # Column seperator for zenity
  local mount=""
  local share=""

  (for item in $SELECTED_ITEMS # toDo: add some kind of 'on error resume next' handling
  do
    # Figure out if $selected is share or mount point
    if [ $(echo "$item" | grep -ce '//') -gt "0" ]; then
      share="$item"
    else
      mount="$item"
    fi
	
  # Make sure we have the mount point and the share
  if [ -n "$share" ] && [ -n "$mount" ]; then
    #log "[mount] $mount"
    if [ ! -d "$mount" ]; then
      eval_exec "mkdir -p \"$mount\" 2>&1 | tee -a \"$LOGFILE\""
    fi
		
    # Don't try to mount a share that is already mounted
    if [ $(mount | grep -c "$mount") -ne "1" ]; then
      # For this to work the user MUST be in /etc/sudoers with the NOPASSWD option
      log "Attempting mount action -> $mount"
      #log "WARN: User must be in /etc/sudoers with NOPASSWD option for mount.cifs to work!"
      
      if [ -e "$CREDSFILE" ]; then
        eval_exec "sudo mount.cifs \"$share\" \"$mount\" -o \"$SMBOPTS\",credentials=\"$CREDSFILE\" 2>&1 | tee -a \"$LOGFILE\""
      else
        if [ -z "$SMBPASSWD" ]; then
          log "Error: Credentials are unknown. Cannot mount shares without credentials"
        else
          eval_exec "sudo mount.cifs \"$share\" \"$mount\" -o $SMBOPTS,$SMBUSROPTS,password='$SMBPASSWD' 2>&1 | tee -a \"$LOGFILE\""
        fi
      fi
    fi
  fi
  done)| zenity --progress --auto-close --title="Peforming Tasks"  --text="Mounting: "$mount" ..."  --progress --pulsate
  IFS=" "
  
  return $exit_code
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

#@ DESCRIPTION: Log message.
#@ PARAM $1: The message to log.
#@ REMARKS: Sends message to stdout with -o flag
function log()     
{ 
  if [[ $STDOUT_LOG_ONLY == "false" ]] ; then
    printf "%s\n" "$1"
  fi  
  echo $(date +%Y-%m-%dT%H:%M) "$1" >> "$LOGFILE"
}

#@ DESCRIPTION: Unlocks the process
#@ REMARKS: Handles the SIGTERM EXIT broadcast
function on_exit() 
{ 
  if [[ -f "$PID_FILE" ]] ; then
    get_seconds_since_modification "$PID_FILE" ; local seconds=$?
    printf 'Process executed for:\t%dh:%dm:%ds\n' $(($seconds/3600)) $(($seconds%3600/60)) $(($seconds%60))
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
  printf "%s (v%s)\n" "$scriptname" "$version"
  printf "by %s, %d\n" "$author"  "${date_of_creation%%-*}"
  printf "%s\n" "$copyright"
}

# End Function definitions

# Ensure user is not root
if [ "$CUSER" == "root" ]; then
  zenity --warning --title="Baileysoft Network Manager" \
  --text="This script cannot be run as root." --width="350"
  echo "This script cannot be run as root."
  exit
fi

# Ensure the script is not currently in a RUNNING state.
if [[ -f "$PID_FILE" ]] ; then
  STDOUT_LOG_ONLY="false"
  log "A previous instance of this process is currently executing."
  exit 101
fi

# Command-line arguments processing
optstring=lhv
while getopts $optstring opt
do
  case $opt in
  l) APPEND_LOG="false" ;;
  h) usage; exit ;;
  v) version; exit ;;
  *) usage; exit ;;
  esac
done
shift "$(( $OPTIND - 1 ))"

if [[ "$APPEND_LOG" == "false" ]]; then
  # Zero out log file
  cat /dev/null > "$LOGFILE"
fi

# Start the application trace log
log "Started executing process: $scriptname"
log "logfile is: \"$LOGFILE\""

#
# Pre-requisite sanity check. These segments ensure nothing unexpected will prevent
# the process from completing at runtime due to unknown or invalid machine configuration. 
#

# Ensure zenity package is installed on server (and we know where it is)
if [ $(which zenity | grep -c "zenity") -eq 0 ]; then
  STDOUT_LOG_ONLY="false"
  log "Error: zenity package is not installed on this machine (not found)!" 
  exit 104
fi 

# Ensure cifs-utils package is installed on server (and we know where it is)
if [ $(which mount.cifs | grep -c "mount") -eq 0 ]; then
  STDOUT_LOG_ONLY="false"
  log "Error: mount.cifs command is not installed on this machine (not found)!"
  log "Error: mount.cifs is typically found in the cifs-utils package."
  exit 104
fi

# Ensure share definitions file exists
if [ ! -f "$CONFIG" ]; then
  STDOUT_LOG_ONLY="false"
  log "Error: Shares definitions file does not exist: \"$CONFIG\""
  exit 105
fi

# Ensure group exists on the server
if [ $(cat /etc/group | grep -ic "$SUDO_GROUP") -eq 0 ]; then
  STDOUT_LOG_ONLY="false"
  log "Error: Samba users group \"$SUDO_GROUP\" does not exist on this server!" 
  exit 103
fi

# Ensure user is in the required group
if [ $(groups $SMBUSER | grep -ic "$SUDO_GROUP") -eq 0 ]; then
  STDOUT_LOG_ONLY="false"
  log "Error: User is not in the group: \"$SUDO_GROUP\"!" 
  exit 104
fi

# Try to ensure the user has the NOPASSWD permission in /etc/sudoers
sudo -n mount.cifs -V &> /dev/null
if [[ $? -gt 0 ]]; then
  STDOUT_LOG_ONLY="false"
  log "The user does not appear to have the NOPASSWD priviledge in /etc/sudoers."
  exit 105
fi

# Warn user is no credentials file is found. 
if [ ! -f "$CREDSFILE" ]; then
  log "WARN: CREDENTIALS FILE WAS NOT FOUND: \"$CREDSFILE\"!"
  log "WARN: YOU WILL BE PROMPTED FOR A PASSWORD"
  log "WARN: THIS PASSWORD WILL APPEAR IN PLAIN-TEXT IN THE LOGFILE!!"
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
  log "WARN: THIS IS A TEST RUN! EXEC COMMANDS WILL NOT BE ISSUED TO THE SERVER! DEBUG MODE!"
fi

# Read remote share definitions
fill_shares_array "$CONFIG"

# Render selection dialog 
show_dialog

# Mount shares based on user selection
do_mount

log "Operation completed. Refer to the log-file to troubleshoot errors."

# Cleanup
on_exit
