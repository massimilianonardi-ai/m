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

env_eval_no_exec()
(
  if [ "$#" -ne "1" ]
  then
    return 1
  fi

  env_eval_word="$(
    printf '%sx' "$1" | LC_ALL=C awk '
      BEGIN {
        sq = sprintf("%c", 39)
      }

      NR == 1 {
        text = $0
        next
      }

      {
        text = text "\n" $0
      }

      END {
        # Remove the sentinel appended by printf.
        text = substr(text, 1, length(text) - 1)

        # Build one shell word. Literal text is always single-quoted;
        # only validated variable names become parameter expansions.
        out = sq

        for (i = 1; i <= length(text); i++) {
          c = substr(text, i, 1)

          # Heredoc-like backslash handling.
          if (c == "\\") {
            n = substr(text, i + 1, 1)

            if (n == "$" || n == "\\" || n == "`") {
              append_literal(n)
              i++
              continue
            }

            if (n == "\n") {
              i++
              continue
            }

            append_literal(c)
            continue
          }

          if (c != "$") {
            append_literal(c)
            continue
          }

          n = substr(text, i + 1, 1)

          # ${NAME}
          if (n == "{") {
            rest = substr(text, i + 2)
            endpos = index(rest, "}")

            if (endpos == 0)
              exit 2

            name = substr(rest, 1, endpos - 1)

            if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/)
              exit 2

            out = out sq "\"${" name "}\"" sq
            i += endpos + 1
            continue
          }

          # $NAME
          if (n ~ /[A-Za-z_]/) {
            name = n
            j = i + 2

            while (j <= length(text)) {
              n = substr(text, j, 1)

              if (n !~ /[A-Za-z0-9_]/)
                break

              name = name n
              j++
            }

            out = out sq "\"${" name "}\"" sq
            i = j - 1
            continue
          }

          # Any other $ construct is literal.
          append_literal(c)
        }

        print out sq
      }

      function append_literal(c) {
        if (c == sq)
          out = out sq "\\" sq sq
        else
          out = out c
      }
    '
  )" || return 1

  eval "printf '%s' $env_eval_word"
)

#-------------------------------------------------------------------------------

# TODO non colliding heredoc delimiter. printf instead of echo. safe against \ as first/last character
# env_eval $template_var $@
# copies content of $template_var and echoes to stdout after substituting positional parameters with remaining args $@
# removes trailing newlines
env_eval()
{
  [ "$#" -ge "1" ] || return 1

  eval printf '%s' '"$(shift; cat << EOF_972364927347827384671231827319283918729387981237
'"${1}"'

EOF_972364927347827384671231827319283918729387981237
)"'
}

env_eval2()
{
  [ "$#" -ge "1" ] || return 1

  eval 'shift; cat << EOF_972364927347827384671231827319283918729387981237
'"${1}"'

EOF_972364927347827384671231827319283918729387981237
'
}

# env_eval3()
# {
#   [ "$#" -ge "1" ] || return 1
#
#   (
#     _eof="EOF_$(command -p -- date '+%Y%m%d_%H%M%S' 2>/dev/null)"
#   eval 'shift; cat << '"$_eof"'
# '"${1}"'
#
# '"$_eof"
#   )
# }

#-------------------------------------------------------------------------------

# env_eval_set destination_var_to_set $template_var $@
# copies content of $template_var into destination_var_to_set after substituting positional parameters with remaining args $@
env_eval_set_old()
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

# maybe its best to use a middle function to pass unique EOF and a tmp var inside a subshell (quote?), or maybe...?

# env_eval_expand <var-name> <text-to-expand> <arg1> <arg2> ...
# expands <text-to-expand> with the same rules of an heredoc, interpreting variables, command substitution, etc. arg1, arg2 are passed as positional parameters $1, $2, etc.
# returns cat error code, handles trailing \+EOF, keeps trailing newlines
# <var-name> is not proteced against error
env_eval_expand()
{
  [ "$#" -ge "2" ] || return 1
  case "$1" in ""|[0123456789]*|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 2;; esac

  eval "${1}"='$(shift 2; cat << EOF_972364927347827384671231827319283918729387981237
'"${2}"'
x
EOF_972364927347827384671231827319283918729387981237
)' '&&' "${1}=\${${1}%x}" '&&' "${1}=\${${1}%
}"
}

# depends on quote
env_eval_expand2()
{
  [ "$#" -ge "2" ] || return 1
  case "$1" in ""|[0123456789]*|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 2;; esac

  eval "$(
    if _env_eval_value="$(
      eval 'shift 2; cat << EOF_972364927347827384671231827319283918729387981237
'"${2}"'
x
EOF_972364927347827384671231827319283918729387981237
'
    )"
    then
      :
    else
      printf 'return %s' "$?"
      exit 0
    fi

    _env_eval_value=${_env_eval_value%x}
    _env_eval_value=${_env_eval_value%"
"}

    if _env_eval_quoted="$(quote "$_env_eval_value")"
    then
      :
    else
      printf 'return %s' "$?"
      exit 0
    fi

    printf '%s=%s' "$1" "$_env_eval_quoted"
  )"
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
