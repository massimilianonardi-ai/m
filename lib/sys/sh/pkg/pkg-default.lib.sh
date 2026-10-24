loadsyslib "pkg/pkg-local"
loadsyslib "pkg/pkg-integration"

_pkg_default_apply_call()
{
  [ "$#" -eq 3 ] || return 2

  if [ -n "$3" ]
  then
    pkg_default_apply "$1" "$2" "$3"
  else
    pkg_default_apply "$1" "$2"
  fi
}

pkg_default()
(
  pkg_default_unset=0

  case "${1-}" in
    -u)
      pkg_default_unset=1
      shift
      ;;
    --)
      shift
      ;;
    -*)
      return 2
      ;;
  esac

  if [ "$pkg_default_unset" -eq 1 ] && [ "${1-}" = "--" ]
  then
    shift
  fi

  [ "$#" -eq 1 ] || return 2

  _pkg_local_operand_parse "$1" || return 2
  if [ "$pkg_default_unset" -eq 1 ] && [ -n "$pkg_local_requested_version" ]
  then
    return 2
  fi

  _pkg_local_class_select "$pkg_local_pkg" "$pkg_local_requested_osarch" || return 1

  if [ "$pkg_default_unset" -eq 1 ]
  then
    [ "$pkg_local_class_present" -eq 1 ] || return 0
    _pkg_default_apply_call "$pkg_local_pkg" "" "$pkg_local_identity_osarch" || return 1
    return 0
  fi

  [ "$pkg_local_class_present" -eq 1 ] || return 1

  if [ -n "$pkg_local_requested_version" ]
  then
    _pkg_default_apply_call "$pkg_local_pkg" "$pkg_local_requested_version" "$pkg_local_identity_osarch" || return 1
    return 0
  fi

  [ -n "$pkg_local_class_current_name" ] || return 1
  printf -- '%s\n' "$pkg_local_class_current_name" || return 1
  return 0
)
