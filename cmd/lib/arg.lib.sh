# current_args="$(quote "$@")"
# set -- foo bar baz boo
# eval "set -- $current_args"

quote()
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
