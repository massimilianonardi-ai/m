#!/bin/sh

realpaths()
{
  # resolve caller dir
  CALL_DIR="$(cd -L -- "${0%/*}" && pwd -L)"

  # resolve caller symlink
  if [ -L "$0" ]
  then
    THIS_PATH="$(ls -ld -- "$0")"
    THIS_PATH="${THIS_PATH#*" $0 -> "}"
  else
    # relative path or absolute depending on call that launched this file
    THIS_PATH="$0"
  fi

  # actual called file and absolute dir from resolved path
  THIS_FILE="${THIS_PATH##*/}"
  THIS_DIR="$(cd -P -- "${THIS_PATH%/*}" && pwd -P)"

  # set path
  PATH="$CALL_DIR:$THIS_DIR:$PATH"
}
