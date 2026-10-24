_pkg_repository_artifact_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_artifact_scalar_file=$1
  [ -f "$pkg_repository_artifact_scalar_file" ] &&
  [ ! -L "$pkg_repository_artifact_scalar_file" ] &&
  [ -r "$pkg_repository_artifact_scalar_file" ] &&
  [ ! -x "$pkg_repository_artifact_scalar_file" ] || return 1
  pkg_repository_artifact_scalar_value=
  pkg_repository_artifact_scalar_extra=
  {
    IFS= read -r pkg_repository_artifact_scalar_value || return 1
    IFS= read -r pkg_repository_artifact_scalar_extra
    pkg_repository_artifact_scalar_second_status=$?
  } < "$pkg_repository_artifact_scalar_file"
  [ "$pkg_repository_artifact_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_artifact_scalar_extra" ] && [ -n "$pkg_repository_artifact_scalar_value" ] || return 1
  pkg_repository_artifact_scalar_cr="$(printf '\r')"
  case "$pkg_repository_artifact_scalar_value" in *"$pkg_repository_artifact_scalar_cr"*) return 1;; esac
  pkg_repository_artifact_scalar_actual="$(command -p -- wc -c < "$pkg_repository_artifact_scalar_file")" || return 1
  pkg_repository_artifact_scalar_expected="$(printf '%s\n' "$pkg_repository_artifact_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_artifact_scalar_actual" = "$pkg_repository_artifact_scalar_expected" ] || return 1
  printf '%s\n' "$pkg_repository_artifact_scalar_value"
}

_pkg_repository_artifact_template_validate()
{
  [ "$#" -eq 2 ] || return 2
  printf '%s\n' "$1" | LC_ALL=C command -p -- awk -v mode="$2" '
{
  value=$0
  while ((start=index(value, "{")) != 0) {
    rest=substr(value, start)
    if (index(rest, "{version}") == 1) {
      value=substr(rest, 10)
      continue
    }
    if (mode == "url" && index(rest, "{name}") == 1) {
      value=substr(rest, 7)
      continue
    }
    exit 1
  }
  if (index(value, "}") != 0) exit 1
}
'
}

_pkg_repository_artifact_template_expand()
{
  [ "$#" -eq 4 ] || return 2
  _pkg_repository_artifact_template_validate "$1" "$4" || return 1
  printf '%s\n' "$1" | LC_ALL=C command -p -- awk -v version="$2" -v name="$3" -v mode="$4" '
{
  value=$0
  output=""
  while ((start=index(value, "{")) != 0) {
    output=output substr(value, 1, start-1)
    rest=substr(value, start)
    if (index(rest, "{version}") == 1) {
      output=output version
      value=substr(rest, 10)
      continue
    }
    if (mode == "url" && index(rest, "{name}") == 1) {
      output=output name
      value=substr(rest, 7)
      continue
    }
    exit 1
  }
  if (index(value, "}") != 0) exit 1
  print output value
}
'
}

_pkg_repository_artifact_digest_length()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    md5) printf '%s\n' 32;;
    sha256) printf '%s\n' 64;;
    sha512) printf '%s\n' 128;;
    *) return 1;;
  esac
}

_pkg_repository_artifact_digest_normalize()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_artifact_digest_length="$(_pkg_repository_artifact_digest_length "$1")" || return 1
  [ "${#2}" -eq "$pkg_repository_artifact_digest_length" ] || return 1
  case "$2" in *[!0-9A-Fa-f]*) return 1;; esac
  printf '%s\n' "$2" | command -p -- tr 'A-F' 'a-f'
}

_pkg_repository_artifact_url_validate()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in https://*) :;; *) return 1;; esac
  case "$1" in *' '*|*"$(printf '\t')"*) return 1;; esac
}

_pkg_repository_artifact_download_validate()
(
  [ "$#" -eq 1 ] || return 2
  pkg_repository_artifact_download_dir=$1
  [ -d "$pkg_repository_artifact_download_dir" ] && [ ! -L "$pkg_repository_artifact_download_dir" ] || return 1
  for pkg_repository_artifact_item in \
    "$pkg_repository_artifact_download_dir"/* \
    "$pkg_repository_artifact_download_dir"/.[!.]* \
    "$pkg_repository_artifact_download_dir"/..?*
  do
    [ -e "$pkg_repository_artifact_item" ] || [ -L "$pkg_repository_artifact_item" ] || continue
    case "${pkg_repository_artifact_item##*/}" in type|name-template|url-template) :;; *) return 1;; esac
  done
  [ "$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_download_dir/type")" = template-url ] || return 1
  pkg_repository_artifact_name_template="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_download_dir/name-template")" || return 1
  pkg_repository_artifact_url_template="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_download_dir/url-template")" || return 1
  _pkg_repository_artifact_template_validate "$pkg_repository_artifact_name_template" name || return 1
  _pkg_repository_artifact_template_validate "$pkg_repository_artifact_url_template" url
)

_pkg_repository_artifact_metadata_validate()
(
  [ "$#" -eq 1 ] || return 2
  pkg_repository_artifact_metadata_dir=$1
  [ -d "$pkg_repository_artifact_metadata_dir" ] && [ ! -L "$pkg_repository_artifact_metadata_dir" ] || return 1
  pkg_repository_artifact_metadata_type="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/type")" || return 1

  for pkg_repository_artifact_item in \
    "$pkg_repository_artifact_metadata_dir"/* \
    "$pkg_repository_artifact_metadata_dir"/.[!.]* \
    "$pkg_repository_artifact_metadata_dir"/..?*
  do
    [ -e "$pkg_repository_artifact_item" ] || [ -L "$pkg_repository_artifact_item" ] || continue
    pkg_repository_artifact_name=${pkg_repository_artifact_item##*/}
    case "$pkg_repository_artifact_metadata_type" in
      checksum-sidecar)
        case "$pkg_repository_artifact_name" in type|url-template|record-format) :;; *) return 1;; esac
        ;;
      checksum-manifest)
        case "$pkg_repository_artifact_name" in type|url-template) :;; *) return 1;; esac
        ;;
      sourceforge-rss)
        case "$pkg_repository_artifact_name" in type|project|path-template) :;; *) return 1;; esac
        ;;
      *) return 1;;
    esac
  done

  case "$pkg_repository_artifact_metadata_type" in
    checksum-sidecar)
      pkg_repository_artifact_url_template="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/url-template")" || return 1
      _pkg_repository_artifact_template_validate "$pkg_repository_artifact_url_template" url || return 1
      pkg_repository_artifact_record_format="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/record-format")" || return 1
      case "$pkg_repository_artifact_record_format" in digest-name|digest-only) :;; *) return 1;; esac
      ;;
    checksum-manifest)
      pkg_repository_artifact_url_template="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/url-template")" || return 1
      _pkg_repository_artifact_template_validate "$pkg_repository_artifact_url_template" url || return 1
      ;;
    sourceforge-rss)
      pkg_repository_artifact_project="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/project")" || return 1
      case "$pkg_repository_artifact_project" in ''|*[!A-Za-z0-9._-]*) return 1;; esac
      pkg_repository_artifact_path_template="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/path-template")" || return 1
      case "$pkg_repository_artifact_path_template" in /*) :;; *) return 1;; esac
      _pkg_repository_artifact_template_validate "$pkg_repository_artifact_path_template" path || return 1
      ;;
  esac
)

pkg_repository_artifact_overrides_validate()
{
  [ "$#" -eq 1 ] || return 2
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  if [ -e "$1/download" ] || [ -L "$1/download" ]
  then
    _pkg_repository_artifact_download_validate "$1/download" || return 1
  fi
  if [ -e "$1/metadata" ] || [ -L "$1/metadata" ]
  then
    _pkg_repository_artifact_metadata_validate "$1/metadata" || return 1
  fi
}

pkg_repository_artifact_download_template_url()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_artifact_name_template=$1
  pkg_repository_artifact_url_template=$2
  pkg_repository_artifact_version=$3

  _pkg_repository_artifact_template_validate "$pkg_repository_artifact_name_template" name || return 1
  _pkg_repository_artifact_template_validate "$pkg_repository_artifact_url_template" url || return 1
  pkg_repository_artifact_name="$(_pkg_repository_artifact_template_expand "$pkg_repository_artifact_name_template" "$pkg_repository_artifact_version" '' name)" || return 1
  case "$pkg_repository_artifact_name" in ''|.|..|*/*) return 1;; esac
  pkg_repository_artifact_url="$(_pkg_repository_artifact_template_expand "$pkg_repository_artifact_url_template" "$pkg_repository_artifact_version" "$pkg_repository_artifact_name" url)" || return 1
  _pkg_repository_artifact_url_validate "$pkg_repository_artifact_url" || return 1
  printf '%s\t%s\n' "$pkg_repository_artifact_name" "$pkg_repository_artifact_url"
)

pkg_repository_artifact_download_resolve()
(
  [ "$#" -eq 2 ] || return 2
  _pkg_repository_artifact_download_validate "$1" || return 1
  pkg_repository_artifact_name_template="$(_pkg_repository_artifact_scalar "$1/name-template")" || return 1
  pkg_repository_artifact_url_template="$(_pkg_repository_artifact_scalar "$1/url-template")" || return 1
  pkg_repository_artifact_download_template_url \
    "$pkg_repository_artifact_name_template" \
    "$pkg_repository_artifact_url_template" \
    "$2"
)

_pkg_repository_artifact_size()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_artifact_size="$(http-fetch -l -- "$1")" || return 1
  case "$pkg_repository_artifact_size" in ''|*[!0-9]*|0[0-9]*) return 1;; esac
  [ "$pkg_repository_artifact_size" -gt 0 ] || return 1
  printf '%s\n' "$pkg_repository_artifact_size"
}

pkg_repository_artifact_metadata_checksum_sidecar()
(
  [ "$#" -eq 5 ] || return 2
  pkg_repository_artifact_metadata_url=$1
  pkg_repository_artifact_record_format=$2
  pkg_repository_artifact_digest_type=$3
  pkg_repository_artifact_name=$4
  pkg_repository_artifact_download_url=$5

  _pkg_repository_artifact_url_validate "$pkg_repository_artifact_metadata_url" || return 1
  _pkg_repository_artifact_digest_length "$pkg_repository_artifact_digest_type" >/dev/null || return 1
  case "$pkg_repository_artifact_record_format" in digest-name|digest-only) :;; *) return 1;; esac
  case "$pkg_repository_artifact_name" in ''|.|..|*/*) return 1;; esac
  _pkg_repository_artifact_url_validate "$pkg_repository_artifact_download_url" || return 1

  pkg_repository_artifact_body="$(http-fetch -- "$pkg_repository_artifact_metadata_url")" || return 1
  pkg_repository_artifact_expected_length="$(_pkg_repository_artifact_digest_length "$pkg_repository_artifact_digest_type")" || return 1
  pkg_repository_artifact_digest="$(printf '%s\n' "$pkg_repository_artifact_body" | LC_ALL=C command -p -- awk \
    -v expected="$pkg_repository_artifact_name" \
    -v digest_length="$pkg_repository_artifact_expected_length" \
    -v record_format="$pkg_repository_artifact_record_format" '
function fail() { exit 1 }
NF == 0 { next }
{
  if (record_format == "digest-only") {
    if (NF != 1) fail()
    digest=$1
  } else if (record_format == "digest-name") {
    if (NF != 2) fail()
    digest=$1
    name=$2
    if (name == "./" expected) name=expected
    if (name != expected) fail()
  } else fail()

  if (length(digest) != digest_length || digest !~ /^[0-9A-Fa-f]+$/) fail()
  count++
  selected=digest
}
END { if (count != 1) exit 1; print selected }
')" || return 1
  pkg_repository_artifact_digest="$(_pkg_repository_artifact_digest_normalize "$pkg_repository_artifact_digest_type" "$pkg_repository_artifact_digest")" || return 1
  pkg_repository_artifact_size="$(_pkg_repository_artifact_size "$pkg_repository_artifact_download_url")" || return 1
  printf '%s\t%s:%s\n' "$pkg_repository_artifact_size" "$pkg_repository_artifact_digest_type" "$pkg_repository_artifact_digest"
)

_pkg_repository_artifact_checksum_manifest()
{
  [ "$#" -eq 4 ] || return 2
  pkg_repository_artifact_body="$(http-fetch -- "$1")" || return 1
  pkg_repository_artifact_expected_length="$(_pkg_repository_artifact_digest_length "$2")" || return 1
  pkg_repository_artifact_digest="$(printf '%s\n' "$pkg_repository_artifact_body" | LC_ALL=C command -p -- awk -v expected="$3" -v digest_length="$pkg_repository_artifact_expected_length" '
function fail() { exit 1 }
NF == 0 { next }
{
  if (NF != 2) fail()
  if ($2 == expected) {
    count++
    if (length($1) != digest_length || $1 !~ /^[0-9A-Fa-f]+$/) fail()
    selected=$1
  }
}
END { if (count != 1) exit 1; print selected }
')" || return 1
  pkg_repository_artifact_digest="$(_pkg_repository_artifact_digest_normalize "$2" "$pkg_repository_artifact_digest")" || return 1
  pkg_repository_artifact_size="$(_pkg_repository_artifact_size "$4")" || return 1
  printf '%s\t%s:%s\n' "$pkg_repository_artifact_size" "$2" "$pkg_repository_artifact_digest"
}

pkg_repository_artifact_metadata_sourceforge_rss()
(
  [ "$#" -eq 6 ] || return 2
  pkg_repository_artifact_project=$1
  pkg_repository_artifact_path_template=$2
  pkg_repository_artifact_digest_type=$3
  pkg_repository_artifact_version=$4
  pkg_repository_artifact_name=$5
  pkg_repository_artifact_download_url=$6

  case "$pkg_repository_artifact_project" in ''|*[!A-Za-z0-9._-]*) return 1;; esac
  case "$pkg_repository_artifact_name" in ''|.|..|*/*) return 1;; esac
  _pkg_repository_artifact_digest_length "$pkg_repository_artifact_digest_type" >/dev/null || return 1
  _pkg_repository_artifact_url_validate "$pkg_repository_artifact_download_url" || return 1
  case "$pkg_repository_artifact_path_template" in /*) :;; *) return 1;; esac
  pkg_repository_artifact_path="$(_pkg_repository_artifact_template_expand "$pkg_repository_artifact_path_template" "$pkg_repository_artifact_version" "$pkg_repository_artifact_name" path)" || return 1
  case "$pkg_repository_artifact_path" in
    /*) :;;
    *) return 1;;
  esac
  case "$pkg_repository_artifact_path" in *[!A-Za-z0-9._~/-]*) return 1;; esac

  pkg_repository_artifact_rss_url="https://sourceforge.net/projects/$pkg_repository_artifact_project/rss?path=$pkg_repository_artifact_path"
  pkg_repository_artifact_body="$(http-fetch -- "$pkg_repository_artifact_rss_url")" || return 1
  pkg_repository_artifact_metadata="$(printf '%s\n' "$pkg_repository_artifact_body" | LC_ALL=C command -p -- awk \
    -v expected_url="$pkg_repository_artifact_download_url" \
    -v algorithm="$pkg_repository_artifact_digest_type" '
{
  source=source $0 "\n"
}
END {
  count=split(source, part, /<media:content/)
  found=0
  for (i=2; i<=count; i++) {
    block=part[i]
    close_pos=index(block, "</media:content>")
    if (!close_pos) {
      if (index(block, "url=\"" expected_url "\"") != 0) exit 1
      continue
    }
    block=substr(block, 1, close_pos-1)
    if (index(block, "url=\"" expected_url "\"") == 0) continue
    found++
    if (found != 1) exit 1

    marker="filesize=\""
    start=index(block, marker)
    if (!start) exit 1
    rest=substr(block, start+length(marker))
    finish=index(rest, "\"")
    if (!finish) exit 1
    size=substr(rest, 1, finish-1)
    if (size !~ /^[1-9][0-9]*$/) exit 1
    if (index(substr(rest, finish+1), marker) != 0) exit 1

    marker="<media:hash algo=\"" algorithm "\">"
    start=index(block, marker)
    if (!start) exit 1
    rest=substr(block, start+length(marker))
    finish=index(rest, "</media:hash>")
    if (!finish) exit 1
    digest=substr(rest, 1, finish-1)
    if (index(substr(rest, finish+length("</media:hash>")), marker) != 0) exit 1
  }
  if (found != 1) exit 1
  printf "%s\t%s\n", size, digest
}
')" || return 1

  pkg_repository_artifact_tab="$(printf '\t')"
  IFS="$pkg_repository_artifact_tab" read -r \
    pkg_repository_artifact_size \
    pkg_repository_artifact_digest \
    pkg_repository_artifact_extra <<EOF_METADATA
$pkg_repository_artifact_metadata
EOF_METADATA
  [ -z "$pkg_repository_artifact_extra" ] || return 1
  case "$pkg_repository_artifact_size" in ''|*[!0-9]*|0[0-9]*) return 1;; esac
  [ "$pkg_repository_artifact_size" -gt 0 ] || return 1
  pkg_repository_artifact_digest="$(_pkg_repository_artifact_digest_normalize "$pkg_repository_artifact_digest_type" "$pkg_repository_artifact_digest")" || return 1
  printf '%s\t%s:%s\n' "$pkg_repository_artifact_size" "$pkg_repository_artifact_digest_type" "$pkg_repository_artifact_digest"
)

pkg_repository_artifact_metadata_resolve()
(
  [ "$#" -eq 5 ] || return 2
  pkg_repository_artifact_metadata_dir=$1
  pkg_repository_artifact_digest_type=$2
  pkg_repository_artifact_version=$3
  pkg_repository_artifact_name=$4
  pkg_repository_artifact_download_url=$5

  _pkg_repository_artifact_metadata_validate "$pkg_repository_artifact_metadata_dir" || return 1
  _pkg_repository_artifact_digest_length "$pkg_repository_artifact_digest_type" >/dev/null || return 1
  _pkg_repository_artifact_url_validate "$pkg_repository_artifact_download_url" || return 1
  pkg_repository_artifact_metadata_type="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/type")" || return 1

  case "$pkg_repository_artifact_metadata_type" in
    checksum-sidecar|checksum-manifest)
      pkg_repository_artifact_url_template="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/url-template")" || return 1
      pkg_repository_artifact_metadata_url="$(_pkg_repository_artifact_template_expand "$pkg_repository_artifact_url_template" "$pkg_repository_artifact_version" "$pkg_repository_artifact_name" url)" || return 1
      _pkg_repository_artifact_url_validate "$pkg_repository_artifact_metadata_url" || return 1
      case "$pkg_repository_artifact_metadata_type" in
        checksum-sidecar)
          pkg_repository_artifact_record_format="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/record-format")" || return 1
          pkg_repository_artifact_metadata_checksum_sidecar \
            "$pkg_repository_artifact_metadata_url" \
            "$pkg_repository_artifact_record_format" \
            "$pkg_repository_artifact_digest_type" \
            "$pkg_repository_artifact_name" \
            "$pkg_repository_artifact_download_url"
          ;;
        checksum-manifest)
          _pkg_repository_artifact_checksum_manifest "$pkg_repository_artifact_metadata_url" "$pkg_repository_artifact_digest_type" "$pkg_repository_artifact_name" "$pkg_repository_artifact_download_url"
          ;;
      esac
      ;;
    sourceforge-rss)
      pkg_repository_artifact_project="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/project")" || return 1
      pkg_repository_artifact_path_template="$(_pkg_repository_artifact_scalar "$pkg_repository_artifact_metadata_dir/path-template")" || return 1
      pkg_repository_artifact_metadata_sourceforge_rss \
        "$pkg_repository_artifact_project" \
        "$pkg_repository_artifact_path_template" \
        "$pkg_repository_artifact_digest_type" \
        "$pkg_repository_artifact_version" \
        "$pkg_repository_artifact_name" \
        "$pkg_repository_artifact_download_url"
      ;;
    *) return 1;;
  esac
)
