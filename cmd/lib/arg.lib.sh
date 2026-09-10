#!/bin/sh

#------------------------------------------------------------------------------

quote()
{
  if [ -z "$1" ]
  then
    printf "''"
  fi

  # printf %s\\n "$1" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"
  printf "%s" "$1" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"
}

# current_args="$(saveargs "$@")"
# set -- foo bar baz boo
# eval "set -- $current_args"

saveargs()
{
  (
    while [ "$#" -gt 0 ]
    do
      _saveargs_arg="$1"

      printf "'" || exit

      while [ "$_saveargs_arg" != "${_saveargs_arg#*"'"}" ]
      do
        _saveargs_part="${_saveargs_arg%%"'"*}"

        printf "%s'\\\\''" "$_saveargs_part" || exit

        _saveargs_arg="${_saveargs_arg#*"'"}"
      done

      printf "%s'" "$_saveargs_arg" || exit

      shift

      if [ "$#" -gt 0 ]
      then
        printf " " || exit
      fi
    done
  )
}

#-------------------------------------------------------------------------------
