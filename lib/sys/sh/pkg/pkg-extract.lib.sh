_pkg_extract_require_empty_dir()
{
  [ "$#" -eq 1 ] || return 2
  [ -d "$1" ] && [ ! -L "$1" ] || return 1

  for pkg_extract_item in "$1"/* "$1"/.[!.]* "$1"/..?*
  do
    [ -e "$pkg_extract_item" ] || [ -L "$pkg_extract_item" ] || continue
    return 1
  done
}

_pkg_extract_single_real_dir()
{
  [ "$#" -eq 1 ] || return 2
  pkg_extract_count=0
  pkg_extract_single_dir=

  for pkg_extract_item in "$1"/* "$1"/.[!.]* "$1"/..?*
  do
    [ -e "$pkg_extract_item" ] || [ -L "$pkg_extract_item" ] || continue
    pkg_extract_count=$((pkg_extract_count + 1))
    pkg_extract_single_dir=$pkg_extract_item
    [ "$pkg_extract_count" -le 1 ] || return 1
  done

  [ "$pkg_extract_count" -eq 1 ] && [ -d "$pkg_extract_single_dir" ] && [ ! -L "$pkg_extract_single_dir" ]
}

_pkg_extract_macos_application_bundle()
{
  [ "$#" -eq 1 ] || return 2
  case "${1##*/}" in *.app) : ;; *) return 1 ;; esac
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  [ -d "$1/Contents" ] && [ ! -L "$1/Contents" ] || return 1
  [ -f "$1/Contents/Info.plist" ] && [ ! -L "$1/Contents/Info.plist" ] || return 1
  [ -d "$1/Contents/MacOS" ] && [ ! -L "$1/Contents/MacOS" ]
}

_pkg_extract_normalize_root()
{
  [ "$#" -eq 1 ] || return 2
  pkg_extract_output=$1
  pkg_extract_useful_root=$pkg_extract_output
  pkg_extract_top_wrapper=

  while _pkg_extract_single_real_dir "$pkg_extract_useful_root"
  do
    _pkg_extract_macos_application_bundle "$pkg_extract_single_dir" && break
    [ -n "$pkg_extract_top_wrapper" ] || pkg_extract_top_wrapper=$pkg_extract_single_dir
    pkg_extract_useful_root=$pkg_extract_single_dir
  done

  [ "$pkg_extract_useful_root" != "$pkg_extract_output" ] || return 0

  pkg_extract_swap="$pkg_extract_output/.pkg-extract-normalize-$$"
  [ ! -e "$pkg_extract_swap" ] && [ ! -L "$pkg_extract_swap" ] || return 1
  command -p -- mv -- "$pkg_extract_top_wrapper" "$pkg_extract_swap" || return 1

  if [ "$pkg_extract_useful_root" = "$pkg_extract_top_wrapper" ]
  then
    pkg_extract_useful_root=$pkg_extract_swap
  else
    pkg_extract_useful_suffix=${pkg_extract_useful_root#"$pkg_extract_top_wrapper"}
    pkg_extract_useful_root="$pkg_extract_swap$pkg_extract_useful_suffix"
  fi

  _pkg_extract_move_contents "$pkg_extract_useful_root" "$pkg_extract_output" || return 1
  command -p -- rm -rf -- "$pkg_extract_swap"
}

_pkg_extract_component_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in ""|.|..|*/*|*'
'*) return 1 ;; *.pkg) return 0 ;; *) return 1 ;; esac
}

_pkg_extract_relative_path_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in ""|/*|*/|*//*|*'
'*) return 1 ;; esac
  case "/$1/" in */./*|*/../*) return 1 ;; esac
}

_pkg_extract_controlled_name_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in ""|[!abcdefghijklmnopqrstuvwxyz0123456789]*|*[!abcdefghijklmnopqrstuvwxyz0123456789._-]*|*[._-]) return 1 ;; esac
}

_pkg_extract_scalar_read()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_extract_scalar=
  pkg_extract_scalar_extra=
  {
    IFS= read -r pkg_extract_scalar || return 1
    IFS= read -r pkg_extract_scalar_extra
    pkg_extract_scalar_second_status=$?
  } < "$1"

  [ "$pkg_extract_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_extract_scalar_extra" ] || return 1
  [ -n "$pkg_extract_scalar" ] || return 1
  pkg_extract_scalar_actual="$(command -p -- wc -c < "$1")" || return 1
  pkg_extract_scalar_expected="$(printf '%s\n' "$pkg_extract_scalar" | command -p -- wc -c)" || return 1
  [ "$pkg_extract_scalar_actual" = "$pkg_extract_scalar_expected" ]
}

_pkg_extract_relative_dir_ensure()
{
  [ "$#" -eq 2 ] || return 2
  pkg_extract_relative_dir=$1
  pkg_extract_relative_rest=$2
  _pkg_extract_relative_path_valid "$pkg_extract_relative_rest" || return 1

  while [ -n "$pkg_extract_relative_rest" ]
  do
    case "$pkg_extract_relative_rest" in
      */*) pkg_extract_relative_part=${pkg_extract_relative_rest%%/*}; pkg_extract_relative_rest=${pkg_extract_relative_rest#*/} ;;
      *) pkg_extract_relative_part=$pkg_extract_relative_rest; pkg_extract_relative_rest= ;;
    esac
    pkg_extract_relative_next="$pkg_extract_relative_dir/$pkg_extract_relative_part"
    if [ -e "$pkg_extract_relative_next" ] || [ -L "$pkg_extract_relative_next" ]
    then
      [ -d "$pkg_extract_relative_next" ] && [ ! -L "$pkg_extract_relative_next" ] || return 1
    else
      command -p -- mkdir "$pkg_extract_relative_next" || return 1
    fi
    pkg_extract_relative_dir=$pkg_extract_relative_next
  done
}

_pkg_extract_move_contents()
{
  [ "$#" -eq 2 ] || return 2
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  [ -d "$2" ] && [ ! -L "$2" ] || return 1

  for pkg_extract_move_item in "$1"/* "$1"/.[!.]* "$1"/..?*
  do
    [ -e "$pkg_extract_move_item" ] || [ -L "$pkg_extract_move_item" ] || continue
    pkg_extract_move_target="$2/${pkg_extract_move_item##*/}"
    [ ! -e "$pkg_extract_move_target" ] && [ ! -L "$pkg_extract_move_target" ] || return 1
    command -p -- mv -- "$pkg_extract_move_item" "$2/" || return 1
  done
}

_pkg_extract_component_materialize()
{
  [ "$#" -eq 4 ] || return 2
  pkg_extract_expanded=$1
  pkg_extract_component=$2
  pkg_extract_payload_root=$3
  pkg_extract_destination=$4

  _pkg_extract_component_valid "$pkg_extract_component" || return 1
  pkg_extract_payload="$pkg_extract_expanded/$pkg_extract_component/Payload"
  [ -d "$pkg_extract_payload" ] && [ ! -L "$pkg_extract_payload" ] || return 1
  pkg_extract_selected=$pkg_extract_payload

  if [ -n "$pkg_extract_payload_root" ]
  then
    _pkg_extract_relative_path_valid "$pkg_extract_payload_root" || return 2
    readpathce pkg_extract_payload_base "$pkg_extract_payload" || return 1
    pkg_extract_payload_candidate="$pkg_extract_payload/$pkg_extract_payload_root"
    [ -d "$pkg_extract_payload_candidate" ] && [ ! -L "$pkg_extract_payload_candidate" ] || return 1
    readpathce pkg_extract_selected "$pkg_extract_payload_candidate" || return 1
    case "$pkg_extract_selected" in "$pkg_extract_payload_base"/*) : ;; *) return 1 ;; esac
  fi

  _pkg_extract_move_contents "$pkg_extract_selected" "$pkg_extract_destination"
}

_pkg_extract_single_pkg()
{
  [ "$#" -eq 1 ] || return 2
  pkg_extract_pkg_count=0
  pkg_extract_pkg=

  for pkg_extract_candidate in "$1"/*.pkg
  do
    [ -e "$pkg_extract_candidate" ] || [ -L "$pkg_extract_candidate" ] || continue
    [ -f "$pkg_extract_candidate" ] && [ ! -L "$pkg_extract_candidate" ] || return 1
    pkg_extract_pkg_count=$((pkg_extract_pkg_count + 1))
    pkg_extract_pkg=$pkg_extract_candidate
    [ "$pkg_extract_pkg_count" -le 1 ] || return 1
  done

  [ "$pkg_extract_pkg_count" -eq 1 ]
}

_pkg_extract_overlay_materialize()
{
  [ "$#" -eq 3 ] || return 2
  pkg_extract_overlay_expanded=$1
  pkg_extract_overlay_root=$2
  pkg_extract_overlay_staging=$3
  pkg_extract_overlay_count=0

  for pkg_extract_overlay_entry in "$pkg_extract_overlay_root"/* "$pkg_extract_overlay_root"/.[!.]* "$pkg_extract_overlay_root"/..?*
  do
    [ -e "$pkg_extract_overlay_entry" ] || [ -L "$pkg_extract_overlay_entry" ] || continue
    pkg_extract_overlay_name=${pkg_extract_overlay_entry##*/}
    _pkg_extract_controlled_name_valid "$pkg_extract_overlay_name" || return 1
    [ -d "$pkg_extract_overlay_entry" ] && [ ! -L "$pkg_extract_overlay_entry" ] || return 1
    pkg_extract_overlay_count=$((pkg_extract_overlay_count + 1))
    pkg_extract_overlay_component_file=
    pkg_extract_overlay_payload_file=
    pkg_extract_overlay_target_file=

    for pkg_extract_overlay_field in "$pkg_extract_overlay_entry"/* "$pkg_extract_overlay_entry"/.[!.]* "$pkg_extract_overlay_entry"/..?*
    do
      [ -e "$pkg_extract_overlay_field" ] || [ -L "$pkg_extract_overlay_field" ] || continue
      case "${pkg_extract_overlay_field##*/}" in
        component) [ -z "$pkg_extract_overlay_component_file" ] || return 1; pkg_extract_overlay_component_file=$pkg_extract_overlay_field ;;
        payload-root) [ -z "$pkg_extract_overlay_payload_file" ] || return 1; pkg_extract_overlay_payload_file=$pkg_extract_overlay_field ;;
        target-root) [ -z "$pkg_extract_overlay_target_file" ] || return 1; pkg_extract_overlay_target_file=$pkg_extract_overlay_field ;;
        *) return 1 ;;
      esac
    done

    [ -n "$pkg_extract_overlay_component_file" ] || return 1
    _pkg_extract_scalar_read "$pkg_extract_overlay_component_file" || return 1
    pkg_extract_overlay_component=$pkg_extract_scalar
    pkg_extract_overlay_payload=
    pkg_extract_overlay_destination=$pkg_extract_overlay_staging

    if [ -n "$pkg_extract_overlay_payload_file" ]
    then
      _pkg_extract_scalar_read "$pkg_extract_overlay_payload_file" || return 1
      pkg_extract_overlay_payload=$pkg_extract_scalar
      _pkg_extract_relative_path_valid "$pkg_extract_overlay_payload" || return 1
    fi

    if [ -n "$pkg_extract_overlay_target_file" ]
    then
      _pkg_extract_scalar_read "$pkg_extract_overlay_target_file" || return 1
      _pkg_extract_relative_dir_ensure "$pkg_extract_overlay_staging" "$pkg_extract_scalar" || return 1
      pkg_extract_overlay_destination=$pkg_extract_relative_dir
    fi

    _pkg_extract_component_materialize "$pkg_extract_overlay_expanded" "$pkg_extract_overlay_component" "$pkg_extract_overlay_payload" "$pkg_extract_overlay_destination" || return 1
  done

  [ "$pkg_extract_overlay_count" -gt 0 ]
}

_pkg_extract_work_create()
{
  [ "$#" -eq 1 ] || return 2
  pkg_extract_work_parent=${1%/*}
  [ "$pkg_extract_work_parent" != "$1" ] || return 1
  pkg_extract_work="$pkg_extract_work_parent/.pkg-extract-${1##*/}-$$"
  [ ! -e "$pkg_extract_work" ] && [ ! -L "$pkg_extract_work" ] || return 1
  command -p -- mkdir "$pkg_extract_work"
}

_pkg_extract_cleanup()
{
  [ -z "${pkg_extract_work-}" ] || command -p -- rm -rf -- "$pkg_extract_work" 2>/dev/null || :
}

pkg_extract()
(
  [ "$#" -eq 3 ] || return 2
  pkg_extract_artifact=$1
  pkg_extract_range_input=$2
  pkg_extract_staging_input=$3

  [ -f "$pkg_extract_artifact" ] && [ ! -L "$pkg_extract_artifact" ] && [ -r "$pkg_extract_artifact" ] || return 1
  [ -d "$pkg_extract_range_input" ] && [ ! -L "$pkg_extract_range_input" ] || return 1
  _pkg_extract_require_empty_dir "$pkg_extract_staging_input" || return 1
  readpathce pkg_extract_range "$pkg_extract_range_input" || return 1
  readpathce pkg_extract_staging "$pkg_extract_staging_input" || return 1

  _pkg_extract_scalar_read "$pkg_extract_range/format" || return 1
  pkg_extract_format=$pkg_extract_scalar
  pkg_extract_component_file="$pkg_extract_range/component"
  pkg_extract_payload_file="$pkg_extract_range/payload-root"
  pkg_extract_overlay="$pkg_extract_range/overlay"
  pkg_extract_work=
  trap '_pkg_extract_cleanup' 0 HUP INT TERM

  case "$pkg_extract_format" in
    flat-pkg)
      _pkg_extract_scalar_read "$pkg_extract_component_file" || return 1
      pkg_extract_component=$pkg_extract_scalar
      pkg_extract_payload_root=
      if [ -e "$pkg_extract_payload_file" ] || [ -L "$pkg_extract_payload_file" ]
      then
        _pkg_extract_scalar_read "$pkg_extract_payload_file" || return 1
        pkg_extract_payload_root=$pkg_extract_scalar
        _pkg_extract_relative_path_valid "$pkg_extract_payload_root" || return 2
      fi
      [ ! -e "$pkg_extract_overlay" ] && [ ! -L "$pkg_extract_overlay" ] || return 1
      _pkg_extract_work_create "$pkg_extract_staging" || return 1
      command -p -- mkdir "$pkg_extract_work/pkg" || return 1
      command -- extract pkg "$pkg_extract_artifact" "$pkg_extract_work/pkg" || return 1
      _pkg_extract_component_materialize "$pkg_extract_work/pkg" "$pkg_extract_component" "$pkg_extract_payload_root" "$pkg_extract_staging" || return $?
      ;;

    dmg-pkg)
      _pkg_extract_scalar_read "$pkg_extract_component_file" || return 1
      pkg_extract_component=$pkg_extract_scalar
      pkg_extract_payload_root=
      if [ -e "$pkg_extract_payload_file" ] || [ -L "$pkg_extract_payload_file" ]
      then
        _pkg_extract_scalar_read "$pkg_extract_payload_file" || return 1
        pkg_extract_payload_root=$pkg_extract_scalar
        _pkg_extract_relative_path_valid "$pkg_extract_payload_root" || return 2
      fi
      if [ -e "$pkg_extract_overlay" ] || [ -L "$pkg_extract_overlay" ]
      then
        [ -d "$pkg_extract_overlay" ] && [ ! -L "$pkg_extract_overlay" ] || return 1
      else
        pkg_extract_overlay=
      fi
      _pkg_extract_work_create "$pkg_extract_staging" || return 1
      command -p -- mkdir "$pkg_extract_work/dmg" "$pkg_extract_work/pkg" || return 1
      command -- extract dmg "$pkg_extract_artifact" "$pkg_extract_work/dmg" || return 1
      _pkg_extract_single_pkg "$pkg_extract_work/dmg" || return 1
      command -- extract pkg "$pkg_extract_pkg" "$pkg_extract_work/pkg" || return 1
      _pkg_extract_component_materialize "$pkg_extract_work/pkg" "$pkg_extract_component" "$pkg_extract_payload_root" "$pkg_extract_staging" || return $?
      [ -z "$pkg_extract_overlay" ] || _pkg_extract_overlay_materialize "$pkg_extract_work/pkg" "$pkg_extract_overlay" "$pkg_extract_staging" || return 1
      ;;

    appimage|executable|tar|tar.gz|tgz|tar.bz2|tar.bzip2|tbz|tbz2|tar.xz|txz|tar.zst|tzst|gzip|gz|bzip|bzip2|bz2|xz|zstd|zst|zip|jar|war|7z|7zip|dmg|deb)
      [ ! -e "$pkg_extract_component_file" ] && [ ! -L "$pkg_extract_component_file" ] || return 1
      [ ! -e "$pkg_extract_payload_file" ] && [ ! -L "$pkg_extract_payload_file" ] || return 1
      [ ! -e "$pkg_extract_overlay" ] && [ ! -L "$pkg_extract_overlay" ] || return 1
      command -- extract "$pkg_extract_format" "$pkg_extract_artifact" "$pkg_extract_staging" || return 1
      ;;

    *)
      return 2
      ;;
  esac

  _pkg_extract_normalize_root "$pkg_extract_staging" || return 1
)
