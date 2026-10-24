_pkg_setuid_validate()
{
  [ "$#" -eq 4 ] || return 2
  pkg_setuid_range=$1
  pkg_setuid_root=$2
  pkg_setuid_osarch=$3
  pkg_setuid_state_paths=$4
  pkg_setuid_file="$pkg_setuid_range/setuid_root"
  pkg_setuid_paths=

  if [ ! -e "$pkg_setuid_file" ] && [ ! -L "$pkg_setuid_file" ]
  then
    return 0
  fi

  case "$pkg_setuid_osarch" in
    linux-arm64 | linux-x86_64) : ;;
    *) return 1 ;;
  esac

  _pkg_state_file_validate "$pkg_setuid_file" || return 1

  while IFS= read -r pkg_setuid_path
  do
    _pkg_state_source_type_set "$pkg_setuid_root" "$pkg_setuid_path" || return 1
    [ "$pkg_state_source_type" = file ] || return 1

    if [ -n "$pkg_setuid_paths" ]
    then
      while IFS= read -r pkg_setuid_existing_path
      do
        [ "$pkg_setuid_path" != "$pkg_setuid_existing_path" ] || return 1
      done <<EOF_SETUID_PATHS
$pkg_setuid_paths
EOF_SETUID_PATHS
    fi

    if [ -n "$pkg_setuid_state_paths" ]
    then
      while IFS= read -r pkg_setuid_state_path
      do
        [ "$pkg_setuid_path" != "$pkg_setuid_state_path" ] || return 1
        case "$pkg_setuid_path" in
          "$pkg_setuid_state_path"/*) return 1 ;;
        esac
        case "$pkg_setuid_state_path" in
          "$pkg_setuid_path"/*) return 1 ;;
        esac
      done <<EOF_STATE_PATHS
$pkg_setuid_state_paths
EOF_STATE_PATHS
    fi

    if [ -n "$pkg_setuid_paths" ]
    then
      pkg_setuid_paths="$pkg_setuid_paths
$pkg_setuid_path"
    else
      pkg_setuid_paths=$pkg_setuid_path
    fi
  done < "$pkg_setuid_file"

  return 0
}

_pkg_setuid_effective_uid_set()
{
  [ "$#" -eq 0 ] || return 2
  pkg_setuid_effective_uid="$(command -p -- id -u 2>/dev/null)" || return 1
  case "$pkg_setuid_effective_uid" in
    "" | *[!0-9]*) return 1 ;;
  esac
}

_pkg_setuid_command_paths_set()
{
  [ "$#" -eq 1 ] || return 2
  pkg_setuid_need_sudo=$1

  pkg_setuid_chown_bin="$(command -p -v chown 2>/dev/null)" || return 1
  pkg_setuid_chmod_bin="$(command -p -v chmod 2>/dev/null)" || return 1
  case "$pkg_setuid_chown_bin" in /*) : ;; *) return 1 ;; esac
  case "$pkg_setuid_chmod_bin" in /*) : ;; *) return 1 ;; esac

  pkg_setuid_sudo_bin=
  if [ "$pkg_setuid_need_sudo" -eq 1 ]
  then
    pkg_setuid_sudo_bin="$(command -p -v sudo 2>/dev/null)" || return 1
    case "$pkg_setuid_sudo_bin" in /*) : ;; *) return 1 ;; esac
  fi
}

_pkg_setuid_shell_quote_set()
{
  [ "$#" -eq 1 ] || return 2
  pkg_setuid_shell_quote_inner="$(printf -- '%s' "$1" | command -p -- sed "s/'/'\\\\''/g")" || return 1
  pkg_setuid_shell_quote="'$pkg_setuid_shell_quote_inner'"
}

_pkg_setuid_privilege_notice()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_setuid_shell_quote_set "$1" || return 1

  log warn security package-setuid-root-authorization-required target "$1" || :
  printf -- '  %s -- %s 0:0 %s\n' \
    "$pkg_setuid_sudo_bin" \
    "$pkg_setuid_chown_bin" \
    "$pkg_setuid_shell_quote" >&2
  printf -- '  %s -- %s 4755 %s\n' \
    "$pkg_setuid_sudo_bin" \
    "$pkg_setuid_chmod_bin" \
    "$pkg_setuid_shell_quote" >&2
}

_pkg_setuid_apply_file()
{
  [ "$#" -eq 1 ] || return 2
  pkg_setuid_apply_target=$1

  _pkg_setuid_effective_uid_set || return 1
  if [ "$pkg_setuid_effective_uid" -eq 0 ]
  then
    _pkg_setuid_command_paths_set 0 || return 1
    "$pkg_setuid_chown_bin" 0:0 "$pkg_setuid_apply_target" || return 1
    "$pkg_setuid_chmod_bin" 4755 "$pkg_setuid_apply_target"
    return $?
  fi

  _pkg_setuid_command_paths_set 1 || return 1
  _pkg_setuid_privilege_notice "$pkg_setuid_apply_target" || return 1
  "$pkg_setuid_sudo_bin" -- "$pkg_setuid_chown_bin" 0:0 "$pkg_setuid_apply_target" || return 1
  "$pkg_setuid_sudo_bin" -- "$pkg_setuid_chmod_bin" 4755 "$pkg_setuid_apply_target"
}

_pkg_setuid_rollback()
{
  [ "$#" -eq 2 ] || return 2
  pkg_setuid_range=$1
  pkg_setuid_concrete=$2
  pkg_setuid_file="$pkg_setuid_range/setuid_root"
  pkg_setuid_rollback_dir="$pkg_setuid_concrete/setuid-root-rollback"
  pkg_setuid_rollback_status=0

  if [ ! -e "$pkg_setuid_rollback_dir" ] && [ ! -L "$pkg_setuid_rollback_dir" ]
  then
    return 0
  fi
  [ -d "$pkg_setuid_rollback_dir" ] && [ ! -L "$pkg_setuid_rollback_dir" ] || return 1

  pkg_setuid_index=0
  while IFS= read -r pkg_setuid_path
  do
    pkg_setuid_index=$((pkg_setuid_index + 1))
    pkg_setuid_target="$pkg_setuid_concrete/root/$pkg_setuid_path"
    pkg_setuid_backup="$pkg_setuid_rollback_dir/original-$pkg_setuid_index"
    pkg_setuid_work="$pkg_setuid_rollback_dir/work-$pkg_setuid_index"

    if [ -e "$pkg_setuid_work" ] || [ -L "$pkg_setuid_work" ]
    then
      command -p -- rm -f -- "$pkg_setuid_work" || pkg_setuid_rollback_status=1
    fi

    if [ -e "$pkg_setuid_backup" ] || [ -L "$pkg_setuid_backup" ]
    then
      [ -f "$pkg_setuid_backup" ] && [ ! -L "$pkg_setuid_backup" ] || {
        pkg_setuid_rollback_status=1
        continue
      }

      if [ -e "$pkg_setuid_target" ] || [ -L "$pkg_setuid_target" ]
      then
        command -p -- rm -f -- "$pkg_setuid_target" || {
          pkg_setuid_rollback_status=1
          continue
        }
      fi

      command -p -- mv -- "$pkg_setuid_backup" "$pkg_setuid_target" || pkg_setuid_rollback_status=1
    fi
  done < "$pkg_setuid_file"

  command -p -- rmdir -- "$pkg_setuid_rollback_dir" 2>/dev/null || pkg_setuid_rollback_status=1
  return "$pkg_setuid_rollback_status"
}

_pkg_setuid_materialize()
{
  [ "$#" -eq 2 ] || return 2
  pkg_setuid_range=$1
  pkg_setuid_concrete=$2
  pkg_setuid_file="$pkg_setuid_range/setuid_root"
  pkg_setuid_rollback_dir="$pkg_setuid_concrete/setuid-root-rollback"

  if [ ! -e "$pkg_setuid_file" ] && [ ! -L "$pkg_setuid_file" ]
  then
    return 0
  fi

  command -p -- mkdir -- "$pkg_setuid_rollback_dir" || return 1

  pkg_setuid_index=0
  while IFS= read -r pkg_setuid_path
  do
    pkg_setuid_index=$((pkg_setuid_index + 1))
    pkg_setuid_target="$pkg_setuid_concrete/root/$pkg_setuid_path"
    pkg_setuid_backup="$pkg_setuid_rollback_dir/original-$pkg_setuid_index"
    pkg_setuid_work="$pkg_setuid_rollback_dir/work-$pkg_setuid_index"

    command -p -- mv -- "$pkg_setuid_target" "$pkg_setuid_backup" || return 1
    command -p -- cp -- "$pkg_setuid_backup" "$pkg_setuid_work" || return 1
    _pkg_setuid_apply_file "$pkg_setuid_work" || return 1
    command -p -- mv -- "$pkg_setuid_work" "$pkg_setuid_target" || return 1
  done < "$pkg_setuid_file"

  return 0
}

_pkg_setuid_cleanup()
{
  [ "$#" -eq 2 ] || return 2
  pkg_setuid_range=$1
  pkg_setuid_concrete=$2
  pkg_setuid_file="$pkg_setuid_range/setuid_root"
  pkg_setuid_rollback_dir="$pkg_setuid_concrete/setuid-root-rollback"

  if [ ! -e "$pkg_setuid_file" ] && [ ! -L "$pkg_setuid_file" ]
  then
    return 0
  fi

  [ -d "$pkg_setuid_rollback_dir" ] && [ ! -L "$pkg_setuid_rollback_dir" ] || return 1
  command -p -- rm -rf -- "$pkg_setuid_rollback_dir"
}

_pkg_setuid_commit()
{
  [ "$#" -eq 2 ] || return 2

  if ! _pkg_setuid_cleanup "$1" "$2"
  then
    log warn execution execution-failed operation pkg-integrate reason setuid-cleanup-failed || :
  fi

  return 0
}
