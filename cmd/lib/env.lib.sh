#!/bin/sh

#-------------------------------------------------------------------------------

. arg.lib.sh

#-------------------------------------------------------------------------------

exist_function()
{
  type "$1">/dev/null 2>&1
}

#-------------------------------------------------------------------------------

exec_if_exist_function()
{
  exist_function "$1" && "$@"
}

#-------------------------------------------------------------------------------

# env_eval $template_var $@
# copies content of $template_var and echoes to stdout after substituting positional parameters with remaining args $@
env_eval()
{
  if [ -z "$1" ]
  then
    return 1
  fi

  eval echo '$(shift; cat << EOF
'"${1}"'
EOF
)'
}

#-------------------------------------------------------------------------------

# env_eval_set destination_var_to_set $template_var $@
# copies content of $template_var into destination_var_to_set after substituting positional parameters with remaining args $@
env_eval_set()
{
  if [ -z "$1" ] || [ -z "$2" ]
  then
    return 1
  fi

  eval ${1}='$(shift 2; cat << EOF
'"${2}"'
EOF
)'
}

#-------------------------------------------------------------------------------

# TO REMOVE

# env_echo_from_template $template_var $@
# copies content of $template_var and echoes to stdout after substituting positional parameters with remaining args $@
env_echo_from_template()
{
  if [ -z "$1" ]
  then
    return 1
  fi

  eval echo '$(shift; cat << EOF
'"$(eval echo "\$${1}")"'
EOF
)'
}

#-------------------------------------------------------------------------------

# TO REMOVE

# env_set_from_template $destination_var_to_set $template_var $@
# copies content of $template_var into $destination_var_to_set after substituting positional parameters with remaining args $@
env_set_from_template()
{
  if [ -z "$1" ] || [ -z "$2" ]
  then
    return 1
  fi

  eval ${1}='$(shift 2; cat << EOF
'"$(eval echo "\$${2}")"'
EOF
)'
}

#-------------------------------------------------------------------------------

env_list_single_quote()
{
  if [ -z "$*" ]
  then
    set | sed '/='\''/,/'\''$/ {s/='\''.*//p; /.*/d}'
  else
    set | sed '/='\''/,/'\''$/ {s/='\''.*//p; /.*/d}' | grep -e "$@"
  fi
}

#-------------------------------------------------------------------------------

env_list()
{
  if [ "$#" -gt "1" ]
  then
    return 1
  fi

  if [ "$#" -eq "0" ]
  then
    env_list_all
  else
    env_list_all | grep -e "$1"
  fi
}

#-------------------------------------------------------------------------------

# full POSIX compliant list of all environment variables (NB safe against bash returning functions)
env_list_all()
{
  set | LC_ALL=C awk '
    BEGIN {
      sq = sprintf("%c", 39)
      mode = ""
      escaped = 0
      boundary = 1
    }

    {
      if (boundary) {
        p = index($0, "=")

        if (p == 0)
          exit

        print substr($0, 1, p - 1)
      }

      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)

        if (mode == "single") {
          if (c == sq)
            mode = ""

          continue
        }

        if (mode == "dollar-single") {
          if (escaped) {
            escaped = 0
            continue
          }

          if (c == "\\") {
            escaped = 1
            continue
          }

          if (c == sq)
            mode = ""

          continue
        }

        if (mode == "double") {
          if (escaped) {
            escaped = 0
            continue
          }

          if (c == "\\") {
            escaped = 1
            continue
          }

          if (c == "\"")
            mode = ""

          continue
        }

        if (escaped) {
          escaped = 0
          continue
        }

        if (c == "\\") {
          escaped = 1
          continue
        }

        if (c == "\"") {
          mode = "double"
          continue
        }

        if (c == "$" && substr($0, i + 1, 1) == sq) {
          mode = "dollar-single"
          i++
          continue
        }

        if (c == sq)
          mode = "single"
      }

      if (mode == "" && !escaped)
        boundary = 1
      else
        boundary = 0

      escaped = 0
    }
  '
}

#-------------------------------------------------------------------------------

# env_set()
env_return_set()
{
  if [ -z "$*" ]
  then
    return 0
  fi

  if [ "$#" = "1" ]
  then
    set -- $@
  fi

  while [ "$#" -gt "0" ]
  do
    eval quoted="\$(quote \"\$$1\")"
    eval printf "$1=\"$quoted; \""
    shift
  done
}

#-------------------------------------------------------------------------------

# env_cmdscope()
env_return_cmd()
{
  if [ -z "$*" ]
  then
    return 0
  fi

  if [ "$#" = "1" ]
  then
    set -- $@
  fi

  while [ "$#" -gt "0" ]
  do
    eval quoted="\$(quote \"\$$1\")"
    eval printf "$1=\"$quoted \""
    shift
  done
}

#-------------------------------------------------------------------------------

# env_export()
env_return_export()
{
  if [ -z "$*" ]
  then
    return 0
  fi

  if [ "$#" = "1" ]
  then
    set -- $@
  fi

  while [ "$#" -gt "0" ]
  do
    eval quoted="\$(quote \"\$$1\")"
    eval echo "export $1=\"$quoted; \""
    shift
  done
}

#-------------------------------------------------------------------------------

env_return_code()
{
  if [ -z "$*" ]
  then
    return 0
  fi

  if [ "$#" = "1" ]
  then
    set -- $@
  fi

  while [ "$#" -gt "0" ]
  do
    eval quoted="\$(quote \"\$$1\")"
    eval echo "$1=\"$quoted; \""
    shift
  done
}

#-------------------------------------------------------------------------------

env_return()
{
(
  if [ -n "$1" ]
  then
    ENV_RETURN="$1"
    shift
  fi

  if [ -n "$*" ]
  then
    ENV_LIST="$@"
  fi

  if [ -z "$ENV_RETURN" ]
  then
    return 1
  elif [ -z "$ENV_LIST" ]
  then
    # return 0
    ENV_LIST="$(env_list)"
  fi

  if [ "$ENV_RETURN" = "export" ]
  then
    env_return_export "$ENV_LIST"
  elif [ "$ENV_RETURN" = "code" ]
  then
    env_return_code "$ENV_LIST"
  elif [ "$ENV_RETURN" = "cmd" ]
  then
    env_return_cmd "$ENV_LIST"
  elif [ "$ENV_RETURN" = "set" ]
  then
    env_return_set "$ENV_LIST"
  fi
)
}

#-------------------------------------------------------------------------------

env_import()
{
  if [ "$#" -lt "1" ]
  then
    return 1
  fi

  eval "$1"
  shift

  ENV_IMPORT="true" "$@"
}

#-------------------------------------------------------------------------------

env_export()
{
  if [ "$#" -lt "1" ]
  then
    return 1
  fi

  set -- "$1" $(shift && ENV_RETURN="${ENV_RETURN:-"export"}" "$@")
  eval $1=\"$(shift && echo "$@")\"
}

#-------------------------------------------------------------------------------

env_read()
{
  set -- "$(set -- $1 && echo "$#")" "$1" "$(shift && "$@")"
  while [ "$1" -gt "0" ]
  do
# echo "arg1='$1'"; echo "arg2='$2'"; echo "arg3='$3'"; read x
    eval "$(shift && set -- $1 && echo "$1")=\"$(shift 2 && eval set -- $1 && echo "$1")\""
    set -- "$(set -- $2 && shift && echo "$#")" "$(set -- $2 && shift && echo "$@")" "$(eval set -- $3 && [ "$#" -gt "0" ] && shift && quote "$@")"
  done
}

#-------------------------------------------------------------------------------

env_read_state()
{
  env_read "$2" echo "$(eval "$1" && set -- $2 && \
    for k in "$@"
    do
      eval quote \"\$$k\"
      printf " "
    done
  )"
}

#-------------------------------------------------------------------------------

# caller functions to be eventually defined:
# env_init "$@": is the only function that accepts command line arguments and initilizes all environment variables
# main: no command line arguments are directly available, must use variables initialized previously
# env_list_get: returns the dynamic list of variables to be exported
# env_result: called by a trap on exit, must echo on stdin the final result to be returned to caller (any other output from other functions to stdin must be forbidden)
env_main()
{
  trap 'ENV_LIST="$(exec_if_exist_function env_list_get)"; env_return || exec_if_exist_function env_result' EXIT

  [ -n "$ENV_IMPORT" ] || exec_if_exist_function env_init "$@" > /dev/null

  exec_if_exist_function main > /dev/null
}

#-------------------------------------------------------------------------------
