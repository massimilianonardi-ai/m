loadsyslib "pkg/pkg-local"

pkg_versions()
(
  [ "$#" -eq 1 ] || return 2

  _pkg_local_operand_parse "$1" || return 2
  [ -z "$pkg_local_requested_version" ] || return 2

  _pkg_local_class_select "$pkg_local_pkg" "$pkg_local_requested_osarch" || return 1
  [ "$pkg_local_class_present" -eq 1 ] || return 1
  [ "$pkg_local_class_count" -gt 0 ] || return 1

  LC_ALL=C
  export LC_ALL

  if [ -n "$pkg_local_identity_osarch" ]
  then
    for pkg_versions_path in "$m_PKG_DIR/$pkg_local_pkg@"*"!$pkg_local_identity_osarch"
    do
      [ -d "$pkg_versions_path" ] && [ ! -L "$pkg_versions_path" ] || return 1
      printf -- '%s\n' "${pkg_versions_path##*/}" || return 1
    done
  else
    for pkg_versions_path in "$m_PKG_DIR/$pkg_local_pkg@"*
    do
      [ -e "$pkg_versions_path" ] || [ -L "$pkg_versions_path" ] || continue
      pkg_versions_name=${pkg_versions_path##*/}
      case "$pkg_versions_name" in
        *!*) continue ;;
      esac
      [ -d "$pkg_versions_path" ] && [ ! -L "$pkg_versions_path" ] || return 1
      printf -- '%s\n' "$pkg_versions_name" || return 1
    done
  fi

  return 0
)
