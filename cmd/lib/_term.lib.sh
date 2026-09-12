#!/bin/sh

#-------------------------------------------------------------------------------

term_render()
{
  # "$@"
  "$@" >/dev/tty
}

term_output()
{
  "$@"
  # "$@" >/dev/stdout
}

term_error()
{
  # "$@"
  # "$@" >/dev/stderr
  "$@" 1>&2
}

#-------------------------------------------------------------------------------

term_init()
{
  if [ ! -t 0 ]
  then
    # term_error echo "no tty"
    exit 1
  fi

  term_screen_init
  trap "term_screen_reset; exit 2" INT QUIT TERM HUP PIPE ABRT TSTP
  term_screen_size_update
}

term_exit()
{
  term_screen_reset

  if [ -z "$1" ]
  then
    exit 1
  else
    exit "$1"
  fi
}

term_screen_init()
{
  saved_tty_settings=$(stty -g)
  stty -echo

  term_render tput sc
  term_render tput smcup
  term_render tput clear
}

term_screen_reset()
{
  term_render tput clear
  term_render tput rmcup
  term_render tput rc

  stty "$saved_tty_settings"
}

term_screen_size_update()
{
  # fix fo initial wrong values of size from tput
  term_render tput clear
  i=0
  # while [ "$i" -lt "999" ]
  while [ "$i" -lt "99" ]
  do
    export TERM_ROWS="$(tput lines)"
    export TERM_COLS="$(tput cols)"
    # term_render printf "                                                 "
    i="$(($i + 1))"
  done
  term_render tput clear

  # get terminal size
  export TERM_ROWS="$(tput lines)"
  export TERM_COLS="$(tput cols)"
}

#-------------------------------------------------------------------------------

term_region_init()
{
  if [ -z "$TERM_ROWS" ] || [ -z "$TERM_COLS" ]
  then
    term_screen_init
    term_screen_size_update
    term_screen_reset
  fi

  if [ -z "$term_ROW0" ]
  then
    export term_ROW0="0"
  fi

  if [ -z "$term_COL0" ]
  then
    export term_COL0="0"
  fi

  if [ -z "$term_ROWS" ]
  then
    export term_ROWS="$TERM_ROWS"
  fi

  if [ -z "$term_COLS" ]
  then
    export term_COLS="$TERM_COLS"
  fi

  if [ "$term_ROW0" -lt "0" ]
  then
    term_ROW0="0"
  fi

  if [ "$term_COL0" -lt "0" ]
  then
    term_COL0="0"
  fi

  if [ "$term_ROWS" -lt "0" ]
  then
    term_ROWS="$TERM_ROWS"
  fi

  if [ "$term_COLS" -lt "0" ]
  then
    term_COLS="$TERM_COLS"
  fi

  # limits
  if [ -z "$term_ROWS_MIN" ]
  then
    term_ROWS_MIN="2"
  fi

  if [ -z "$term_COLS_MIN" ]
  then
    term_COLS_MIN="2"
  fi

  if [ "$term_ROW0" -gt "$(($TERM_ROWS - 1 - $term_ROWS_MIN))" ]
  then
    term_ROW0="$(($TERM_ROWS - 1 - $term_ROWS_MIN))"
  fi

  if [ "$term_COL0" -gt "$(($TERM_COLS - 1 - $term_COLS_MIN))" ]
  then
    term_COL0="$(($TERM_COLS - 1 - $term_COLS_MIN))"
  fi

  if [ "$(($term_ROW0 + $term_ROWS))" -gt "$TERM_ROWS" ]
  then
    term_ROWS="$(($TERM_ROWS - $term_ROW0))"
  fi

  if [ "$(($term_COL0 + $term_COLS))" -gt "$TERM_COLS" ]
  then
    term_COLS="$(($TERM_COLS - $term_COL0))"
  fi
}

term_region()
{
  if [ "$#" -lt "4" ]
  then
    exit 1
  fi

  export term_ROW0="$1"
  shift
  export term_COL0="$1"
  shift
  export term_ROWS="$1"
  shift
  export term_COLS="$1"
  shift

  term_region_init

  if [ "$#" -gt "0" ]
  then
    "$@"
  fi
}

___term_region_clear()
{
(
  i="$1"
  n="$(($1 + $3))"
  while [ "$i" -lt "$n" ]
  do
    term_render tput cup "$i" "$2"
    term_render printf "%${4}s"
    i="$(($i + 1))"
  done
)
}

term_region_clear()
{
  if [ "$#" -lt "4" ]
  then
    set -- "$term_ROW0" "$term_COL0" "$term_ROWS" "$term_COLS"
  fi

  # set -- "$1" "$2" "$3" "$4" "$1" "$(($1 + $3))"
  # set -- "$1" "$2" "$3" "$(($4 - 1))" "$1" "$(($1 + $3))"
  set -- "$1" "$2" "$3" "$(printf "%${4}s")" "$1" "$(($1 + $3))"
  while [ "$5" -lt "$6" ]
  do
    term_render tput cup "$5" "$2"
    # term_render printf "%${4}s"
    term_render printf "${4}"
    set -- "$1" "$2" "$3" "$4" "$(($5 + 1))" "$6"
  done
}

#-------------------------------------------------------------------------------

term_render_text_at()
{
(
  if [ -z "$1" ]
  then
    return 0
  fi

  # IFS=$(printf '\n+'); IFS=${IFS%?}
  IFS='
'
  i="0"
  for line in $1
  do
    term_render tput cup "$(($2 + $i))" "$3"
    term_render printf "%s" "$line"
    i="$(($i + 1))"
  done
)
}

term_get_cursor_pos()
{
(
  if [ -z "$1" ]
  then
    if [ -z "$2" ]
    then
      set -- "row" "col"
    else
      set -- "row" "$2"
    fi
  elif [ -z "$2" ]
  then
    set -- "$1" "col"
  fi

  saved_tty_settings=$(stty -g)

  stty -echo -icanon min 0 time 1
  tput u7
  IFS='[;R' read -r dummy1 $1 $2 dummy2

  stty "$saved_tty_settings"
)
}

term_string_count_lines()
{
  if [ -z "$1" ]
  then
    return 1
  fi

  eval echo "\$(($(printf "${1}" | wc -l) + 1))"
}

term_echo_colors()
{
(
  for f in {0..7}
  do
    for b in {0..7}
    do
      term_render printf "%s" "$(tput setaf $f)$(tput setab $b) $f/$b "
    done
    term_render echo "$(tput sgr 0)"
  done
)
}

#-------------------------------------------------------------------------------
