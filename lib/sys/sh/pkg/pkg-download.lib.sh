_pkg_download_error()
{
  log error execution execution-failed operation pkg-download reason "$1"
}

pkg_download()
(
  [ "$#" -eq 1 ] || return 2
  [ -d "$1" ] && [ ! -L "$1" ] || return 1

  readpathce pkg_download_staging_dir "$1" || return 1
  [ -d "$pkg_download_staging_dir" ] || return 1

  pkg_download_name=
  pkg_download_urls=
  pkg_download_size=
  pkg_download_digest_algorithm=
  pkg_download_digest=
  pkg_download_seen_name=0
  pkg_download_seen_url=0
  pkg_download_seen_size=0
  pkg_download_seen_digest=0
  pkg_download_lf='
'
  pkg_download_cr="$(printf '\r')"
  pkg_download_tab="$(printf '\t')"

  while :
  do
    pkg_download_line=
    IFS= read -r pkg_download_line
    pkg_download_read_status=$?
    if [ "$pkg_download_read_status" -ne 0 ]
    then
      [ -z "$pkg_download_line" ] || { _pkg_download_error descriptor-not-lf-terminated; return 1; }
      break
    fi

    case "$pkg_download_line" in
      *=*) :;;
      *) _pkg_download_error descriptor-invalid; return 1;;
    esac

    pkg_download_key=${pkg_download_line%%=*}
    pkg_download_value=${pkg_download_line#*=}
    [ -n "$pkg_download_value" ] || { _pkg_download_error descriptor-invalid; return 1; }
    case "$pkg_download_value" in
      *"$pkg_download_cr"*|*"$pkg_download_tab"*) _pkg_download_error descriptor-invalid; return 1;;
    esac

    case "$pkg_download_key" in
      name)
        [ "$pkg_download_seen_name" -eq 0 ] || { _pkg_download_error descriptor-duplicate-field; return 1; }
        case "$pkg_download_value" in
          .|..|*/*) _pkg_download_error artifact-name-invalid; return 1;;
        esac
        pkg_download_name=$pkg_download_value
        pkg_download_seen_name=1
        ;;
      url)
        case "$pkg_download_value" in
          http://*|https://*) :;;
          *) _pkg_download_error artifact-url-invalid; return 1;;
        esac
        if [ -n "$pkg_download_urls" ]
        then
          pkg_download_urls="$pkg_download_urls$pkg_download_lf$pkg_download_value"
        else
          pkg_download_urls=$pkg_download_value
        fi
        pkg_download_seen_url=$((pkg_download_seen_url + 1))
        ;;
      size)
        [ "$pkg_download_seen_size" -eq 0 ] || { _pkg_download_error descriptor-duplicate-field; return 1; }
        case "$pkg_download_value" in
          *[!0-9]*|0[0-9]*) _pkg_download_error artifact-size-invalid; return 1;;
          *) :;;
        esac
        pkg_download_size=$pkg_download_value
        pkg_download_seen_size=1
        ;;
      digest)
        [ "$pkg_download_seen_digest" -eq 0 ] || { _pkg_download_error descriptor-duplicate-field; return 1; }
        case "$pkg_download_value" in
          sha256:*)
            pkg_download_digest_algorithm=sha256
            pkg_download_digest=${pkg_download_value#sha256:}
            pkg_download_digest_length=64
            ;;
          sha512:*)
            pkg_download_digest_algorithm=sha512
            pkg_download_digest=${pkg_download_value#sha512:}
            pkg_download_digest_length=128
            ;;
          md5:*)
            pkg_download_digest_algorithm=md5
            pkg_download_digest=${pkg_download_value#md5:}
            pkg_download_digest_length=32
            ;;
          *) _pkg_download_error artifact-digest-invalid; return 1;;
        esac
        [ "${#pkg_download_digest}" -eq "$pkg_download_digest_length" ] || { _pkg_download_error artifact-digest-invalid; return 1; }
        case "$pkg_download_digest" in
          *[!0-9A-Fa-f]*) _pkg_download_error artifact-digest-invalid; return 1;;
        esac
        pkg_download_digest="$(printf -- '%s\n' "$pkg_download_digest" | LC_ALL=C command -p -- awk '{ print tolower($0) }')" || return 1
        pkg_download_seen_digest=1
        ;;
      *)
        _pkg_download_error descriptor-unknown-field
        return 1
        ;;
    esac
  done

  [ "$pkg_download_seen_name" -eq 1 ] && \
  [ "$pkg_download_seen_url" -ge 1 ] && \
  [ "$pkg_download_seen_size" -eq 1 ] || { _pkg_download_error descriptor-missing-field; return 1; }

  pkg_download_target="$pkg_download_staging_dir/$pkg_download_name"
  [ ! -e "$pkg_download_target" ] && [ ! -L "$pkg_download_target" ] || { _pkg_download_error target-exists; return 1; }

  pkg_download_success=0
  pkg_download_failure_reason=transfer-failed
  pkg_download_failure_actual_size=
  pkg_download_failure_actual_digest=

  pkg_download_old_ifs=$IFS
  IFS=$pkg_download_lf
  set -f
  for pkg_download_url in $pkg_download_urls
  do
    command -p -- rm -f -- "$pkg_download_target" 2>/dev/null

    if ! http-fetch -o "$pkg_download_target" -- "$pkg_download_url"
    then
      pkg_download_failure_reason=transfer-failed
      continue
    fi

    pkg_download_actual_size="$(LC_ALL=C command -p -- wc -c < "$pkg_download_target")"
    pkg_download_size_status=$?
    if [ "$pkg_download_size_status" -ne 0 ]
    then
      command -p -- rm -f -- "$pkg_download_target" 2>/dev/null
      pkg_download_failure_reason=size-check-failed
      continue
    fi

    pkg_download_actual_size="$(printf -- '%s\n' "$pkg_download_actual_size" | LC_ALL=C command -p -- awk '{ print $1 }')"
    pkg_download_size_status=$?
    if [ "$pkg_download_size_status" -ne 0 ]
    then
      command -p -- rm -f -- "$pkg_download_target" 2>/dev/null
      pkg_download_failure_reason=size-check-failed
      continue
    fi

    if [ "$pkg_download_actual_size" != "$pkg_download_size" ]
    then
      pkg_download_failure_reason=size-mismatch
      pkg_download_failure_actual_size=$pkg_download_actual_size
      command -p -- rm -f -- "$pkg_download_target" 2>/dev/null
      continue
    fi

    if [ "$pkg_download_seen_digest" -eq 1 ]
    then
      pkg_download_actual_digest="$(digest -a "$pkg_download_digest_algorithm" -- "$pkg_download_target")"
      pkg_download_digest_status=$?
      if [ "$pkg_download_digest_status" -ne 0 ]
      then
        command -p -- rm -f -- "$pkg_download_target" 2>/dev/null
        pkg_download_failure_reason=digest-check-failed
        continue
      fi

      if [ "$pkg_download_actual_digest" != "$pkg_download_digest" ]
      then
        pkg_download_failure_reason=digest-mismatch
        pkg_download_failure_actual_digest=$pkg_download_actual_digest
        command -p -- rm -f -- "$pkg_download_target" 2>/dev/null
        continue
      fi
    fi

    pkg_download_success=1
    break
  done
  set +f
  IFS=$pkg_download_old_ifs

  if [ "$pkg_download_success" -ne 1 ]
  then
    command -p -- rm -f -- "$pkg_download_target" 2>/dev/null
    case "$pkg_download_failure_reason" in
      size-mismatch)
        log error execution execution-failed operation pkg-download reason size-mismatch expected-size "$pkg_download_size" actual-size "$pkg_download_failure_actual_size"
        ;;
      digest-mismatch)
        log error execution execution-failed operation pkg-download reason digest-mismatch expected-digest "$pkg_download_digest_algorithm:$pkg_download_digest" actual-digest "$pkg_download_digest_algorithm:$pkg_download_failure_actual_digest"
        ;;
      *)
        _pkg_download_error "$pkg_download_failure_reason"
        ;;
    esac
    return 1
  fi

  printf -- '%s\n' "$pkg_download_target"
)