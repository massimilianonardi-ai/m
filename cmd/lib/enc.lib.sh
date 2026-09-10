#!/bin/sh

#------------------------------------------------------------------------------

# randh [bytes]
#
# Generates cryptographically secure random bytes and writes them as
# lowercase hexadecimal characters followed by a newline.
#
# bytes defaults to 32 and must be a canonical positive decimal integer.
# Each random byte is represented by exactly two hexadecimal characters:
#
#   randh      -> 32 random bytes -> 64 hexadecimal characters
#   randh 16   -> 16 random bytes -> 32 hexadecimal characters
#   randh 1    ->  1 random byte  ->  2 hexadecimal characters
#
# Returns 2 for invalid arguments and otherwise returns the status of
# openssl rand.

randh()
{
  [ "$#" -le "1" ] || return 2

  if [ "$#" -eq "0" ]
  then
    set -- "32"
  fi

  [ -n "$1" ] || return 2
  [ "$1" = "${1%%[!0123456789]*}" ] || return 2
  [ "$1" = "${1#0}" ] || return 2
  [ "$1" -gt "0" ] 2>/dev/null || return 2

  openssl rand -hex "$1"
}

#------------------------------------------------------------------------------

# rand64 [bytes]
#
# Generates cryptographically secure random bytes and writes their Base64
# representation as a single line followed by a newline.
#
# bytes defaults to 32 and must be a canonical positive decimal integer.
# The output contains exactly 4 * ceil(bytes / 3) Base64 characters,
# including any '=' padding:
#
#   rand64      -> 32 random bytes -> 44 Base64 characters
#   rand64 3    ->  3 random bytes ->  4 Base64 characters
#   rand64 1    ->  1 random byte  ->  4 Base64 characters
#
# Returns 2 for invalid arguments and 1 if random generation or output
# normalization fails.

rand64()
(
  [ "$#" -le "1" ] || return 2

  if [ "$#" -eq "0" ]
  then
    set -- "32"
  fi

  [ -n "$1" ] || return 2
  [ "$1" = "${1%%[!0123456789]*}" ] || return 2
  [ "$1" = "${1#0}" ] || return 2
  [ "$1" -gt "0" ] 2>/dev/null || return 2

  _rand64_output="$(openssl rand -base64 "$1")" || return 1

  _rand64_output="$(
    printf '%s' "$_rand64_output" |
      tr -d '\012'
  )" || return 1

  printf '%s\n' "$_rand64_output"
)

#------------------------------------------------------------------------------

# randstr [characters]
#
# Generates a cryptographically secure random string using only characters
# from the RFC 4648 Base64URL alphabet:
#
#   A-Z a-z 0-9 _ -
#
# The output contains exactly the requested number of characters followed by
# a newline. characters defaults to 32 and must be a canonical positive
# decimal integer.
#
# The function generates random input in complete 3-byte blocks, so every
# Base64 character is derived from exactly 6 uniformly distributed random
# bits. Standard Base64 '+' and '/' are translated to Base64URL '-' and '_',
# then the result is truncated to the requested length. No modulo operation
# or rejection mapping is used, so every output character remains uniformly
# distributed over the 64-character alphabet.
#
# Each output character therefore carries exactly 6 bits of entropy:
#
#   randstr       -> 32 characters -> 192 bits
#   randstr 16    -> 16 characters ->  96 bits
#   randstr 64    -> 64 characters -> 384 bits
#
# The result contains no whitespace, '/', '+', or '=' padding and is therefore
# suitable for tokens, filenames and URL components without further escaping.
#
# This is a random string drawn from the Base64URL alphabet; for arbitrary
# lengths it is not necessarily a decodable Base64URL encoding of a byte
# sequence.
#
# Returns 2 for invalid arguments and 1 if secure random generation or output
# transformation fails.

randstr()
(
  [ "$#" -le "1" ] || return 2

  if [ "$#" -eq "0" ]
  then
    set -- "32"
  fi

  [ -n "$1" ] || return 2
  [ "$1" = "${1%%[!0123456789]*}" ] || return 2
  [ "$1" = "${1#0}" ] || return 2
  [ "$1" -gt "0" ] 2>/dev/null || return 2

  _randstr_blocks="$((($1 + 3) / 4))"
  _randstr_bytes="$((_randstr_blocks * 3))"

  _randstr_output="$(rand64 "$_randstr_bytes")" || return 1

  _randstr_output="$(
    printf '%s' "$_randstr_output" |
      tr '/+' '_-'
  )" || return 1

  [ "${#_randstr_output}" -eq "$((_randstr_blocks * 4))" ] || return 1

  _randstr_remainder="$(($1 % 4))"

  if [ "$_randstr_remainder" -eq "1" ]
  then
    _randstr_output="${_randstr_output%???}"
  elif [ "$_randstr_remainder" -eq "2" ]
  then
    _randstr_output="${_randstr_output%??}"
  elif [ "$_randstr_remainder" -eq "3" ]
  then
    _randstr_output="${_randstr_output%?}"
  fi

  [ "${#_randstr_output}" -eq "$1" ] || return 1

  [ "$_randstr_output" = \
    "${_randstr_output%%[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*}" ] ||
    return 1

  printf '%s\n' "$_randstr_output"
)

#------------------------------------------------------------------------------

# randu [digits]
#
# Generates exactly the requested number of uniformly distributed decimal
# digits using the same cryptographically secure random source as randh.
#
# digits defaults to 4 and must be a canonical positive decimal integer.
# Leading zeroes are allowed because the result is a fixed-length digit
# string rather than a mathematical integer:
#
#   randu      -> e.g. 0387
#   randu 8    -> e.g. 59102743
#   randu 1    -> e.g. 7
#
# Hexadecimal digits a-f are discarded. Since every hexadecimal digit is
# uniformly distributed over 0-f, conditioning on the accepted set 0-9
# leaves every decimal digit with the same probability.
#
# Returns 2 for invalid arguments and 1 if random generation fails.

randu()
(
  [ "$#" -le "1" ] || return 2

  if [ "$#" -eq "0" ]
  then
    set -- "4"
  fi

  [ -n "$1" ] || return 2
  [ "$1" = "${1%%[!0123456789]*}" ] || return 2
  [ "$1" = "${1#0}" ] || return 2
  [ "$1" -gt "0" ] 2>/dev/null || return 2

  _randu_digits=""

  while [ "${#_randu_digits}" -lt "$1" ]
  do
    _randu_chunk="$(randh "$1")" || return 1

    _randu_chunk="$(
      printf '%s' "$_randu_chunk" |
        tr -cd '0123456789'
    )" || return 1

    _randu_digits="$_randu_digits$_randu_chunk"
  done

  printf '%.*s\n' "$1" "$_randu_digits"
)

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

  [ "$1" = "${1%%[!0123456789abcdef]*}" ] || return 1

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
    if [ "$_enc_kdf_line" != "${_enc_kdf_line#key=}" ]
    then
      _enc_mac_key="${_enc_kdf_line#key=}"
    fi
  done <<EOF_KDF
$_enc_kdf_output
EOF_KDF

  [ "${#_enc_mac_key}" -eq "64" ] || return 1

  [ "$_enc_mac_key" = "${_enc_mac_key%%[!0123456789ABCDEFabcdef]*}" ] || return 1

  printf '%s\n' "$_enc_mac_key"
)

_enc_hmac()
(
  set +x

  [ "$#" -eq "1" ] || return 2
  [ "${#1}" -eq "64" ] || return 1

  [ "$1" = "${1%%[!0123456789ABCDEFabcdef]*}" ] || return 1

  _enc_hmac_output="$(
    openssl dgst -sha256 \
      -mac HMAC \
      -macopt "hexkey:$1"
  )" || return 1

  _enc_hmac_tag="${_enc_hmac_output##* }"

  [ "${#_enc_hmac_tag}" -eq "64" ] || return 1

  [ "$_enc_hmac_tag" = "${_enc_hmac_tag%%[!0123456789abcdef]*}" ] || return 1

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

  if [ "$_enc_body" = "${_enc_body%_ENC_BODY_END_}" ]
  then
    return 1
  fi

  _enc_body="${_enc_body%_ENC_BODY_END_}"

  [ -n "$_enc_body" ] || return 1

  _enc_mac_salt="$(openssl rand -hex 8)" || return 1

  [ "${#_enc_mac_salt}" -eq "16" ] || return 1

  [ "$_enc_mac_salt" = "${_enc_mac_salt%%[!0123456789abcdef]*}" ] || return 1

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

  if [ "$_enc_body" = "${_enc_body%_ENC_BODY_END_}" ]
  then
    return 1
  fi

  _enc_body="${_enc_body%_ENC_BODY_END_}"

  [ "$_enc_magic" = "ENC1" ] || return 1

  if [ "$_enc_salt_line" = "${_enc_salt_line#SALT:}" ]
  then
    return 1
  fi

  _enc_mac_salt="${_enc_salt_line#SALT:}"

  [ "${#_enc_mac_salt}" -eq "16" ] || return 1

  [ "$_enc_mac_salt" = "${_enc_mac_salt%%[!0123456789abcdef]*}" ] || return 1

  if [ "$_enc_tag_line" = "${_enc_tag_line#HMAC:}" ]
  then
    return 1
  fi

  _enc_tag="${_enc_tag_line#HMAC:}"

  [ "${#_enc_tag}" -eq "64" ] || return 1

  [ "$_enc_tag" = "${_enc_tag%%[!0123456789abcdef]*}" ] || return 1

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
      _o2a_length="${#_o2a_octet}"

      if [ "$_o2a_length" -lt "1" ] || [ "$_o2a_length" -gt "3" ]
      then
        return 1
      fi

      [ "$_o2a_octet" = "${_o2a_octet%%[!01234567]*}" ] || return 1

      if [ "$_o2a_length" -eq "3" ]
      then
        _o2a_first="${_o2a_octet%??}"

        if [ "$_o2a_first" != "0" ] &&
           [ "$_o2a_first" != "1" ] &&
           [ "$_o2a_first" != "2" ] &&
           [ "$_o2a_first" != "3" ]
        then
          return 1
        fi
      fi
    done

    for _o2a_octet
    do
      printf '%b' "\\0$_o2a_octet" || return 1
    done
  )
}

#-------------------------------------------------------------------------------
