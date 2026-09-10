# array ARRAY_NAME size
# array ARRAY_NAME size SIZE_VAR_NAME
# array ARRAY_NAME get
# array ARRAY_NAME get INDEX
# array ARRAY_NAME get INDEX ELEM_VAR_NAME
# array ARRAY_NAME put INDEX NEW_VALUE
# array ARRAY_NAME add NEW_VALUE
# array ARRAY_NAME ins INDEX NEW_VALUE
# array ARRAY_NAME rem INDEX
# array ARRAY_NAME set NEW_VALUES...
# array ARRAY_NAME unset
#
# ARRAY_NAME_TYPE, ARRAY_NAME_SIZE and ARRAY_NAME_INDEX variables are
# opaque internal storage. Callers must not modify them directly.
#
# Operations which already need to traverse the complete array validate
# that all declared slots exist before using them. Constant-time operations
# intentionally avoid a full O(n) storage scan.


. arg.lib.sh


_array_name_valid()
{
  case "$1" in
    ""|[0123456789]*|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      return 1
    ;;
  esac

  return 0
}


_array_uint_valid()
{
  case "$1" in
    ""|*[!0123456789]*|0[0123456789]*)
      return 1
    ;;
  esac

  [ "$1" -ge "0" ] 2>/dev/null
}


_array_var_is_set()
{
  _array_name_valid "$1" || return 1

  eval "[ \"\${$1+x}\" = \"x\" ]"
}


_array_var_set()
{
  _array_name_valid "$1" || return 1

  eval "$1=\"\${2}\""
}


_array_var_copy()
{
  _array_name_valid "$1" || return 1
  _array_name_valid "$2" || return 1
  _array_var_is_set "$2" || return 1

  eval "$1=\"\${$2}\""
}


_array_var_print()
{
  _array_name_valid "$1" || return 1
  _array_var_is_set "$1" || return 1

  eval "printf '%s\n' \"\${$1}\""
}


_array_destination_valid()
{
  _array_name_valid "$2" || return 1

  case "$2" in
    "${1}_TYPE"|"${1}_SIZE"|"${1}_"[0123456789]*)
      return 1
    ;;

    *_TYPE)
      set -- "$1" "$2" "${2%_TYPE}"
    ;;

    *_SIZE)
      set -- "$1" "$2" "${2%_SIZE}"
    ;;

    *_*)
      set -- "$1" "$2" "${2%_*}" "${2##*_}"

      _array_uint_valid "$4" || return 0

      set -- "$1" "$2" "$3"
    ;;

    *)
      return 0
    ;;
  esac

  _array_name_valid "$3" || return 0
  _array_var_is_set "${3}_TYPE" || return 0

  eval "[ \"\${${3}_TYPE}\" = \"array\" ]" && return 1

  return 0
}


# Return:
#
#   0  valid array metadata
#   1  array does not exist
#   2  inconsistent array metadata

_array_state()
{
  if ! _array_var_is_set "${1}_TYPE"
  then
    _array_var_is_set "${1}_SIZE" && return 2
    return 1
  fi

  eval "[ \"\${${1}_TYPE}\" = \"array\" ]" || return 2

  _array_var_is_set "${1}_SIZE" || return 2

  eval "set -- \"\$1\" \"\${${1}_SIZE}\""

  _array_uint_valid "$2" || return 2

  return 0
}


# Full O(n) storage validation. Use only when the operation already needs
# to traverse the complete declared array.

_array_slots_valid()
{
  set -- "$1" "$2" "0"

  while [ "$3" -lt "$2" ]
  do
    _array_var_is_set "${1}_${3}" || return 1

    set -- "$1" "$2" "$(($3 + 1))"
  done

  return 0
}


_array_range_unset()
{
  set -- "$1" "$2" "$3"

  while [ "$2" -lt "$3" ]
  do
    unset "${1}_${2}" || return 1

    set -- "$1" "$(($2 + 1))" "$3"
  done

  return 0
}


_array_range_clear()
{
  set -- "$1" "$2" "$3"

  while [ "$2" -lt "$3" ]
  do
    _array_var_is_set "${1}_${2}" && return 1

    set -- "$1" "$(($2 + 1))" "$3"
  done

  return 0
}


_array_get_all()
{
  _array_slots_valid "$1" "$2" || return 1

  # Keep:
  #
  #   $1 ARRAY_NAME
  #   $2 SIZE
  #
  # and append each actual array value to the positional parameters.
  #
  # No command substitution is used to transport array data.

  set -- "$1" "$2"

  while [ "$(($# - 2))" -lt "$2" ]
  do
    eval \
      "set -- \"\$@\" \"\${${1}_$(($# - 2))}\"" ||
      return 1
  done

  shift 2

  quote "$@" || return 1

  printf '\n'
}


_array_reset()
{
  eval "set -- \"\$1\" \"\${${1}_SIZE}\""

  _array_range_unset "$1" "0" "$2" || return 1

  _array_var_set "${1}_SIZE" "0"
}


_array_destroy()
{
  eval "set -- \"\$1\" \"\${${1}_SIZE}\""

  _array_range_unset "$1" "0" "$2" || return 1

  unset "${1}_SIZE" "${1}_TYPE"
}


_array_add()
{
  # Deliberately no full slot validation here: internal storage is opaque
  # and append remains O(1).

  eval \
    "set -- \"\$1\" \"\$2\" \"\${${1}_SIZE}\""

  set -- "$@" "$(($3 + 1))"

  [ "$4" -gt "$3" ] 2>/dev/null || return 1

  _array_var_is_set "${1}_${3}" && return 1

  _array_var_set "${1}_${3}" "$2" || return 1

  if ! _array_var_set "${1}_SIZE" "$4"
  then
    unset "${1}_${3}"
    return 1
  fi

  return 0
}


_array_insert()
{
  eval \
    "set -- \
     \"\$1\" \
     \"\$2\" \
     \"\$3\" \
     \"\${${1}_SIZE}\""

  set -- "$@" "$(($4 + 1))"

  [ "$5" -gt "$4" ] 2>/dev/null || return 1

  _array_slots_valid "$1" "$4" || return 1

  _array_var_is_set "${1}_${4}" && return 1

  # $1 ARRAY_NAME
  # $2 INDEX
  # $3 NEW_VALUE
  # $4 OLD_SIZE
  # $5 NEW_SIZE
  # $6 CURRENT_DESTINATION

  set -- "$@" "$4"

  while [ "$6" -gt "$2" ]
  do
    set -- \
      "$1" \
      "$2" \
      "$3" \
      "$4" \
      "$5" \
      "$6" \
      "$(($6 - 1))"

    _array_var_copy "${1}_${6}" "${1}_${7}" ||
      return 1

    set -- \
      "$1" \
      "$2" \
      "$3" \
      "$4" \
      "$5" \
      "$7"
  done

  _array_var_set "${1}_${2}" "$3" || return 1

  _array_var_set "${1}_SIZE" "$5"
}


_array_remove()
{
  eval \
    "set -- \
     \"\$1\" \
     \"\$2\" \
     \"\${${1}_SIZE}\""

  _array_slots_valid "$1" "$3" || return 1

  # $1 ARRAY_NAME
  # $2 INDEX
  # $3 SIZE
  # $4 CURRENT_DESTINATION

  set -- "$1" "$2" "$3" "$2"

  while [ "$4" -lt "$(($3 - 1))" ]
  do
    set -- \
      "$1" \
      "$2" \
      "$3" \
      "$4" \
      "$(($4 + 1))"

    _array_var_copy "${1}_${4}" "${1}_${5}" ||
      return 1

    set -- \
      "$1" \
      "$2" \
      "$3" \
      "$5"
  done

  set -- \
    "$1" \
    "$2" \
    "$3" \
    "$(($3 - 1))"

  unset "${1}_${4}" || return 1

  _array_var_set "${1}_SIZE" "$4"
}


_array_set()
{
  # Append:
  #
  #   ARRAY_NAME
  #   NEW_SIZE
  #   OLD_SIZE
  #
  # to the original positional parameters.

  eval \
    "set -- \
     \"\$@\" \
     \"\$1\" \
     \"$(($# - 2))\" \
     \"\${${1}_SIZE}\""

  # If the array grows, verify first that every newly required
  # slot is free.

  if eval \
    "[ \"\${$(($# - 1))}\" -gt \"\${$#}\" ]"
  then
    eval \
      "_array_range_clear \
       \"\$1\" \
       \"\${$#}\" \
       \"\${$(($# - 1))}\"" ||
      return 1
  fi

  shift 2

  # Current layout:
  #
  #   VALUE... ARRAY_NAME NEW_SIZE OLD_SIZE

  while [ "$#" -gt "3" ]
  do
    eval \
      "_array_var_set \
       \"\${$(($# - 2))}_\$((\${$(($# - 1))} - ($# - 3)))\" \
       \"\$1\"" ||
      return 1

    shift
  done

  # Remaining layout:
  #
  #   ARRAY_NAME NEW_SIZE OLD_SIZE

  if [ "$2" -lt "$3" ]
  then
    _array_range_unset "$1" "$2" "$3" ||
      return 1
  fi

  _array_var_set "${1}_SIZE" "$2"
}


array()
{
  [ "$#" -ge "1" ] || return 2

  _array_name_valid "$1" || return 2

  if _array_state "$1"
  then
    # Preserve the historical behaviour:
    #
    #   array NAME
    #
    # resets an existing array.

    if [ "$#" -eq "1" ]
    then
      _array_reset "$1"
      return "$?"
    fi
  else
    case "$?" in
      1)
        # A missing array can only be created with:
        #
        #   array NAME

        if [ "$#" -eq "1" ]
        then
          _array_var_set "${1}_TYPE" "array" ||
            return 1

          if ! _array_var_set "${1}_SIZE" "0"
          then
            unset "${1}_TYPE"
            return 1
          fi

          return 0
        fi

        return 1
      ;;

      *)
        return 1
      ;;
    esac
  fi


  case "$2" in
    size)
      [ "$#" -eq "2" ] ||
      [ "$#" -eq "3" ] ||
        return 2

      if [ "$#" -eq "2" ]
      then
        _array_var_print "${1}_SIZE"
      else
        _array_destination_valid "$1" "$3" ||
          return 2

        _array_var_copy "$3" "${1}_SIZE"
      fi
    ;;


    get)
      [ "$#" -ge "2" ] &&
      [ "$#" -le "4" ] ||
        return 2

      eval \
        "set -- \"\$@\" \"\${${1}_SIZE}\""

      # array NAME get
      #
      # becomes:
      #
      # NAME get SIZE

      if [ "$#" -eq "3" ]
      then
        _array_get_all "$1" "$3"
        return "$?"
      fi

      # array NAME get INDEX
      #
      # becomes:
      #
      # NAME get INDEX SIZE

      if [ "$#" -eq "4" ]
      then
        _array_uint_valid "$3" ||
          return 2

        [ "$3" -lt "$4" ] ||
          return 1

        _array_var_print "${1}_${3}"
      else
        # array NAME get INDEX DESTINATION
        #
        # becomes:
        #
        # NAME get INDEX DESTINATION SIZE

        _array_uint_valid "$3" ||
          return 2

        [ "$3" -lt "$5" ] ||
          return 1

        _array_destination_valid "$1" "$4" ||
          return 2

        _array_var_copy "$4" "${1}_${3}"
      fi
    ;;


    put)
      [ "$#" -eq "4" ] ||
        return 2

      _array_uint_valid "$3" ||
        return 2

      eval \
        "set -- \"\$@\" \"\${${1}_SIZE}\""

      [ "$3" -lt "$5" ] ||
        return 1

      _array_var_is_set "${1}_${3}" ||
        return 1

      _array_var_set "${1}_${3}" "$4"
    ;;


    add)
      [ "$#" -eq "3" ] ||
        return 2

      _array_add "$1" "$3"
    ;;


    ins)
      [ "$#" -eq "4" ] ||
        return 2

      _array_uint_valid "$3" ||
        return 2

      eval \
        "set -- \"\$@\" \"\${${1}_SIZE}\""

      # INDEX == SIZE is valid and therefore acts as append.

      [ "$3" -le "$5" ] ||
        return 1

      _array_insert "$1" "$3" "$4"
    ;;


    rem)
      [ "$#" -eq "3" ] ||
        return 2

      _array_uint_valid "$3" ||
        return 2

      eval \
        "set -- \"\$@\" \"\${${1}_SIZE}\""

      [ "$3" -lt "$4" ] ||
        return 1

      _array_remove "$1" "$3"
    ;;


    set)
      _array_set "$@"
    ;;


    unset)
      [ "$#" -eq "2" ] ||
        return 2

      _array_destroy "$1"
    ;;


    *)
      return 2
    ;;
  esac
}
