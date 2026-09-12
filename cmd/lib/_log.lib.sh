#!/bin/sh

# log $level $msg $args (eg: log fatal exit_message var1 "i am not a var" var2)
# if msg is a name of an existing var it is substituted with its contents, same for args, then msg is evaluated with $args as $1, $2, etc.
# each arg that point to an existing var is explicitly appended at the end with its value

#-------------------------------------------------------------------------------

# delegates to proper lib function
log()
{
  log_"$@"
}

#-------------------------------------------------------------------------------

# base printing function that redirects to stderr
log_echo()
{
  printf %s\\n "$*" 1>&2
}

#-------------------------------------------------------------------------------

log_line()
{
  log_echo "$(date +"[%Y-%m-%d %H:%M:%S]") [${PPID}>${$}] [$LOG_PROC_NAME] [$LOG_MESSAGE_PRI] [$LOG_MESSAGE_LEVEL]" "$@"
}

#-------------------------------------------------------------------------------

log_fatal()
{
  $LOG_LINE_FUNC "1" "fatal" "$@"
}

log_error()
{
  $LOG_LINE_FUNC "2" "error" "$@"
}

log_warn()
{
  $LOG_LINE_FUNC "3" "warn " "$@"
}

log_info()
{
  $LOG_LINE_FUNC "4" "info " "$@"
}

log_debug()
{
  $LOG_LINE_FUNC "5" "debug" "$@"
}

log_trace()
{
  $LOG_LINE_FUNC "6" "trace" "$@"
}

#-------------------------------------------------------------------------------

# filters out messages below current log level and delegates to $LOG_LINE_FUNC_FILTER_LEVEL
log_line_func_filter_level()
{
  if [ $(($1)) -le $(($LOG_LEVEL_PRI)) ]
  then
    (
      LOG_MESSAGE_PRI="$1"
      shift
      LOG_MESSAGE_LEVEL="$1"
      shift
      $LOG_LINE_FUNC_FILTER_LEVEL "$@"
    )
  fi
}

#-------------------------------------------------------------------------------

# if message is "--" then message is retrieved from a variable and delegated to $LOG_LINE_FUNC_FORMATTER_LANG
log_line_func_formatter_lang()
{
  # if [ "$1" = "--" ]
  if (eval echo "\${$1}" 1>/dev/null 2>/dev/null) && (eval "[ -n \"\${$1+true}\" ]")
  then
    # shift
    eval "LOG_MESSAGE_TRANSLATION=\"\$$1\""
    shift
    set -- "$LOG_MESSAGE_TRANSLATION" "$@"
  fi

  $LOG_LINE_FUNC_FORMATTER_LANG "$@"
}

#-------------------------------------------------------------------------------

# $1 is evaluated passing subsequent args ot it and delegated to $LOG_LINE_FUNC_FORMATTER_VARS
log_line_func_formatter_vars()
{
  LOG_MESSAGE_VAR_MESSAGE="$1"
  shift

  for LOG_MESSAGE_VAR_k in "$@"
  do
    shift
    if (eval echo "\${$LOG_MESSAGE_VAR_k}" 1>/dev/null 2>/dev/null) && (eval "[ -n \"\${$LOG_MESSAGE_VAR_k+true}\" ]") && [ "$LOG_MESSAGE_VAR_k" != "@" ]
    then
echo "$LOG_MESSAGE_VAR_k is a valued var" 1>&2
      LOG_MESSAGE_VAR_VARS="$LOG_MESSAGE_VAR_VARS [$LOG_MESSAGE_VAR_k=\"\${$LOG_MESSAGE_VAR_k}\"]"
      set -- "$@" "$(eval echo "\$$LOG_MESSAGE_VAR_k")"
    elif [ "$LOG_MESSAGE_VAR_k" = "@" ]
    then
echo "$LOG_MESSAGE_VAR_k is @" 1>&2
      true
    else
echo "$LOG_MESSAGE_VAR_k is a fixed param" 1>&2
      # LOG_MESSAGE_VAR_MESSAGE="$LOG_MESSAGE_VAR_MESSAGE $LOG_MESSAGE_VAR_k"
      set -- "$@" "$LOG_MESSAGE_VAR_k"
    fi
    # echo "args: $@" 1>&2
  done
    echo "args: $@" 1>&2

  eval "LOG_MESSAGE_VAR_MESSAGE=\"$LOG_MESSAGE_VAR_MESSAGE $LOG_MESSAGE_VAR_VARS\""

  # $LOG_LINE_FUNC_FORMATTER_VARS "$LOG_MESSAGE_VAR_MESSAGE" "$@"
  $LOG_LINE_FUNC_FORMATTER_VARS "$LOG_MESSAGE_VAR_MESSAGE"
}

# $1 is evaluated passing subsequent args ot it and delegated to $LOG_LINE_FUNC_FORMATTER_VARS
log_line_func_formatter_vars()
{
  LOG_MESSAGE_VAR_MESSAGE="$1"
  shift

  while [ "$#" -gt "0" ] && [ "$1" != "--" ]
  do
    LOG_MESSAGE_VAR_MESSAGE="$LOG_MESSAGE_VAR_MESSAGE $1"
    shift
  done

  if [ "$1" = "--" ]
  then
    shift

    for LOG_MESSAGE_VAR_k in "$@"
    do
      shift
      if (eval echo "\${$LOG_MESSAGE_VAR_k}" 1>/dev/null 2>/dev/null) && (eval "[ -n \"\${$LOG_MESSAGE_VAR_k+true}\" ]") && [ "$LOG_MESSAGE_VAR_k" != "@" ]
      then
echo "$LOG_MESSAGE_VAR_k is a valued var" 1>&2
        LOG_MESSAGE_VAR_VARS="$LOG_MESSAGE_VAR_VARS [$LOG_MESSAGE_VAR_k=\"\${$LOG_MESSAGE_VAR_k}\"]"
        set -- "$@" "$(eval echo "\$$LOG_MESSAGE_VAR_k")"
      elif [ "$LOG_MESSAGE_VAR_k" = "@" ]
      then
echo "$LOG_MESSAGE_VAR_k is @" 1>&2
        true
      else
echo "$LOG_MESSAGE_VAR_k is a fixed param" 1>&2
        # LOG_MESSAGE_VAR_MESSAGE="$LOG_MESSAGE_VAR_MESSAGE $LOG_MESSAGE_VAR_k"
        set -- "$@" "$LOG_MESSAGE_VAR_k"
      fi
      # echo "args: $@" 1>&2
    done
echo "args: $@" 1>&2
  fi

# echo  eval "LOG_MESSAGE_VAR_MESSAGE=\"$LOG_MESSAGE_VAR_MESSAGE $LOG_MESSAGE_VAR_VARS\""
  # LOG_MESSAGE_VAR_MESSAGE="$(echo "$LOG_MESSAGE_VAR_MESSAGE") $LOG_MESSAGE_VAR_VARS"
  LOG_MESSAGE_VAR_MESSAGE="$(eval echo "$LOG_MESSAGE_VAR_MESSAGE $LOG_MESSAGE_VAR_VARS")"

  # $LOG_LINE_FUNC_FORMATTER_VARS "$LOG_MESSAGE_VAR_MESSAGE" "$@"
  $LOG_LINE_FUNC_FORMATTER_VARS "$LOG_MESSAGE_VAR_MESSAGE"
}

# $1 is evaluated passing subsequent args ot it and delegated to $LOG_LINE_FUNC_FORMATTER_VARS
log_line_func_formatter_vars()
{
  LOG_MESSAGE_VAR_MESSAGE=""

  while [ "$#" -gt "0" ]
  do
    # @ \* \# ? - !
    if [ "$1" != '@' ] && [ "$1" != '*' ] && [ "$1" != '#' ] && [ "$1" != '?' ] && [ "$1" != '-' ] && [ "$1" != '!' ] && (eval "[ -n \"\${$1+true}\" ]" 1>/dev/null 2>/dev/null)
    then
      LOG_MESSAGE_VAR_VARS="$LOG_MESSAGE_VAR_VARS [$(eval echo "'$1'=\"\${$1}\"")]"
    else
      LOG_MESSAGE_VAR_MESSAGE="$LOG_MESSAGE_VAR_MESSAGE $1"
    fi
    shift
  done

  $LOG_LINE_FUNC_FORMATTER_VARS "$LOG_MESSAGE_VAR_MESSAGE $LOG_MESSAGE_VAR_VARS"
}

#-------------------------------------------------------------------------------

log_level()
{
  if [ -z "$1" ]
  then
    log_fatal "log_level: empty arg"
    return 1
  fi

  export LOG_LEVEL="$1"
  log_level_parse
}

#-------------------------------------------------------------------------------

log_level_parse()
{
  if [ "$LOG_LEVEL" = "off" ] || [ "$LOG_LEVEL" = "none" ]
  then
    LOG_LEVEL_PRI="0"
  elif [ "$LOG_LEVEL" = "fatal" ]
  then
    LOG_LEVEL_PRI="1"
  elif [ "$LOG_LEVEL" = "error" ]
  then
    LOG_LEVEL_PRI="2"
  elif [ "$LOG_LEVEL" = "warn" ]
  then
    LOG_LEVEL_PRI="3"
  elif [ "$LOG_LEVEL" = "info" ]
  then
    LOG_LEVEL_PRI="4"
  elif [ "$LOG_LEVEL" = "debug" ]
  then
    LOG_LEVEL_PRI="5"
  elif [ "$LOG_LEVEL" = "trace" ] || [ "$LOG_LEVEL" = "all" ] || [ "$LOG_LEVEL" = "full" ] || [ "$LOG_LEVEL" = "max" ]
  then
    LOG_LEVEL_PRI="6"
  else
    log_fatal "LOG_LEVEL=$LOG_LEVEL"
    exit 1
  fi

  export LOG_LEVEL_PRI
}

#-------------------------------------------------------------------------------

if [ -z "$LOG_LINE_FUNC" ]
then
  LOG_LINE_FUNC="log_line_func_filter_level"
fi

if [ -z "$LOG_LINE_FUNC_FILTER_LEVEL" ]
then
  LOG_LINE_FUNC_FILTER_LEVEL="log_line_func_formatter_lang"
fi

if [ -z "$LOG_LINE_FUNC_FORMATTER_LANG" ]
then
  LOG_LINE_FUNC_FORMATTER_LANG="log_line_func_formatter_vars"
fi

if [ -z "$LOG_LINE_FUNC_FORMATTER_VARS" ]
then
  LOG_LINE_FUNC_FORMATTER_VARS="log_line"
fi

if [ -z "$LOG_PROC_NAME" ]
then
  LOG_PROC_NAME="$(ps -o "comm=" -p "$$")"
fi

#if [ -z "$LOG_LEVEL" ] && [ -z "$LOG_LEVEL_PRI" ]
if [ -z "$LOG_LEVEL" ]
then
  LOG_LEVEL="info"
fi

log_level_parse
