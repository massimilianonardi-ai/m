# current_args="$(saveargs "$@")"
# set -- foo bar baz boo
# eval "set -- $current_args"

# TODO evaluate the decision to use only one function with name "quote" that uses the current "saveargs", because: quote "$1" == saveargs "$1"

quote()
{
  if [ "$#" -ne 1 ]
  then
    return 1
  fi

  (
    _quote_arg="$1"

    printf "%s" "'" || exit 1

    while [ "$_quote_arg" != "${_quote_arg#*"'"}" ]
    do
      _quote_part="${_quote_arg%%"'"*}"

      printf "%s%s" "$_quote_part" "'\\''" || exit 1

      _quote_arg="${_quote_arg#*"'"}"
    done

    printf "%s%s" "$_quote_arg" "'" || exit 1
  )
}

quoteargs()
{
  while [ "$#" -gt 0 ]
  do
    quote "$1" || return 1

    shift

    if [ "$#" -gt 0 ]
    then
      printf "%s" " " || return 1
    fi
  done
}

quotearg()
{
  [ "$#" -eq 1 ] || return 1

  saveargs "$1"
}

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
