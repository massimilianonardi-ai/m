#!/bin/sh

#------------------------------------------------------------------------------

# generates a POSIX compliant random number between 0 and 1 by the use of awk
rand()
{
  echo "" | awk -v rseed=$RANDOM 'BEGIN{srand(rseed);}{print rand(); exit}'
}

#------------------------------------------------------------------------------

# generates a POSIX compliant random number between $1 and $2 by the use of awk
# maximum allowed value for max range is 999999999999999999 (awk limitation)
# randint $min $max
# randint $max - (min=0)
# randint - (min=0, max=255)
randint()
{
  if [ "$#" = "0" ]
  then
    set -- "0" "255"
  elif [ "$#" = "1" ]
  then
    set -- "0" "$1"
  fi

  if [ "$1" -ne "$1" ] || [ "$2" -ne "$2" ]
  then
    exit 1
  fi

  awk -v rseed=$RANDOM "BEGIN{srand(rseed); print int(rand()*($2-$1+1))+$1}"
}

#------------------------------------------------------------------------------

# randh $n
# generates a POSIX compliant random hex string of $n characters (NB each hex digit is represented by 2 ascii characters)
randh()
{
  if [ -z "$1" ] || [ "$1" -ne "$1" ]
  then
    set -- "32"
  fi

  openssl rand -hex "$1"
}

#------------------------------------------------------------------------------

# randstr $n
# generates a POSIX compliant random base64 string of $n characters
rand64()
{
  if [ -z "$1" ] || [ "$1" -ne "$1" ]
  then
    set -- "32"
  fi

  # openssl rand -base64 "$1"
  openssl rand -base64 "$1" | tr -d '\n'; echo ""
}

#------------------------------------------------------------------------------

# randstr $n
# generates a POSIX compliant random string of $n characters
randstr()
{
  if [ -z "$1" ] || [ "$1" -ne "$1" ]
  then
    set -- "32"
  fi

  openssl rand -hex "$1" | openssl enc -A -base64; echo ""
}

#------------------------------------------------------------------------------

# generate random number of specified number of digits.
# NB is not POSIX compliant because uses /dev/urandom and may not guarrantee enough entropy for security uses
randu()
{
  if [ -z "$1" ] || [ "$1" -ne "$1" ]
  then
    set -- "4"
  fi

  tr -dc '[:digit:]' < /dev/urandom | fold -w "$1" | head -n1
  # od -An -N4 -tu4 /dev/urandom | tr -d ' '
  # od -An -N2 -d /dev/urandom
}

#------------------------------------------------------------------------------

# generate random number of specified number of digits.
# NB is not POSIX compliant because uses /dev/random. should guarrantee enough entropy for security uses, but may block
rands()
{
  if [ -z "$1" ] || [ "$1" -ne "$1" ]
  then
    set -- "4"
  fi

  tr -dc '[:digit:]' < /dev/random | fold -w "$1" | head -n1
}

#------------------------------------------------------------------------------

# authenticated password-based encryption envelope
#
# Format version 1:
#
#   ENC1
#   SALT:<16 lowercase hex digits>
#   HMAC:<64 lowercase hex digits>
#   <OpenSSL base64 ciphertext>
#
# The ciphertext is AES-256-CBC encrypted with PBKDF2-HMAC-SHA256 using
# 600000 iterations and OpenSSL's embedded random salt. The envelope payload
# (magic, MAC salt and base64 ciphertext) is authenticated with HMAC-SHA256
# before any plaintext is emitted. The MAC key is independently derived from
# the password with PBKDF2-HMAC-SHA256, the envelope MAC salt and a fixed
# domain-separation prefix.
#
# The Base64 ciphertext is buffered in shell memory. encode and decode do not
# create temporary files; memory use is therefore proportional to ciphertext
# size while plaintext remains streamed directly through OpenSSL.

_enc_password_read()
(
  set +x

  [ "$#" -eq "1" ] || return 2
  [ -r "/dev/tty" ] && [ -w "/dev/tty" ] || return 1

  _enc_tty_settings="$(stty -g < "/dev/tty")" || return 1

  trap 'stty "$_enc_tty_settings" < "/dev/tty" >/dev/null 2>&1' 0
  trap 'exit 1' HUP INT QUIT TERM

  stty -echo < "/dev/tty" || return 1
  printf '%s' "$1" > "/dev/tty" || return 1

  IFS= read -r _enc_password < "/dev/tty"
  _enc_read_status="$?"

  stty "$_enc_tty_settings" < "/dev/tty" || return 1
  printf '\n' > "/dev/tty" || return 1

  [ "$_enc_read_status" -eq "0" ] || return 1

  printf '%s' "$_enc_password"
)

_enc_mac_key()
(
  set +x

  [ "$#" -eq "2" ] || return 2

  [ "${#1}" -eq "16" ] || return 1

  case "$1" in
    *[!0123456789abcdef]*) return 1 ;;
  esac

  _enc_kdf_output="$(
    _ENC_MAC_PASS="ENC1-MAC:$2" \
      openssl enc -aes-256-cbc \
        -pbkdf2 \
        -iter 600000 \
        -md sha256 \
        -S "$1" \
        -P \
        -pass env:_ENC_MAC_PASS
  )" || return 1

  _enc_mac_key=""

  while IFS= read -r _enc_kdf_line
  do
    case "$_enc_kdf_line" in
      key=*)
        _enc_mac_key="${_enc_kdf_line#key=}"
      ;;
    esac
  done <<EOF_KDF
$_enc_kdf_output
EOF_KDF

  [ "${#_enc_mac_key}" -eq "64" ] || return 1

  case "$_enc_mac_key" in
    *[!0123456789ABCDEFabcdef]*) return 1 ;;
  esac

  printf '%s\n' "$_enc_mac_key"
)

_enc_hmac()
(
  set +x

  [ "$#" -eq "1" ] || return 2
  [ "${#1}" -eq "64" ] || return 1

  case "$1" in
    *[!0123456789ABCDEFabcdef]*) return 1 ;;
  esac

  _enc_hmac_output="$(
    openssl dgst -sha256 \
      -mac HMAC \
      -macopt "hexkey:$1"
  )" || return 1

  _enc_hmac_tag="${_enc_hmac_output##* }"

  [ "${#_enc_hmac_tag}" -eq "64" ] || return 1

  case "$_enc_hmac_tag" in
    *[!0123456789abcdef]*) return 1 ;;
  esac

  printf '%s\n' "$_enc_hmac_tag"
)

# encodes stdin to stdout
# ENC_PASS may provide the password; otherwise it is read from /dev/tty

encode()
(
  set +x

  [ "$#" -eq "0" ] || return 2

  if [ "${ENC_PASS+x}" != "x" ] || [ -z "$ENC_PASS" ]
  then
    ENC_PASS="$(_enc_password_read "Encryption password: ")" || return 1
    [ -n "$ENC_PASS" ] || return 1

    _enc_password_confirm="$(_enc_password_read "Verify encryption password: ")" || return 1
    [ "$ENC_PASS" = "$_enc_password_confirm" ] || return 1

    unset _enc_password_confirm
  fi

  _enc_password="$ENC_PASS"
  unset ENC_PASS

  _enc_body="$(
    ENC_PASS="$_enc_password" \
      openssl enc -e -aes-256-cbc \
        -pbkdf2 \
        -iter 600000 \
        -md sha256 \
        -a \
        -pass env:ENC_PASS || exit 1

    printf '%s' '_ENC_BODY_END_'
  )" || return 1

  case "$_enc_body" in
    *_ENC_BODY_END_)
      _enc_body="${_enc_body%_ENC_BODY_END_}"
    ;;

    *)
      return 1
    ;;
  esac

  [ -n "$_enc_body" ] || return 1

  _enc_mac_salt="$(openssl rand -hex 8)" || return 1

  [ "${#_enc_mac_salt}" -eq "16" ] || return 1

  case "$_enc_mac_salt" in
    *[!0123456789abcdef]*) return 1 ;;
  esac

  _enc_mac_key="$(_enc_mac_key "$_enc_mac_salt" "$_enc_password")" || return 1
  _enc_tag="$(
    {
      printf '%s\n' "ENC1"
      printf 'SALT:%s\n' "$_enc_mac_salt"
      printf '%s' "$_enc_body"
    } | _enc_hmac "$_enc_mac_key"
  )" || return 1

  unset _enc_mac_key
  unset _enc_password

  printf '%s\n' "ENC1" &&
    printf 'SALT:%s\n' "$_enc_mac_salt" &&
    printf 'HMAC:%s\n' "$_enc_tag" &&
    printf '%s' "$_enc_body"
)

#------------------------------------------------------------------------------

# decodes stdin to stdout
# ENC_PASS may provide the password; otherwise it is read from /dev/tty

decode()
(
  set +x

  [ "$#" -eq "0" ] || return 2

  if [ "${ENC_PASS+x}" != "x" ] || [ -z "$ENC_PASS" ]
  then
    ENC_PASS="$(_enc_password_read "Decryption password: ")" || return 1
    [ -n "$ENC_PASS" ] || return 1
  fi

  _enc_password="$ENC_PASS"
  unset ENC_PASS

  IFS= read -r _enc_magic || return 1
  IFS= read -r _enc_salt_line || return 1
  IFS= read -r _enc_tag_line || return 1

  _enc_body="$(
    cat || exit 1
    printf '%s' '_ENC_BODY_END_'
  )" || return 1

  case "$_enc_body" in
    *_ENC_BODY_END_)
      _enc_body="${_enc_body%_ENC_BODY_END_}"
    ;;

    *)
      return 1
    ;;
  esac

  [ "$_enc_magic" = "ENC1" ] || return 1

  case "$_enc_salt_line" in
    SALT:*)
      _enc_mac_salt="${_enc_salt_line#SALT:}"
    ;;

    *)
      return 1
    ;;
  esac

  [ "${#_enc_mac_salt}" -eq "16" ] || return 1

  case "$_enc_mac_salt" in
    *[!0123456789abcdef]*) return 1 ;;
  esac

  case "$_enc_tag_line" in
    HMAC:*)
      _enc_tag="${_enc_tag_line#HMAC:}"
    ;;

    *)
      return 1
    ;;
  esac

  [ "${#_enc_tag}" -eq "64" ] || return 1

  case "$_enc_tag" in
    *[!0123456789abcdef]*) return 1 ;;
  esac

  [ -n "$_enc_body" ] || return 1

  _enc_mac_key="$(_enc_mac_key "$_enc_mac_salt" "$_enc_password")" || return 1
  _enc_expected_tag="$(
    {
      printf '%s\n' "ENC1"
      printf 'SALT:%s\n' "$_enc_mac_salt"
      printf '%s' "$_enc_body"
    } | _enc_hmac "$_enc_mac_key"
  )" || return 1

  unset _enc_mac_key

  [ "$_enc_tag" = "$_enc_expected_tag" ] || return 1

  printf '%s' "$_enc_body" |
    ENC_PASS="$_enc_password" \
      openssl enc -d -aes-256-cbc \
        -pbkdf2 \
        -iter 600000 \
        -md sha256 \
        -a \
        -pass env:ENC_PASS
)

#------------------------------------------------------------------------------

# decodes file sourcing (executing) it into current shell script

encoded_file_import()
{
  if [ ! -f "$1" ]
  then
    set -- "$(command -v "$1")"

    if [ "$?" != "0" ] || [ ! -f "$1" ]
    then
      return 1
    fi
  fi

  eval "$(decode < "$1")"
}

#------------------------------------------------------------------------------

# sets the editor command

encoded_file_editor()
{
  if ! command -v "$1"
  then
    return 1
  fi

  export ENCODED_FILE_EDITOR="$1"
}

#------------------------------------------------------------------------------

# decodes file, opens it in editor, re-encodes it streaming into original

encoded_file_edit()
{
  if [ ! -f "$1" ]
  then
    set -- "$(command -v "$1")"

    if [ "$?" != "0" ] || [ ! -f "$1" ]
    then
      return 1
    fi
  fi

  (
    if [ -z "$ENCODED_FILE_EDITOR" ]
    then
      ENCODED_FILE_EDITOR="nano"
    fi

    # DECODED_FILE="${1}.$(date +"[%Y-%m-%d %H:%M:%S]").dec" && \
    # decode < "$1" > "$DECODED_FILE" && \
    # "$ENCODED_FILE_EDITOR" "$DECODED_FILE" && \
    # encode < "$DECODED_FILE" > "$1"

    DECODED_FILE="${1}.$(date +"[%Y-%m-%d %H:%M:%S]").dec" && \
    decode < "$1" > "$DECODED_FILE" && \
    "$ENCODED_FILE_EDITOR" "$DECODED_FILE"

    echo "reencode file: $1? YES, NO (default = YES): " >&2
    read REENCODE_CHOICE
    if [ "$REENCODE_CHOICE" = "YES" ] || [ "$REENCODE_CHOICE" = "yes" ] || [ "$REENCODE_CHOICE" = "Y" ] || [ "$REENCODE_CHOICE" = "y" ] || [ "$REENCODE_CHOICE" = "Yes" ]
    then
      encode < "$DECODED_FILE" > "$1"
    fi

    rm -f "$DECODED_FILE"
  )
}

#------------------------------------------------------------------------------

# converts bytes to whitespace-separated 3-digit octal octets
# with no arguments reads stdin, otherwise encodes the concatenated arguments

a2o()
{
  if [ "$#" -eq "0" ]
  then
    od -A n -t o1
  else
    printf '%s' "$@" | od -A n -t o1
  fi
}

# converts whitespace-separated octal octets to bytes
# with no arguments reads stdin; accepted octets are 0..377

o2a()
{
  (
    IFS=' 	
'
    set -f

    if [ "$#" -eq "0" ]
    then
      _o2a_input="$(cat)" || return 1
    else
      _o2a_input="$*"
    fi

    set -- $_o2a_input

    for _o2a_octet
    do
      case "$_o2a_octet" in
        [0-7]|[0-7][0-7]|[0123][0-7][0-7])
          :
        ;;

        *)
          return 1
        ;;
      esac
    done

    for _o2a_octet
    do
      printf '%b' "\\0$_o2a_octet" || return 1
    done
  )
}

#-------------------------------------------------------------------------------
