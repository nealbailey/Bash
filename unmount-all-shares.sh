#!/bin/bash
#: Title: Unmount Windows Shares
#: Author: Neal T. Bailey <nealbailey@hotmail.com>
#: Date: 03/15/2013
#: Purpose: Automatically unmounts all windows shares. Designed for use during logoff.
#
#: Usage: ./unmount-all-shares
#: Install: echo "$HOME/bin/unmount-all-shares" >> $HOME/.bash_logout
#:
#: Version: 1.0
#:
#  Notes: users must have the same username on both the local machine and the samba server. 
#         users of this script must be in a group with permission to use mount.cifs.
# 	    -e.g. /etc/sudoers -->%cdrom ALL=NOPASSWD:NOEXEC:/sbin/mount.cifs

# Metadata
scriptname=${0##*/}
description="Automatically unmounts all windows shares."
usage="$scriptname [-v|-h]"
optionusage="-v:\tPrint version info\n  -h:\tPrint help (this screen)\n"
date_of_creation=03/15/2013
version=1.0
author="Neal T. Bailey"

# Default Values
#REGEX='^//([^ ]+)' # lines that start with '//' up to first empty character
DEBUG=0
LOG="$0.error"
LINE_PREFIX="[$(date +%m/%d/%Y' '%H:%M)]"

# Functions
usage() #@ DESCRIPTION: print usage information
{       #@ USAGE: usage
  printf "%s - %s\n" "$scriptname" "$description"
  printf "Usage: %s\n" "$usage"
  printf "%s  $optionusage"
}

version() #@ DESCRIPTION: print version information
{         #@ USAGE: version
  printf "Script: %s (v%s)\n" "$scriptname" "$version"
  printf "by: %s, %s\n" "$author"  "$date_of_creation"
}

# Find mounted share points
#mshares=( $(mount|grep -e '//' | cut -d ' ' -f3) )
mshares=( $(mount|grep -Eo '^//([^ ]+)') ) 

CleanErrLog() {
  # Delete unused error log
  if [ -f "$LOG" ]; then
    lc=$(cat "$LOG" | wc -w)
  
    if [ "$lc" -eq "0" ]; then
      rm "$LOG"
    fi 
  fi
}

UnmountShares() {
  for share in "${mshares[@]}"
  do
	# Figure out whether to use /sbin/umount.cifs or /bin/umount
	test_cifs=$(which umount.cifs 2>/dev/null | grep -c "umount.cifs")
		
	if [ "$test_cifs" -ne "0" ]; then
	  # use cifs
	  sudo umount.cifs "$share" 2>"$LOG"
	else
	  # use umount
	sudo umount "$share" 2>"$LOG"
	fi 
  done
}

optstring=hv
while getopts $optstring opt
do
  case $opt in
    h) usage; exit ;;
    v) version; exit ;;
    *) exit 1 ;;
  esac
done
shift "$(( $OPTIND - 1 ))" 

UnmountShares
CleanErrLog
