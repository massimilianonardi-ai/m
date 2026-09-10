# current_args="$(quote "$@")"
# set -- foo bar baz boo
# eval "set -- $current_args"

quote()
{
  (
    while [ "$#" -gt 0 ]
    do
      _quote_arg="$1"

      printf "'" || exit 1

      while [ "$_quote_arg" != "${_quote_arg#*"'"}" ]
      do
        _quote_part="${_quote_arg%%"'"*}"

        printf "%s'\\\\''" "$_quote_part" || exit 2

        _quote_arg="${_quote_arg#*"'"}"
      done

      printf "%s'" "$_quote_arg" || exit 3

      shift

      if [ "$#" -gt 0 ]
      then
        printf " " || exit 4
      fi
    done
  )
}
