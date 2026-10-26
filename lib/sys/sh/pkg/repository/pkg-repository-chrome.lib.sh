_pkg_repository_chrome_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_chrome_scalar_file="$1"

  [ -f "$pkg_repository_chrome_scalar_file" ] && \
  [ ! -L "$pkg_repository_chrome_scalar_file" ] && \
  [ ! -x "$pkg_repository_chrome_scalar_file" ] || return 1

  pkg_repository_chrome_scalar_value=
  pkg_repository_chrome_scalar_extra=
  {
    IFS= read -r pkg_repository_chrome_scalar_value || return 1
    IFS= read -r pkg_repository_chrome_scalar_extra
    pkg_repository_chrome_scalar_second_status=$?
  } < "$pkg_repository_chrome_scalar_file"

  [ "$pkg_repository_chrome_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_chrome_scalar_extra" ] || return 1
  [ -n "$pkg_repository_chrome_scalar_value" ] || return 1

  pkg_repository_chrome_scalar_cr="$(printf '\r')"
  case "$pkg_repository_chrome_scalar_value" in
    *"$pkg_repository_chrome_scalar_cr"*) return 1;;
  esac

  pkg_repository_chrome_scalar_actual="$(command -p -- wc -c < "$pkg_repository_chrome_scalar_file")" || return 1
  pkg_repository_chrome_scalar_expected="$(printf '%s\n' "$pkg_repository_chrome_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_chrome_scalar_actual" = "$pkg_repository_chrome_scalar_expected" ] || return 1

  printf -- '%s\n' "$pkg_repository_chrome_scalar_value"
}

_pkg_repository_chrome_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_chrome_repository_dir="$1"

  [ -d "$pkg_repository_chrome_repository_dir" ] && [ ! -L "$pkg_repository_chrome_repository_dir" ] || return 1

  for pkg_repository_chrome_repository_item in \
    "$pkg_repository_chrome_repository_dir"/* \
    "$pkg_repository_chrome_repository_dir"/.[!.]* \
    "$pkg_repository_chrome_repository_dir"/..?*
  do
    [ -e "$pkg_repository_chrome_repository_item" ] || [ -L "$pkg_repository_chrome_repository_item" ] || continue
    pkg_repository_chrome_repository_name=${pkg_repository_chrome_repository_item##*/}
    case "$pkg_repository_chrome_repository_name" in
      type) :;;
      *) return 1;;
    esac
  done

  pkg_repository_chrome_type="$(_pkg_repository_chrome_scalar "$pkg_repository_chrome_repository_dir/type")" || return 1
  [ "$pkg_repository_chrome_type" = chrome ] || return 1
}

_pkg_repository_chrome_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  LC_ALL=C command -p -- awk -v value="$1" 'BEGIN {
    count=split(value, parts, /[.-]/)
    if (count != 5) exit 1
    for (i=1; i<=5; i++) {
      if (parts[i] !~ /^[0-9]+$/) exit 1
      if (length(parts[i]) > 1 && substr(parts[i], 1, 1) == "0") exit 1
    }
    exit 0
  }'
}

_pkg_repository_chrome_packages_get()
{
  [ "$#" -eq 0 ] || return 2
  http-fetch -- 'https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages'
}

_pkg_repository_chrome_records()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_chrome_validate_repository "$1" || return 1

  pkg_repository_chrome_body="$(_pkg_repository_chrome_packages_get)" || return 1
  printf '%s\n' "$pkg_repository_chrome_body" | LC_ALL=C command -p -- awk '
function reset() {
  package=""; version=""; architecture=""; filename=""; size=""; sha256=""
  package_count=0; version_count=0; architecture_count=0; filename_count=0; size_count=0; sha256_count=0
  target_seen=0
}
function fail() {
  failed=1
  exit 1
}
function emit( expected) {
  if (!target_seen) {
    reset()
    return
  }

  if (package_count != 1 || version_count != 1 || architecture_count != 1 || filename_count != 1 || size_count != 1 || sha256_count != 1) fail()
  if (package != "google-chrome-stable" || architecture != "amd64") fail()
  version_count_parts=split(version, version_parts, /[.-]/)
  if (version_count_parts != 5) fail()
  for (version_index=1; version_index<=5; version_index++) {
    if (version_parts[version_index] !~ /^[0-9]+$/) fail()
    if (length(version_parts[version_index]) > 1 && substr(version_parts[version_index], 1, 1) == "0") fail()
  }
  expected="pool/main/g/google-chrome-stable/google-chrome-stable_" version "_amd64.deb"
  if (filename != expected) fail()
  if (size !~ /^[0-9]+$/ || size == "0") fail()
  if (length(sha256) != 64 || sha256 !~ /^[0-9A-Fa-f]+$/) fail()
  if (seen_version[version]) fail()
  seen_version[version]=1
  print version "\t" filename "\t" size "\t" tolower(sha256)
  reset()
}
BEGIN { reset() }
{
  if (index($0, "\r") != 0) fail()
  if ($0 == "") {
    emit()
    next
  }
  if (index($0, "Package: ") == 1) {
    package_count++
    package=substr($0, 10)
    if (package == "google-chrome-stable") target_seen=1
    next
  }
  if (index($0, "Version: ") == 1) {
    version_count++
    version=substr($0, 10)
    next
  }
  if (index($0, "Architecture: ") == 1) {
    architecture_count++
    architecture=substr($0, 15)
    next
  }
  if (index($0, "Filename: ") == 1) {
    filename_count++
    filename=substr($0, 11)
    next
  }
  if (index($0, "Size: ") == 1) {
    size_count++
    size=substr($0, 7)
    next
  }
  if (index($0, "SHA256: ") == 1) {
    sha256_count++
    sha256=substr($0, 9)
    next
  }
}
END {
  if (!failed) emit()
}
'
)

_pkg_repository_chrome_compare_raw()
{
  [ "$#" -eq 2 ] || return 2
  _pkg_repository_chrome_validate_version "$1" || return 1
  _pkg_repository_chrome_validate_version "$2" || return 1

  LC_ALL=C command -p -- awk -v left="$1" -v right="$2" '
function normalize(value) {
  sub(/^0+/, "", value)
  if (value == "") value="0"
  return value
}
function number_compare(a, b) {
  a=normalize(a); b=normalize(b)
  if (length(a) < length(b)) return -1
  if (length(a) > length(b)) return 1
  if (("x" a) < ("x" b)) return -1
  if (("x" a) > ("x" b)) return 1
  return 0
}
BEGIN {
  left_count=split(left, left_parts, /[.-]/)
  right_count=split(right, right_parts, /[.-]/)
  if (left_count != 5 || right_count != 5) exit 1
  for (i=1; i<=5; i++) {
    comparison=number_compare(left_parts[i], right_parts[i])
    if (comparison != 0) {
      print comparison
      exit 0
    }
  }
  print 0
}
'
}

_pkg_repository_chrome_unavailable()
{
  [ "$#" -eq 1 ] || return 2
  log error execution execution-failed \
    operation pkg \
    repository chrome \
    reason upstream-version-unavailable \
    version "$1" || :
  return 1
}

_pkg_repository_chrome_record_set()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_chrome_record_source="$1"
  pkg_repository_chrome_record_requested="$2"
  _pkg_repository_chrome_validate_version "$pkg_repository_chrome_record_requested" || return 1

  pkg_repository_chrome_record_found=0
  pkg_repository_chrome_record_version=
  pkg_repository_chrome_record_filename=
  pkg_repository_chrome_record_size=
  pkg_repository_chrome_record_sha256=
  pkg_repository_chrome_tab="$(printf '\t')"

  while IFS="$pkg_repository_chrome_tab" read -r \
    pkg_repository_chrome_record_candidate_version \
    pkg_repository_chrome_record_candidate_filename \
    pkg_repository_chrome_record_candidate_size \
    pkg_repository_chrome_record_candidate_sha256 \
    pkg_repository_chrome_record_extra
  do
    [ -z "$pkg_repository_chrome_record_extra" ] || return 1
    [ -n "$pkg_repository_chrome_record_candidate_version" ] || continue
    if [ "$pkg_repository_chrome_record_candidate_version" = "$pkg_repository_chrome_record_requested" ]
    then
      pkg_repository_chrome_record_found=$((pkg_repository_chrome_record_found + 1))
      pkg_repository_chrome_record_version=$pkg_repository_chrome_record_candidate_version
      pkg_repository_chrome_record_filename=$pkg_repository_chrome_record_candidate_filename
      pkg_repository_chrome_record_size=$pkg_repository_chrome_record_candidate_size
      pkg_repository_chrome_record_sha256=$pkg_repository_chrome_record_candidate_sha256
    fi
  done <<EOF_RECORDS
$pkg_repository_chrome_record_source
EOF_RECORDS

  [ "$pkg_repository_chrome_record_found" -eq 1 ] || _pkg_repository_chrome_unavailable "$pkg_repository_chrome_record_requested"
}

_pkg_repository_chrome_sorted_versions()
{
  [ "$#" -eq 1 ] || return 2
  printf '%s\n' "$1" | LC_ALL=C command -p -- awk -F '\t' '
function normalize(value) {
  sub(/^0+/, "", value)
  if (value == "") value="0"
  return value
}
function number_compare(a, b) {
  a=normalize(a); b=normalize(b)
  if (length(a) < length(b)) return -1
  if (length(a) > length(b)) return 1
  if (("x" a) < ("x" b)) return -1
  if (("x" a) > ("x" b)) return 1
  return 0
}
function version_compare(a, b, left_parts, right_parts, left_count, right_count, i, comparison) {
  left_count=split(a, left_parts, /[.-]/)
  right_count=split(b, right_parts, /[.-]/)
  if (left_count != 5 || right_count != 5) return 2
  for (i=1; i<=5; i++) {
    comparison=number_compare(left_parts[i], right_parts[i])
    if (comparison != 0) return comparison
  }
  return 0
}
NF == 0 { next }
NF != 4 { exit 1 }
{
  versions[++count]=$1
}
END {
  for (i=1; i<=count; i++) {
    for (j=i+1; j<=count; j++) {
      comparison=version_compare(versions[i], versions[j])
      if (comparison == 2) exit 1
      if (comparison > 0) {
        swap=versions[i]
        versions[i]=versions[j]
        versions[j]=swap
      }
    }
  }
  for (i=1; i<=count; i++) print versions[i]
}
'
}

pkg_repository_list_versions()
(
  [ "$#" -eq 1 ] || return 2
  pkg_repository_chrome_records="$(_pkg_repository_chrome_records "$1")" || return 1
  [ -n "$pkg_repository_chrome_records" ] || return 0
  _pkg_repository_chrome_sorted_versions "$pkg_repository_chrome_records"
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_chrome_validate_repository "$1" || return 1
  _pkg_repository_chrome_validate_version "$2" || return 1
  _pkg_repository_chrome_validate_version "$3" || return 1
  _pkg_repository_chrome_compare_raw "$2" "$3"
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  _pkg_repository_chrome_validate_repository "$1" || return 1
  pkg_repository_chrome_records="$(_pkg_repository_chrome_records "$1")" || return 1
  [ -n "$pkg_repository_chrome_records" ] || return 1

  if [ "$#" -eq 2 ]
  then
    _pkg_repository_chrome_record_set "$pkg_repository_chrome_records" "$2" || return 1
    printf -- '%s\n' "$pkg_repository_chrome_record_version"
    return 0
  fi

  pkg_repository_chrome_versions="$(_pkg_repository_chrome_sorted_versions "$pkg_repository_chrome_records")" || return 1
  pkg_repository_chrome_latest="$(printf '%s\n' "$pkg_repository_chrome_versions" | command -p -- tail -n 1)" || return 1
  [ -n "$pkg_repository_chrome_latest" ] || return 1
  printf -- '%s\n' "$pkg_repository_chrome_latest"
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_chrome_validate_repository "$1" || return 1
  pkg_repository_chrome_range_dir="$2"
  pkg_repository_chrome_requested="$3"

  _pkg_repository_chrome_validate_version "$pkg_repository_chrome_requested" || return 1
  [ -d "$pkg_repository_chrome_range_dir" ] && [ ! -L "$pkg_repository_chrome_range_dir" ] || return 1

  pkg_repository_chrome_archive_regex="$(_pkg_repository_chrome_scalar "$pkg_repository_chrome_range_dir/archive_regex")" || return 1
  LC_ALL=C command -p -- awk -v expression="$pkg_repository_chrome_archive_regex" 'BEGIN { value=""; value ~ expression; exit 0 }' || return 1

  if [ -e "$pkg_repository_chrome_range_dir/digest_regex" ] || [ -L "$pkg_repository_chrome_range_dir/digest_regex" ]
  then
    return 1
  fi

  pkg_repository_chrome_digest_type="$(_pkg_repository_chrome_scalar "$pkg_repository_chrome_range_dir/digest_type")" || return 1
  [ "$pkg_repository_chrome_digest_type" = sha256 ] || return 1

  pkg_repository_chrome_records="$(_pkg_repository_chrome_records "$1")" || return 1
  _pkg_repository_chrome_record_set "$pkg_repository_chrome_records" "$pkg_repository_chrome_requested" || return 1

  pkg_repository_chrome_name=${pkg_repository_chrome_record_filename##*/}
  [ -n "$pkg_repository_chrome_name" ] || return 1
  printf '%s\n' "$pkg_repository_chrome_name" | LC_ALL=C command -p -- awk -v expression="$pkg_repository_chrome_archive_regex" 'BEGIN {
    if ((getline value) != 1) exit 1
    if (value ~ expression) exit 0
    exit 1
  }' || return 1

  pkg_repository_chrome_url="https://dl.google.com/linux/chrome/deb/$pkg_repository_chrome_record_filename"
  printf -- 'name=%s\n' "$pkg_repository_chrome_name"
  printf -- 'url=%s\n' "$pkg_repository_chrome_url"
  printf -- 'size=%s\n' "$pkg_repository_chrome_record_size"
  printf -- 'digest=sha256:%s\n' "$pkg_repository_chrome_record_sha256"
)
