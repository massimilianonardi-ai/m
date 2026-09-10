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

# encodes stdin to stdout (password can be provided through environmental variable ENC_PASS)

encode()
{
  if [ -z "$ENC_PASS" ]
  then
    openssl enc -e -aes-256-cbc -pbkdf2
  else
    (export ENC_PASS; openssl enc -e -aes-256-cbc -pbkdf2 -pass "env:ENC_PASS")
  fi
}

#------------------------------------------------------------------------------

# decodes stdin to stdout (password can be provided through environmental variable ENC_PASS)

decode()
{
  if [ -z "$ENC_PASS" ]
  then
    openssl enc -d -aes-256-cbc -pbkdf2
  else
    (export ENC_PASS; openssl enc -d -aes-256-cbc -pbkdf2 -pass "env:ENC_PASS")
  fi
}

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
