#!/bin/sh

wait_continue()
{
  echo ""
  echo "--------------------------------------------------------------------------------"
  echo "press ENTER to continue"
  read -r EXIT_VAR
}

waituser()
{
  # detect if launched from gui or active terminal
  PARENT_PROCESS="$(ps -o 'cmd=' -p $(ps -o 'ppid=' -p $$))"
  #if [ "$PARENT_PROCESS" != "bash" ]
  if [ "${PARENT_PROCESS%sh}" = "$PARENT_PROCESS" ]
  then
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "press ENTER to exit"
    read -r EXIT_VAR
  fi
}
