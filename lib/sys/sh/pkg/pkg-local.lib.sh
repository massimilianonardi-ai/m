loadsyslib "pkg/pkg-common"

_pkg_local_operand_parse()
{
  [ "$#" -eq 1 ] || return 2
  pkg_local_operand=$1
  pkg_local_pkg=
  pkg_local_requested_version=
  pkg_local_requested_osarch=
  pkg_local_left=$pkg_local_operand

  case "$pkg_local_left" in
    *!*)
      pkg_local_requested_osarch=${pkg_local_left##*!}
      pkg_local_left=${pkg_local_left%!"$pkg_local_requested_osarch"}
      case "$pkg_local_left" in
        *!*) return 2 ;;
      esac
      pkg_osarch_valid "$pkg_local_requested_osarch" || return 2
      ;;
  esac

  case "$pkg_local_left" in
    *@*)
      pkg_local_requested_version=${pkg_local_left##*@}
      pkg_local_pkg=${pkg_local_left%@"$pkg_local_requested_version"}
      case "$pkg_local_pkg" in
        *@*) return 2 ;;
      esac
      pkg_version_valid "$pkg_local_requested_version" || return 2
      ;;
    *)
      pkg_local_pkg=$pkg_local_left
      ;;
  esac

  pkg_name_valid "$pkg_local_pkg" || return 2
}

_pkg_local_class_scan()
{
  [ "$#" -eq 2 ] || return 2
  pkg_local_scan_pkg=$1
  pkg_local_scan_osarch=$2
  pkg_local_class_present=0
  pkg_local_class_count=0
  pkg_local_class_single_version=
  pkg_local_class_current_version=
  pkg_local_class_current_name=
  pkg_local_class_current_found=0

  if [ -n "$pkg_local_scan_osarch" ]
  then
    pkg_local_selector_name="$pkg_local_scan_pkg!$pkg_local_scan_osarch"
  else
    pkg_local_selector_name=$pkg_local_scan_pkg
  fi
  pkg_local_selector="$m_PKG_DIR/$pkg_local_selector_name"

  if [ -e "$pkg_local_selector" ] || [ -L "$pkg_local_selector" ]
  then
    pkg_local_class_present=1
    [ -L "$pkg_local_selector" ] || return 1
    pkg_local_class_current_name="$(command -p -- readlink -- "$pkg_local_selector")" || return 1
    case "$pkg_local_class_current_name" in
      "" | */*) return 1 ;;
    esac

    if [ -n "$pkg_local_scan_osarch" ]
    then
      pkg_local_current_prefix="$pkg_local_scan_pkg@"
      pkg_local_current_suffix="!$pkg_local_scan_osarch"
      case "$pkg_local_class_current_name" in
        "$pkg_local_current_prefix"*"$pkg_local_current_suffix")
          pkg_local_class_current_version=${pkg_local_class_current_name#"$pkg_local_current_prefix"}
          pkg_local_class_current_version=${pkg_local_class_current_version%"$pkg_local_current_suffix"}
          ;;
        *)
          return 1
          ;;
      esac
      pkg_version_valid "$pkg_local_class_current_version" || return 1
      [ "$pkg_local_class_current_name" = "$pkg_local_scan_pkg@$pkg_local_class_current_version!$pkg_local_scan_osarch" ] || return 1
    else
      pkg_local_current_prefix="$pkg_local_scan_pkg@"
      case "$pkg_local_class_current_name" in
        "$pkg_local_current_prefix"*)
          pkg_local_class_current_version=${pkg_local_class_current_name#"$pkg_local_current_prefix"}
          ;;
        *)
          return 1
          ;;
      esac
      pkg_version_valid "$pkg_local_class_current_version" || return 1
      [ "$pkg_local_class_current_name" = "$pkg_local_scan_pkg@$pkg_local_class_current_version" ] || return 1
    fi
  fi

  for pkg_local_path in "$m_PKG_DIR/$pkg_local_scan_pkg@"*
  do
    [ -e "$pkg_local_path" ] || [ -L "$pkg_local_path" ] || continue
    pkg_local_name=${pkg_local_path##*/}

    if [ -n "$pkg_local_scan_osarch" ]
    then
      pkg_local_suffix="!$pkg_local_scan_osarch"
      case "$pkg_local_name" in
        "$pkg_local_scan_pkg@"*"$pkg_local_suffix")
          pkg_local_version=${pkg_local_name#"$pkg_local_scan_pkg@"}
          pkg_local_version=${pkg_local_version%"$pkg_local_suffix"}
          ;;
        *)
          continue
          ;;
      esac
      pkg_version_valid "$pkg_local_version" || return 1
      [ "$pkg_local_name" = "$pkg_local_scan_pkg@$pkg_local_version!$pkg_local_scan_osarch" ] || return 1
    else
      case "$pkg_local_name" in
        *!*) continue ;;
        "$pkg_local_scan_pkg@"*)
          pkg_local_version=${pkg_local_name#"$pkg_local_scan_pkg@"}
          ;;
        *)
          continue
          ;;
      esac
      pkg_version_valid "$pkg_local_version" || return 1
      [ "$pkg_local_name" = "$pkg_local_scan_pkg@$pkg_local_version" ] || return 1
    fi

    pkg_local_class_present=1
    [ -d "$pkg_local_path" ] && [ ! -L "$pkg_local_path" ] || return 1
    pkg_local_class_count=$((pkg_local_class_count + 1))
    if [ "$pkg_local_class_count" -eq 1 ]
    then
      pkg_local_class_single_version=$pkg_local_version
    else
      pkg_local_class_single_version=
    fi
    if [ -n "$pkg_local_class_current_name" ] && [ "$pkg_local_name" = "$pkg_local_class_current_name" ]
    then
      pkg_local_class_current_found=1
    fi
  done

  if [ -n "$pkg_local_class_current_name" ]
  then
    [ "$pkg_local_class_current_found" -eq 1 ] || return 1
  fi

  return 0
}

_pkg_local_class_select()
{
  [ "$#" -eq 2 ] || return 2
  pkg_local_select_pkg=$1
  pkg_local_select_osarch=$2

  [ -d "$m_PKG_DIR" ] && [ ! -L "$m_PKG_DIR" ] || return 1

  if [ -n "$pkg_local_select_osarch" ]
  then
    pkg_local_identity_osarch=$pkg_local_select_osarch
    _pkg_local_class_scan "$pkg_local_select_pkg" "$pkg_local_identity_osarch" || return 1
    return 0
  fi

  pkg_osarch_valid "$m_OSARCH" || return 1
  _pkg_local_class_scan "$pkg_local_select_pkg" "$m_OSARCH" || return 1
  if [ "$pkg_local_class_present" -eq 1 ]
  then
    pkg_local_identity_osarch=$m_OSARCH
    return 0
  fi

  pkg_local_identity_osarch=
  _pkg_local_class_scan "$pkg_local_select_pkg" "" || return 1
  return 0
}
