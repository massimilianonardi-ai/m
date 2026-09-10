#!/bin/sh

. enc.lib.sh

#-------------------------------------------------------------------------------

# ipc_create [base_dir]
# creates a private IPC channel and prints its directory path
ipc_create()
(
  set +x

  [ "$#" -le "1" ] || return 2

  _ipc_base="${1:-${TMPDIR:-/tmp}}"

  case "$_ipc_base" in
    /*) : ;;
    *) return 1 ;;
  esac

  [ -d "$_ipc_base" ] && [ -w "$_ipc_base" ] || return 1

  umask 077
  _ipc_try="0"

  while [ "$_ipc_try" -lt "10" ]
  do
    _ipc_token="$(randh 16)" || return 1

    [ "${#_ipc_token}" -eq "32" ] || return 1

    case "$_ipc_token" in
      *[!0123456789abcdef]*) return 1 ;;
    esac

    _ipc_dir="${_ipc_base%/}/ipc.$$.$_ipc_token"

    if mkdir "$_ipc_dir" 2>/dev/null
    then
      _ipc_fifo="$_ipc_dir/data"

      if ! mkfifo "$_ipc_fifo" 2>/dev/null
      then
        rmdir "$_ipc_dir" 2>/dev/null || :
        return 1
      fi

      chmod 700 "$_ipc_dir" ||
      {
        rm -f "$_ipc_fifo"
        rmdir "$_ipc_dir" 2>/dev/null || :
        return 1
      }

      chmod 600 "$_ipc_fifo" ||
      {
        rm -f "$_ipc_fifo"
        rmdir "$_ipc_dir" 2>/dev/null || :
        return 1
      }

      printf '%s\n' "$_ipc_dir"
      return 0
    fi

    _ipc_try="$((_ipc_try + 1))"
  done

  return 1
)

#-------------------------------------------------------------------------------

# ipc_write channel [data]
# with data writes that shell string exactly; without data copies stdin
ipc_write()
(
  set +x

  [ "$#" -eq "1" ] || [ "$#" -eq "2" ] || return 2

  _ipc_dir="$1"
  _ipc_fifo="$_ipc_dir/data"

  [ -d "$_ipc_dir" ] && [ -p "$_ipc_fifo" ] || return 1

  if [ "$#" -eq "2" ]
  then
    printf '%s' "$2" > "$_ipc_fifo"
  else
    cat > "$_ipc_fifo"
  fi
)

#-------------------------------------------------------------------------------

# ipc_read channel
# copies one writer session from the channel to stdout
ipc_read()
(
  set +x

  [ "$#" -eq "1" ] || return 2

  _ipc_dir="$1"
  _ipc_fifo="$_ipc_dir/data"

  [ -d "$_ipc_dir" ] && [ -p "$_ipc_fifo" ] || return 1

  cat < "$_ipc_fifo"
)

#-------------------------------------------------------------------------------

# ipc_sync pid
# waits for an asynchronous IPC operation and returns its status
ipc_sync()
{
  [ "$#" -eq "1" ] || return 2

  wait "$1"
}

#-------------------------------------------------------------------------------

# ipc_cancel pid
# stops an asynchronous IPC operation and reaps it
ipc_cancel()
{
  [ "$#" -eq "1" ] || return 2

  kill "$1" 2>/dev/null || :
  wait "$1" 2>/dev/null || :
}

#-------------------------------------------------------------------------------

# ipc_destroy channel
# removes only the channel FIFO and its now-empty private directory
ipc_destroy()
(
  set +x

  [ "$#" -eq "1" ] || return 2

  _ipc_dir="$1"

  case "$_ipc_dir" in
    /*) : ;;
    *) return 1 ;;
  esac

  if [ -p "$_ipc_dir/data" ]
  then
    rm -f "$_ipc_dir/data" || return 1
  fi

  if [ -d "$_ipc_dir" ]
  then
    rmdir "$_ipc_dir" || return 1
  fi
)

#-------------------------------------------------------------------------------
