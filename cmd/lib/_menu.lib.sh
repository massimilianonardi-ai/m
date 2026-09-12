#!/bin/sh

#-------------------------------------------------------------------------------

menuset()
{
  case "$1" in
    "multi")
      shift
      export tui_MENU_MULTISELECTION="true"
    ;;
    "nomulti")
      shift
      export tui_MENU_MULTISELECTION="false"
    ;;
    "id")
      shift
      export tui_MENU_ID="true"
    ;;
    "noid")
      shift
      export tui_MENU_ID="false"
    ;;
    "keys")
      shift

      if [ "$#" -lt "1" ]
      then
        return 1
      fi

      export tui_MENU_CUSTOM_KEYS="$1"
    ;;
    *) exit 1;;
  esac
}

#-------------------------------------------------------------------------------

menucmdshift()
{
  shift "$(($1 + 1))"
  "$@"
}

#-------------------------------------------------------------------------------

menucmd()
{
  case "$1" in
    "multi")
      shift
      tui_MENU_MULTISELECTION="true" "$@"
    ;;
    "nomulti")
      shift
      tui_MENU_MULTISELECTION="false" "$@"
    ;;
    "id")
      shift
      tui_MENU_ID="true" "$@"
    ;;
    "noid")
      shift
      tui_MENU_ID="false" "$@"
    ;;
    "keys")
      shift

      if [ "$#" -lt "1" ]
      then
        return 1
      fi

      tui_MENU_CUSTOM_KEYS="$1" menucmdshift "1" "$@"
    ;;
    *) exit 1;;
  esac
}

#-------------------------------------------------------------------------------
