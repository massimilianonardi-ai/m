loadsyslib "json"
loadsyslib "pkg/repository/pkg-repository-artifact"

_pkg_repository_github_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_github_scalar_file=$1

  [ -f "$pkg_repository_github_scalar_file" ] && \
  [ ! -L "$pkg_repository_github_scalar_file" ] && \
  [ ! -x "$pkg_repository_github_scalar_file" ] || return 1

  pkg_repository_github_scalar_value=
  pkg_repository_github_scalar_extra=
  {
    IFS= read -r pkg_repository_github_scalar_value || return 1
    IFS= read -r pkg_repository_github_scalar_extra
    pkg_repository_github_scalar_second_status=$?
  } < "$pkg_repository_github_scalar_file"

  [ "$pkg_repository_github_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_github_scalar_extra" ] || return 1
  [ -n "$pkg_repository_github_scalar_value" ] || return 1

  pkg_repository_github_scalar_cr="$(printf '\r')"
  case "$pkg_repository_github_scalar_value" in
    *"$pkg_repository_github_scalar_cr"*) return 1;;
  esac

  pkg_repository_github_scalar_actual="$(command -p -- wc -c < "$pkg_repository_github_scalar_file")" || return 1
  pkg_repository_github_scalar_expected="$(printf '%s\n' "$pkg_repository_github_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_github_scalar_actual" = "$pkg_repository_github_scalar_expected" ] || return 1

  printf -- '%s\n' "$pkg_repository_github_scalar_value"
}

_pkg_repository_github_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._+~-]*) return 1;;
  esac
}

_pkg_repository_github_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_github_repository_dir=$1

  [ -d "$pkg_repository_github_repository_dir" ] && [ ! -L "$pkg_repository_github_repository_dir" ] || return 1

  for pkg_repository_github_repository_item in \
    "$pkg_repository_github_repository_dir"/* \
    "$pkg_repository_github_repository_dir"/.[!.]* \
    "$pkg_repository_github_repository_dir"/..?*
  do
    [ -e "$pkg_repository_github_repository_item" ] || [ -L "$pkg_repository_github_repository_item" ] || continue
    pkg_repository_github_repository_name=${pkg_repository_github_repository_item##*/}
    case "$pkg_repository_github_repository_name" in
      type|owner|repository|versions)
        [ -f "$pkg_repository_github_repository_item" ] && \
        [ ! -L "$pkg_repository_github_repository_item" ] && \
        [ ! -x "$pkg_repository_github_repository_item" ] || return 1
        ;;
      download|metadata)
        [ -d "$pkg_repository_github_repository_item" ] && [ ! -L "$pkg_repository_github_repository_item" ] || return 1
        ;;
      *) return 1;;
    esac
  done

  pkg_repository_github_type="$(_pkg_repository_github_scalar "$pkg_repository_github_repository_dir/type")" || return 1
  pkg_repository_github_owner="$(_pkg_repository_github_scalar "$pkg_repository_github_repository_dir/owner")" || return 1
  pkg_repository_github_repository="$(_pkg_repository_github_scalar "$pkg_repository_github_repository_dir/repository")" || return 1

  [ "$pkg_repository_github_type" = github ] || return 1
  case "$pkg_repository_github_owner" in
    ''|*[!A-Za-z0-9-]*) return 1;;
  esac
  case "$pkg_repository_github_repository" in
    ''|*[!A-Za-z0-9._-]*) return 1;;
  esac

  pkg_repository_artifact_overrides_validate "$pkg_repository_github_repository_dir"
}

_pkg_repository_github_get()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_github_path=$1
  pkg_repository_github_function=$2
  pkg_repository_github_url="https://api.github.com/repos/$pkg_repository_github_owner/$pkg_repository_github_repository$pkg_repository_github_path"

  http-fetch \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2026-03-10' \
    -- "$pkg_repository_github_url"
  pkg_repository_github_status=$?
  [ "$pkg_repository_github_status" -eq 0 ] && return 0

  log error execution execution-failed \
    operation pkg-repository-github \
    reason upstream-request-failed \
    function "$pkg_repository_github_function" \
    url "$pkg_repository_github_url" \
    status "$pkg_repository_github_status" || :
  return 1
}

_pkg_repository_github_validate_release_tokens()
{
  [ "$#" -ge 4 ] && [ "$#" -le 5 ] || return 2

  case "$1" in
    s:*) pkg_repository_github_release_tag=${1#s:};;
    *) return 1;;
  esac
  [ "$2" = b:false ] || return 1
  [ "$3" = b:false ] || return 1
  case "$4" in
    s:*) pkg_repository_github_release_created=${4#s:};;
    *) return 1;;
  esac

  _pkg_repository_github_validate_version "$pkg_repository_github_release_tag" || return 1
  LC_ALL=C command -p -- awk -v value="$pkg_repository_github_release_created" '
BEGIN {
  if (value ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) exit 0
  exit 1
}
' || return 1

  if [ "$#" -eq 5 ]
  then
    case "$5" in
      s:*) pkg_repository_github_release_published=${5#s:};;
      *) return 1;;
    esac
    LC_ALL=C command -p -- awk -v value="$pkg_repository_github_release_published" '
BEGIN {
  if (value ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) exit 0
  exit 1
}
' || return 1
  fi
}

_pkg_repository_github_index_order()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_github_index="$1/versions"
  [ -e "$pkg_repository_github_index" ] || [ -L "$pkg_repository_github_index" ] || return 3
  [ -f "$pkg_repository_github_index" ] && [ ! -L "$pkg_repository_github_index" ] && \
    [ -r "$pkg_repository_github_index" ] && [ ! -x "$pkg_repository_github_index" ] || return 1

  # Missing versions require live discovery (status 3); corrupt data fails closed.
  LC_ALL=C command -p -- awk -v left="$2" -v right="$3" '
  {
    if ($0 !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/ || seen[$0]++) {
      invalid=1
      exit 1
    }
    if ($0 == left) left_position=NR
    if ($0 == right) right_position=NR
  }
  END {
    if (invalid || NR == 0) exit 1
    if (!left_position || !right_position) exit 3
    if (left_position < right_position) print "-1"
    else if (left_position > right_position) print "1"
    else print "0"
  }
  ' "$pkg_repository_github_index"
)

_pkg_repository_github_release_order_key()
(
  [ "$#" -eq 2 ] || return 2
  _pkg_repository_github_validate_repository "$1" || return 1
  pkg_repository_github_requested=$2
  _pkg_repository_github_validate_version "$pkg_repository_github_requested" || return 1

  pkg_repository_github_body="$(_pkg_repository_github_get "/releases/tags/$pkg_repository_github_requested" pkg_repository_compare_versions)" || return 1
  json_object_read \
    tag_name pkg_repository_github_tag_token \
    draft pkg_repository_github_draft_token \
    prerelease pkg_repository_github_prerelease_token \
    created_at pkg_repository_github_created_token \
    published_at pkg_repository_github_published_token <<EOF_JSON
$pkg_repository_github_body
EOF_JSON
  [ "$?" -eq 0 ] || return 1

  _pkg_repository_github_validate_release_tokens \
    "$pkg_repository_github_tag_token" \
    "$pkg_repository_github_draft_token" \
    "$pkg_repository_github_prerelease_token" \
    "$pkg_repository_github_created_token" \
    "$pkg_repository_github_published_token" || return 1
  [ "$pkg_repository_github_release_tag" = "$pkg_repository_github_requested" ] || return 1

  printf -- '%s\t%s\n' "$pkg_repository_github_release_created" "$pkg_repository_github_release_published"
)

pkg_repository_list_versions()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_github_validate_repository "$1" || return 1

  pkg_repository_github_page=1
  pkg_repository_github_versions=
  pkg_repository_github_lf='
'
  pkg_repository_github_tab="$(printf '\t')"

  while :
  do
    pkg_repository_github_body="$(_pkg_repository_github_get "/releases?per_page=100&page=$pkg_repository_github_page" pkg_repository_list_versions)" || return 1
    pkg_repository_github_records="$(printf '%s\n' "$pkg_repository_github_body" | json_array_object_fields tag_name draft prerelease created_at published_at)" || return 1

    pkg_repository_github_count=0
    if [ -n "$pkg_repository_github_records" ]
    then
      while IFS="$pkg_repository_github_tab" read -r \
        pkg_repository_github_tag_token \
        pkg_repository_github_draft_token \
        pkg_repository_github_prerelease_token \
        pkg_repository_github_created_token \
        pkg_repository_github_published_token \
        pkg_repository_github_extra
      do
        [ -z "$pkg_repository_github_extra" ] || return 1
        pkg_repository_github_count=$((pkg_repository_github_count + 1))

        case "$pkg_repository_github_draft_token" in
          b:true) continue;;
          b:false) :;;
          *) return 1;;
        esac
        case "$pkg_repository_github_prerelease_token" in
          b:true) continue;;
          b:false) :;;
          *) return 1;;
        esac
        _pkg_repository_github_validate_release_tokens \
          "$pkg_repository_github_tag_token" \
          "$pkg_repository_github_draft_token" \
          "$pkg_repository_github_prerelease_token" \
          "$pkg_repository_github_created_token" \
          "$pkg_repository_github_published_token" || return 1

        pkg_repository_github_record="$pkg_repository_github_release_created$pkg_repository_github_tab$pkg_repository_github_release_published$pkg_repository_github_tab$pkg_repository_github_release_tag"
        if [ -n "$pkg_repository_github_versions" ]
        then
          pkg_repository_github_versions="$pkg_repository_github_versions$pkg_repository_github_lf$pkg_repository_github_record"
        else
          pkg_repository_github_versions=$pkg_repository_github_record
        fi
      done <<EOF_RECORDS
$pkg_repository_github_records
EOF_RECORDS
    fi

    [ "$pkg_repository_github_count" -ge 100 ] || break
    pkg_repository_github_page=$((pkg_repository_github_page + 1))
  done

  [ -n "$pkg_repository_github_versions" ] || return 0

  printf '%s\n' "$pkg_repository_github_versions" | \
    LC_ALL=C command -p -- sort | \
    LC_ALL=C command -p -- awk -F "$pkg_repository_github_tab" '
NF != 3 { exit 1 }
{
  if (previous_created != "" && $1 == previous_created && $2 == previous_published) exit 1
  if (seen[$3]) exit 1
  seen[$3]=1
  previous_created=$1
  previous_published=$2
  print $3
}
'
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_github_repository_dir=$1
  pkg_repository_github_left=$2
  pkg_repository_github_right=$3

  _pkg_repository_github_validate_repository "$pkg_repository_github_repository_dir" || return 1
  _pkg_repository_github_validate_version "$pkg_repository_github_left" || return 1
  _pkg_repository_github_validate_version "$pkg_repository_github_right" || return 1

  if [ "$pkg_repository_github_left" = "$pkg_repository_github_right" ]
  then
    printf -- '0\n'
    return 0
  fi

  if [ -e "$pkg_repository_github_repository_dir/versions" ] || [ -L "$pkg_repository_github_repository_dir/versions" ]
  then
    _pkg_repository_github_index_order "$pkg_repository_github_repository_dir" "$pkg_repository_github_left" "$pkg_repository_github_right"
    pkg_repository_github_index_status=$?
    case "$pkg_repository_github_index_status" in
      0) return 0 ;;
      3) : ;;
      *) return 1 ;;
    esac
  fi

  pkg_repository_github_left_key="$(_pkg_repository_github_release_order_key "$pkg_repository_github_repository_dir" "$pkg_repository_github_left")" || return 1

  pkg_repository_github_right_key="$(_pkg_repository_github_release_order_key "$pkg_repository_github_repository_dir" "$pkg_repository_github_right")" || return 1
  pkg_repository_github_order="$(LC_ALL=C command -p -- awk -v left="$pkg_repository_github_left_key" -v right="$pkg_repository_github_right_key" 'BEGIN {
  if (left < right) print "-1"
  else if (left > right) print "1"
  else exit 1
}')" || return 1

  case "$pkg_repository_github_order" in
    -1|1) printf -- '%s\n' "$pkg_repository_github_order";;
    *) return 1;;
  esac
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  _pkg_repository_github_validate_repository "$1" || return 1

  if [ "$#" -eq 1 ]
  then
    pkg_repository_github_path=/releases/latest
    pkg_repository_github_requested=
  else
    pkg_repository_github_requested=$2
    _pkg_repository_github_validate_version "$pkg_repository_github_requested" || return 1
    pkg_repository_github_path=/releases/tags/$pkg_repository_github_requested
    if [ -e "$1/versions" ] || [ -L "$1/versions" ]
    then
      _pkg_repository_github_index_order "$1" "$pkg_repository_github_requested" "$pkg_repository_github_requested" >/dev/null
      pkg_repository_github_index_status=$?
      case "$pkg_repository_github_index_status" in
        0)
          printf -- '%s\n' "$pkg_repository_github_requested"
          return 0
          ;;
        3) : ;;
        *) return 1 ;;
      esac
    fi
  fi

  pkg_repository_github_body="$(_pkg_repository_github_get "$pkg_repository_github_path" pkg_repository_resolve_version)" || return 1
  json_object_read \
    tag_name pkg_repository_github_tag_token \
    draft pkg_repository_github_draft_token \
    prerelease pkg_repository_github_prerelease_token \
    created_at pkg_repository_github_created_token <<EOF_JSON
$pkg_repository_github_body
EOF_JSON
  [ "$?" -eq 0 ] || return 1

  _pkg_repository_github_validate_release_tokens \
    "$pkg_repository_github_tag_token" \
    "$pkg_repository_github_draft_token" \
    "$pkg_repository_github_prerelease_token" \
    "$pkg_repository_github_created_token" || return 1

  if [ -n "$pkg_repository_github_requested" ]
  then
    [ "$pkg_repository_github_release_tag" = "$pkg_repository_github_requested" ] || return 1
  fi

  printf -- '%s\n' "$pkg_repository_github_release_tag"
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_github_repository_dir=$1
  pkg_repository_github_range_dir=$2
  pkg_repository_github_requested=$3

  _pkg_repository_github_validate_repository "$pkg_repository_github_repository_dir" || return 1
  _pkg_repository_github_validate_version "$pkg_repository_github_requested" || return 1
  [ -d "$pkg_repository_github_range_dir" ] && [ ! -L "$pkg_repository_github_range_dir" ] || return 1

  pkg_repository_github_archive_regex="$(_pkg_repository_github_scalar "$pkg_repository_github_range_dir/archive_regex")" || return 1
  LC_ALL=C command -p -- awk -v expression="$pkg_repository_github_archive_regex" 'BEGIN { value=""; value ~ expression; exit 0 }' || return 1

  if [ -e "$pkg_repository_github_range_dir/digest_regex" ] || [ -L "$pkg_repository_github_range_dir/digest_regex" ]
  then
    return 1
  fi

  pkg_repository_github_have_download_override=0
  pkg_repository_github_have_metadata_override=0
  if [ -e "$pkg_repository_github_repository_dir/download" ] || [ -L "$pkg_repository_github_repository_dir/download" ]
  then
    pkg_repository_github_have_download_override=1
  fi
  if [ -e "$pkg_repository_github_repository_dir/metadata" ] || [ -L "$pkg_repository_github_repository_dir/metadata" ]
  then
    pkg_repository_github_have_metadata_override=1
  fi

  pkg_repository_github_digest_type=
  if [ -e "$pkg_repository_github_range_dir/digest_type" ] || [ -L "$pkg_repository_github_range_dir/digest_type" ]
  then
    pkg_repository_github_digest_type="$(_pkg_repository_github_scalar "$pkg_repository_github_range_dir/digest_type")" || return 1
  fi
  if [ "$pkg_repository_github_have_metadata_override" -eq 1 ]
  then
    [ -n "$pkg_repository_github_digest_type" ] || return 1
  elif [ -n "$pkg_repository_github_digest_type" ]
  then
    [ "$pkg_repository_github_digest_type" = sha256 ] || return 1
  fi

  pkg_repository_github_body="$(_pkg_repository_github_get "/releases/tags/$pkg_repository_github_requested" pkg_repository_resolve_artifact)" || return 1
  json_object_read \
    tag_name pkg_repository_github_tag_token \
    draft pkg_repository_github_draft_token \
    prerelease pkg_repository_github_prerelease_token \
    created_at pkg_repository_github_created_token <<EOF_JSON
$pkg_repository_github_body
EOF_JSON
  [ "$?" -eq 0 ] || return 1

  _pkg_repository_github_validate_release_tokens \
    "$pkg_repository_github_tag_token" \
    "$pkg_repository_github_draft_token" \
    "$pkg_repository_github_prerelease_token" \
    "$pkg_repository_github_created_token" || return 1
  [ "$pkg_repository_github_release_tag" = "$pkg_repository_github_requested" ] || return 1

  pkg_repository_github_asset_name=
  pkg_repository_github_asset_size=
  pkg_repository_github_asset_digest_token=
  pkg_repository_github_asset_url=

  if [ "$pkg_repository_github_have_download_override" -eq 0 ] || [ "$pkg_repository_github_have_metadata_override" -eq 0 ]
  then
    pkg_repository_github_assets="$(printf '%s\n' "$pkg_repository_github_body" | json_object_array_object_fields assets name state size digest browser_download_url)" || return 1
    [ -n "$pkg_repository_github_assets" ] || return 1

    pkg_repository_github_tab="$(printf '\t')"
    pkg_repository_github_selected="$(printf '%s\n' "$pkg_repository_github_assets" | \
      LC_ALL=C command -p -- awk -F "$pkg_repository_github_tab" -v expression="$pkg_repository_github_archive_regex" '
function fail() { exit 1 }
{
  if (NF != 5) fail()
  if ($1 !~ /^s:/) fail()
  name=$1
  sub(/^s:/, "", name)
  if (name ~ expression) {
    count++
    selected=$0
  }
}
END {
  if (count != 1) exit 1
  print selected
}
')" || return 1

    IFS="$pkg_repository_github_tab" read -r \
      pkg_repository_github_name_token \
      pkg_repository_github_state_token \
      pkg_repository_github_size_token \
      pkg_repository_github_digest_token \
      pkg_repository_github_url_token \
      pkg_repository_github_extra <<EOF_ASSET
$pkg_repository_github_selected
EOF_ASSET
    [ -z "$pkg_repository_github_extra" ] || return 1

    case "$pkg_repository_github_name_token" in
      s:*) pkg_repository_github_asset_name=${pkg_repository_github_name_token#s:};;
      *) return 1;;
    esac
    [ -n "$pkg_repository_github_asset_name" ] || return 1
    [ "$pkg_repository_github_state_token" = s:uploaded ] || return 1

    case "$pkg_repository_github_size_token" in
      n:*) pkg_repository_github_asset_size=${pkg_repository_github_size_token#n:};;
      *) return 1;;
    esac
    case "$pkg_repository_github_asset_size" in
      ''|*[!0-9]*) return 1;;
    esac
    [ "$pkg_repository_github_asset_size" -gt 0 ] || return 1

    case "$pkg_repository_github_url_token" in
      s:https://*) pkg_repository_github_asset_url=${pkg_repository_github_url_token#s:};;
      *) return 1;;
    esac
  fi

  if [ "$pkg_repository_github_have_download_override" -eq 1 ]
  then
    pkg_repository_github_download="$(pkg_repository_artifact_download_resolve "$pkg_repository_github_repository_dir/download" "$pkg_repository_github_requested")" || return 1
    pkg_repository_github_tab="$(printf '\t')"
    IFS="$pkg_repository_github_tab" read -r \
      pkg_repository_github_name \
      pkg_repository_github_url \
      pkg_repository_github_extra <<EOF_DOWNLOAD
$pkg_repository_github_download
EOF_DOWNLOAD
    [ -z "$pkg_repository_github_extra" ] || return 1
    [ -n "$pkg_repository_github_name" ] && [ -n "$pkg_repository_github_url" ] || return 1
  else
    pkg_repository_github_name=$pkg_repository_github_asset_name
    pkg_repository_github_url=$pkg_repository_github_asset_url
  fi

  LC_ALL=C command -p -- awk \
    -v value="$pkg_repository_github_name" \
    -v expression="$pkg_repository_github_archive_regex" \
    'BEGIN { exit(value ~ expression ? 0 : 1) }' || return 1

  if [ "$pkg_repository_github_have_metadata_override" -eq 1 ]
  then
    pkg_repository_github_metadata="$(pkg_repository_artifact_metadata_resolve \
      "$pkg_repository_github_repository_dir/metadata" \
      "$pkg_repository_github_digest_type" \
      "$pkg_repository_github_requested" \
      "$pkg_repository_github_name" \
      "$pkg_repository_github_url")" || return 1
    pkg_repository_github_tab="$(printf '\t')"
    IFS="$pkg_repository_github_tab" read -r \
      pkg_repository_github_size \
      pkg_repository_github_digest \
      pkg_repository_github_extra <<EOF_METADATA
$pkg_repository_github_metadata
EOF_METADATA
    [ -z "$pkg_repository_github_extra" ] || return 1
    [ -n "$pkg_repository_github_size" ] && [ -n "$pkg_repository_github_digest" ] || return 1
  else
    [ "$pkg_repository_github_name" = "$pkg_repository_github_asset_name" ] || return 1
    pkg_repository_github_size=$pkg_repository_github_asset_size
    pkg_repository_github_digest=
    if [ -n "$pkg_repository_github_digest_type" ]
    then
      case "$pkg_repository_github_digest_token" in
        s:sha256:*) pkg_repository_github_digest=${pkg_repository_github_digest_token#s:sha256:};;
        *) return 1;;
      esac
      [ "${#pkg_repository_github_digest}" -eq 64 ] || return 1
      case "$pkg_repository_github_digest" in
        *[!0-9A-Fa-f]*) return 1;;
      esac
      pkg_repository_github_digest="$(printf '%s\n' "$pkg_repository_github_digest" | command -p -- tr 'A-F' 'a-f')" || return 1
      pkg_repository_github_digest="sha256:$pkg_repository_github_digest"
    fi
  fi

  printf 'name=%s\n' "$pkg_repository_github_name"
  printf 'url=%s\n' "$pkg_repository_github_url"
  printf 'size=%s\n' "$pkg_repository_github_size"
  if [ -n "$pkg_repository_github_digest" ]
  then
    printf 'digest=%s\n' "$pkg_repository_github_digest"
  fi
)

