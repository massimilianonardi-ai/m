# current_args="$(quote "$@")"
# set -- foo bar baz boo
# eval "set -- $current_args"

quote()
{
  (
    while [ "$#" -gt 0 ]
    do
      _arg="$1"

      printf "'" || exit 1

      while [ "$_arg" != "${_arg#*"'"}" ]
      do
        _part="${_arg%%"'"*}"

        printf "%s'\\\\''" "$_part" || exit 2

        _arg="${_arg#*"'"}"
      done

      printf "%s'" "$_arg" || exit 3

      shift

      if [ "$#" -gt 0 ]
      then
        printf " " || exit 4
      fi
    done
  )
}
