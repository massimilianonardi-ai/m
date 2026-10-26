loadsyslib "json"

_pkg_repository_chromium_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_chromium_scalar_file=$1

  [ -f "$pkg_repository_chromium_scalar_file" ] && \
  [ ! -L "$pkg_repository_chromium_scalar_file" ] && \
  [ ! -x "$pkg_repository_chromium_scalar_file" ] || return 1

  pkg_repository_chromium_scalar_value=
  pkg_repository_chromium_scalar_extra=
  {
    IFS= read -r pkg_repository_chromium_scalar_value || return 1
    IFS= read -r pkg_repository_chromium_scalar_extra
    pkg_repository_chromium_scalar_second_status=$?
  } < "$pkg_repository_chromium_scalar_file"

  [ "$pkg_repository_chromium_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_chromium_scalar_extra" ] || return 1
  [ -n "$pkg_repository_chromium_scalar_value" ] || return 1

  pkg_repository_chromium_scalar_cr="$(printf '\r')"
  case "$pkg_repository_chromium_scalar_value" in
    *"$pkg_repository_chromium_scalar_cr"*) return 1;;
  esac

  pkg_repository_chromium_scalar_actual="$(command -p -- wc -c < "$pkg_repository_chromium_scalar_file")" || return 1
  pkg_repository_chromium_scalar_expected="$(printf '%s\n' "$pkg_repository_chromium_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_chromium_scalar_actual" = "$pkg_repository_chromium_scalar_expected" ] || return 1

  printf -- '%s\n' "$pkg_repository_chromium_scalar_value"
}

_pkg_repository_chromium_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    ''|0|0*|*[!0-9]*) return 1;;
  esac
}

_pkg_repository_chromium_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_chromium_repository_dir=$1

  [ -d "$pkg_repository_chromium_repository_dir" ] && [ ! -L "$pkg_repository_chromium_repository_dir" ] || return 1

  for pkg_repository_chromium_repository_item in \
    "$pkg_repository_chromium_repository_dir"/* \
    "$pkg_repository_chromium_repository_dir"/.[!.]* \
    "$pkg_repository_chromium_repository_dir"/..?*
  do
    [ -e "$pkg_repository_chromium_repository_item" ] || [ -L "$pkg_repository_chromium_repository_item" ] || continue
    pkg_repository_chromium_repository_name=${pkg_repository_chromium_repository_item##*/}
    case "$pkg_repository_chromium_repository_name" in
      type|platform) :;;
      *) return 1;;
    esac
  done

  pkg_repository_chromium_type="$(_pkg_repository_chromium_scalar "$pkg_repository_chromium_repository_dir/type")" || return 1
  pkg_repository_chromium_platform="$(_pkg_repository_chromium_scalar "$pkg_repository_chromium_repository_dir/platform")" || return 1

  [ "$pkg_repository_chromium_type" = chromium ] || return 1
  case "$pkg_repository_chromium_platform" in
    Linux_x64|Mac|Mac_Arm|Win_x64|Win_Arm64) :;;
    *) return 1;;
  esac
}

_pkg_repository_chromium_archive()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    Linux_x64) printf -- 'chrome-linux.zip\n';;
    Mac|Mac_Arm) printf -- 'chrome-mac.zip\n';;
    Win_x64|Win_Arm64) printf -- 'chrome-win.zip\n';;
    *) return 1;;
  esac
}

_pkg_repository_chromium_md5_hex()
{
  [ "$#" -eq 1 ] || return 2
  LC_ALL=C command -p -- awk -v value="$1" '
function index64(c,    p) {
  p=index(alphabet,c)
  if (p == 0) exit 1
  return p-1
}
BEGIN {
  alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  if (length(value) != 24 || substr(value,23,2) != "==") exit 1
  for (i=1; i<=22; i++) {
    if (index(alphabet,substr(value,i,1)) == 0) exit 1
  }

  output=""
  for (i=1; i<=20; i+=4) {
    a=index64(substr(value,i,1))
    b=index64(substr(value,i+1,1))
    c=index64(substr(value,i+2,1))
    d=index64(substr(value,i+3,1))
    output=output sprintf("%02x", a*4+int(b/16))
    output=output sprintf("%02x", (b%16)*16+int(c/4))
    output=output sprintf("%02x", (c%4)*64+d)
  }

  a=index64(substr(value,21,1))
  b=index64(substr(value,22,1))
  if ((b%16) != 0) exit 1
  output=output sprintf("%02x", a*4+int(b/16))

  if (length(output) != 32) exit 1
  print output
}
'
}

_pkg_repository_chromium_metadata()
(
  [ "$#" -eq 2 ] || return 2
  _pkg_repository_chromium_validate_repository "$1" || return 1
  pkg_repository_chromium_requested=$2
  _pkg_repository_chromium_validate_version "$pkg_repository_chromium_requested" || return 1

  pkg_repository_chromium_archive="$(_pkg_repository_chromium_archive "$pkg_repository_chromium_platform")" || return 1
  pkg_repository_chromium_object="$pkg_repository_chromium_platform/$pkg_repository_chromium_requested/$pkg_repository_chromium_archive"
  pkg_repository_chromium_encoded_object="$pkg_repository_chromium_platform%2F$pkg_repository_chromium_requested%2F$pkg_repository_chromium_archive"
  pkg_repository_chromium_metadata_url="https://www.googleapis.com/storage/v1/b/chromium-browser-snapshots/o/$pkg_repository_chromium_encoded_object?fields=name%2Csize%2Cmd5Hash%2Ccrc32c"

  pkg_repository_chromium_body="$(http-fetch -- "$pkg_repository_chromium_metadata_url")" || return 1
  json_object_read \
    name pkg_repository_chromium_name_token \
    size pkg_repository_chromium_size_token \
    md5Hash pkg_repository_chromium_md5_token \
    crc32c pkg_repository_chromium_crc32c_token <<EOF_JSON
$pkg_repository_chromium_body
EOF_JSON
  [ "$?" -eq 0 ] || return 1

  case "$pkg_repository_chromium_name_token" in
    s:*) pkg_repository_chromium_name=${pkg_repository_chromium_name_token#s:};;
    *) return 1;;
  esac
  [ "$pkg_repository_chromium_name" = "$pkg_repository_chromium_object" ] || return 1

  case "$pkg_repository_chromium_size_token" in
    s:*) pkg_repository_chromium_size=${pkg_repository_chromium_size_token#s:};;
    *) return 1;;
  esac
  case "$pkg_repository_chromium_size" in
    ''|*[!0-9]*|0[0-9]*) return 1;;
  esac

  case "$pkg_repository_chromium_md5_token" in
    s:*) pkg_repository_chromium_md5_base64=${pkg_repository_chromium_md5_token#s:};;
    *) return 1;;
  esac
  pkg_repository_chromium_md5="$(_pkg_repository_chromium_md5_hex "$pkg_repository_chromium_md5_base64")" || return 1

  case "$pkg_repository_chromium_crc32c_token" in
    s:*) pkg_repository_chromium_crc32c=${pkg_repository_chromium_crc32c_token#s:};;
    *) return 1;;
  esac
  [ -n "$pkg_repository_chromium_crc32c" ] || return 1

  printf -- '%s\t%s\t%s\n' \
    "$pkg_repository_chromium_archive" \
    "$pkg_repository_chromium_size" \
    "$pkg_repository_chromium_md5"
)

_pkg_repository_chromium_latest()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_chromium_validate_repository "$1" || return 1

  pkg_repository_chromium_latest_url="https://www.googleapis.com/download/storage/v1/b/chromium-browser-snapshots/o/$pkg_repository_chromium_platform%2FLAST_CHANGE?alt=media"
  pkg_repository_chromium_latest="$(http-fetch -- "$pkg_repository_chromium_latest_url")" || return 1
  _pkg_repository_chromium_validate_version "$pkg_repository_chromium_latest" || return 1

  _pkg_repository_chromium_metadata "$1" "$pkg_repository_chromium_latest" >/dev/null || return 1
  printf -- '%s\n' "$pkg_repository_chromium_latest"
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_chromium_validate_repository "$1" || return 1
  _pkg_repository_chromium_validate_version "$2" || return 1
  _pkg_repository_chromium_validate_version "$3" || return 1

  _pkg_repository_chromium_metadata "$1" "$2" >/dev/null || return 1
  if [ "$2" = "$3" ]
  then
    printf -- '0\n'
    return 0
  fi
  _pkg_repository_chromium_metadata "$1" "$3" >/dev/null || return 1

  LC_ALL=C command -p -- awk -v left="$2" -v right="$3" '
BEGIN {
  if (length(left) < length(right)) { print "-1"; exit 0 }
  if (length(left) > length(right)) { print "1"; exit 0 }
  if ("x" left < "x" right) print "-1"
  else if ("x" left > "x" right) print "1"
  else exit 1
}
' || return 1
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  _pkg_repository_chromium_validate_repository "$1" || return 1

  if [ "$#" -eq 1 ]
  then
    _pkg_repository_chromium_latest "$1"
    return $?
  fi

  pkg_repository_chromium_requested=$2
  _pkg_repository_chromium_validate_version "$pkg_repository_chromium_requested" || return 1
  _pkg_repository_chromium_metadata "$1" "$pkg_repository_chromium_requested" >/dev/null || return 1
  printf -- '%s\n' "$pkg_repository_chromium_requested"
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_chromium_validate_repository "$1" || return 1
  pkg_repository_chromium_range_dir=$2
  pkg_repository_chromium_requested=$3

  _pkg_repository_chromium_validate_version "$pkg_repository_chromium_requested" || return 1
  [ -d "$pkg_repository_chromium_range_dir" ] && [ ! -L "$pkg_repository_chromium_range_dir" ] || return 1

  pkg_repository_chromium_archive_regex="$(_pkg_repository_chromium_scalar "$pkg_repository_chromium_range_dir/archive_regex")" || return 1
  pkg_repository_chromium_archive="$(_pkg_repository_chromium_archive "$pkg_repository_chromium_platform")" || return 1
  LC_ALL=C command -p -- awk \
    -v value="$pkg_repository_chromium_archive" \
    -v expression="$pkg_repository_chromium_archive_regex" \
    'BEGIN { if (value ~ expression) exit 0; exit 1 }' || return 1

  if [ -e "$pkg_repository_chromium_range_dir/digest_regex" ] || [ -L "$pkg_repository_chromium_range_dir/digest_regex" ]
  then
    return 1
  fi

  pkg_repository_chromium_digest_type="$(_pkg_repository_chromium_scalar "$pkg_repository_chromium_range_dir/digest_type")" || return 1
  [ "$pkg_repository_chromium_digest_type" = md5 ] || return 1

  pkg_repository_chromium_metadata="$(_pkg_repository_chromium_metadata "$1" "$pkg_repository_chromium_requested")" || return 1
  pkg_repository_chromium_tab="$(printf '\t')"
  IFS="$pkg_repository_chromium_tab" read -r \
    pkg_repository_chromium_name \
    pkg_repository_chromium_size \
    pkg_repository_chromium_md5 \
    pkg_repository_chromium_extra <<EOF_METADATA
$pkg_repository_chromium_metadata
EOF_METADATA
  [ -z "$pkg_repository_chromium_extra" ] || return 1
  [ "$pkg_repository_chromium_name" = "$pkg_repository_chromium_archive" ] || return 1
  [ -n "$pkg_repository_chromium_size" ] || return 1
  [ "${#pkg_repository_chromium_md5}" -eq 32 ] || return 1

  pkg_repository_chromium_encoded_object="$pkg_repository_chromium_platform%2F$pkg_repository_chromium_requested%2F$pkg_repository_chromium_name"
  pkg_repository_chromium_url="https://www.googleapis.com/download/storage/v1/b/chromium-browser-snapshots/o/$pkg_repository_chromium_encoded_object?alt=media"

  printf -- 'name=%s\n' "$pkg_repository_chromium_name"
  printf -- 'url=%s\n' "$pkg_repository_chromium_url"
  printf -- 'size=%s\n' "$pkg_repository_chromium_size"
  printf -- 'digest=md5:%s\n' "$pkg_repository_chromium_md5"
)
