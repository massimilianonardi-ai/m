#!/bin/sh

# Reusable terminal, TTY and terminfo helpers.
#
# This library collects terminal-specific primitives that are useful outside a
# single interactive command.  It is deliberately independent from menu,
# logging and layout policy: callers decide how to render their UI and how to
# handle signals.
#
# Public functions:
#   term_ext_tty_use DEVICE
#       Select the TTY device used by this library (default: /dev/tty).
#   term_ext_tty_available
#       Return success when the selected device is a usable terminal.
#   term_ext_tty_save [DEVICE]
#       Save the current TTY settings.  An optional DEVICE also selects it.
#   term_ext_tty_restore
#       Restore settings saved by term_ext_tty_save.
#   term_ext_tty_blocking
#       Character-at-a-time, no-echo input; reads block for one byte.
#   term_ext_tty_timed TENTHS
#       Character-at-a-time, no-echo input; reads wait at most TENTHS of a
#       second as understood by stty time.
#   term_ext_tty_nowait
#       Character-at-a-time, no-echo input; reads return immediately.
#   term_ext_size_update
#       Update term_ext_rows and term_ext_cols from the selected terminal.
#   term_ext_screen_enter / term_ext_screen_leave
#       Enter/leave the terminal alternate screen when supported.
#   term_ext_keypad_enable / term_ext_keypad_disable
#       Enable/disable application keypad mode when supported.
#   term_ext_cursor_hide / term_ext_cursor_show
#       Hide/show the cursor when supported.
#   term_ext_cursor_move ROW COL
#       Move the cursor using zero-based terminal coordinates.
#   term_ext_clear
#       Clear the selected terminal using its terminfo capability.
#   term_ext_read_byte
#       Read one byte from the selected TTY without storing the raw byte in a
#       shell variable.  Sets term_ext_byte_dec and term_ext_byte_hex.
#   term_ext_keymap_init
#       Load common navigation-key sequences from terminfo.
#   term_ext_read_key
#       Read and decode one key.  Sets term_ext_key, term_ext_key_hex and,
#       for text input, term_ext_key_text.  The caller should already have put
#       the TTY in character mode with term_ext_tty_blocking (normally after
#       term_ext_tty_save).  Escape-sequence reads temporarily use timed mode.
#   term_ext_read_secret [PROMPT]
#       Read one line from the selected TTY with echo disabled and print it to
#       stdout, restoring the exact previous TTY state before returning.
#
# Public state:
#   term_ext_tty_device       selected terminal device, default /dev/tty
#   term_ext_rows             rows reported by term_ext_size_update
#   term_ext_cols             columns reported by term_ext_size_update
#   term_ext_byte_dec         last byte as unsigned decimal 0..255
#   term_ext_byte_hex         last byte as two lowercase hexadecimal digits
#   term_ext_key              decoded key name: text, tab, enter, escape,
#                             backspace, up, down, left, right, home, end,
#                             page_up, page_down, insert, delete, backtab,
#                             control or unknown
#   term_ext_key_hex          complete key sequence in lowercase hexadecimal
#   term_ext_key_text         decoded text for term_ext_key=text
#   term_ext_escape_time      escape-sequence timeout in stty tenths (default 1)
#
# Return status convention:
#   0  success
#   1  runtime/terminal/input error or unsupported operation
#   2  invalid function arguments
#   3  no byte available / end of input (term_ext_read_byte)
#
# Design constraints:
#   - POSIX.1-2024 /bin/sh; no shell arrays, [[ ... ]], brace expansion or eval.
#   - No traps are installed and no function calls exit; lifecycle and signal
#     handling remain the caller's responsibility.
#   - Terminal control sequences are emitted directly to term_ext_tty_device,
#     never to stdout/stderr, so command output remains composable.
#   - stty state is restored exactly rather than reconstructed from assumptions.
#   - tput capabilities are queried at runtime; unsupported capabilities fail
#     cleanly instead of embedding terminal-specific escape sequences.
#   - External utilities used: stty, tput, dd, od and tr.

: "${term_ext_tty_device:=/dev/tty}"
: "${term_ext_escape_time:=1}"

term_ext_rows=
term_ext_cols=
term_ext_byte_dec=
term_ext_byte_hex=
term_ext_key=
term_ext_key_hex=
term_ext_key_text=
term_ext_saved_stty=
term_ext_tty_saved=false
term_ext_keymap_ready=false

#-------------------------------------------------------------------------------

_term_ext_is_uint()
{
  case ${1-} in
    ''|*[!0-9]*) return 1 ;;
  esac

  return 0
}

_term_ext_tput()
{
  [ "$#" -ge 1 ] || return 2
  term_ext_tty_available || return 1
  command -v tput >/dev/null 2>&1 || return 1
  [ -n "${TERM-}" ] || return 1
  [ "$TERM" != "dumb" ] || return 1

  tput "$@" > "$term_ext_tty_device" 2>/dev/null
}

_term_ext_cap_hex()
{
  [ "$#" -eq 1 ] || return 2
  command -v tput >/dev/null 2>&1 || return 1
  command -v od >/dev/null 2>&1 || return 1
  command -v tr >/dev/null 2>&1 || return 1
  [ -n "${TERM-}" ] || return 1
  [ "$TERM" != "dumb" ] || return 1

  tput "$1" 2>/dev/null | od -An -tx1 | tr -d '[:space:]'
}

_term_ext_key_name()
{
  [ "$#" -eq 1 ] || return 2

  case $1 in
    09) printf '%s\n' tab; return 0 ;;
    0a|0d) printf '%s\n' enter; return 0 ;;
    1b) printf '%s\n' escape; return 0 ;;
    08|7f) printf '%s\n' backspace; return 0 ;;
  esac

  [ -n "${term_ext_key_up_hex-}" ] && [ "$1" = "$term_ext_key_up_hex" ] && { printf '%s\n' up; return 0; }
  [ -n "${term_ext_key_down_hex-}" ] && [ "$1" = "$term_ext_key_down_hex" ] && { printf '%s\n' down; return 0; }
  [ -n "${term_ext_key_left_hex-}" ] && [ "$1" = "$term_ext_key_left_hex" ] && { printf '%s\n' left; return 0; }
  [ -n "${term_ext_key_right_hex-}" ] && [ "$1" = "$term_ext_key_right_hex" ] && { printf '%s\n' right; return 0; }
  [ -n "${term_ext_key_home_hex-}" ] && [ "$1" = "$term_ext_key_home_hex" ] && { printf '%s\n' home; return 0; }
  [ -n "${term_ext_key_end_hex-}" ] && [ "$1" = "$term_ext_key_end_hex" ] && { printf '%s\n' end; return 0; }
  [ -n "${term_ext_key_page_up_hex-}" ] && [ "$1" = "$term_ext_key_page_up_hex" ] && { printf '%s\n' page_up; return 0; }
  [ -n "${term_ext_key_page_down_hex-}" ] && [ "$1" = "$term_ext_key_page_down_hex" ] && { printf '%s\n' page_down; return 0; }
  [ -n "${term_ext_key_insert_hex-}" ] && [ "$1" = "$term_ext_key_insert_hex" ] && { printf '%s\n' insert; return 0; }
  [ -n "${term_ext_key_delete_hex-}" ] && [ "$1" = "$term_ext_key_delete_hex" ] && { printf '%s\n' delete; return 0; }
  [ -n "${term_ext_key_backtab_hex-}" ] && [ "$1" = "$term_ext_key_backtab_hex" ] && { printf '%s\n' backtab; return 0; }
  [ -n "${term_ext_key_enter_hex-}" ] && [ "$1" = "$term_ext_key_enter_hex" ] && { printf '%s\n' enter; return 0; }
  [ -n "${term_ext_key_backspace_hex-}" ] && [ "$1" = "$term_ext_key_backspace_hex" ] && { printf '%s\n' backspace; return 0; }

  return 1
}

_term_ext_key_has_longer_prefix()
{
  [ "$#" -eq 1 ] || return 2
  _term_ext_prefix=$1

  for _term_ext_sequence in \
    "${term_ext_key_up_hex-}" \
    "${term_ext_key_down_hex-}" \
    "${term_ext_key_left_hex-}" \
    "${term_ext_key_right_hex-}" \
    "${term_ext_key_home_hex-}" \
    "${term_ext_key_end_hex-}" \
    "${term_ext_key_page_up_hex-}" \
    "${term_ext_key_page_down_hex-}" \
    "${term_ext_key_insert_hex-}" \
    "${term_ext_key_delete_hex-}" \
    "${term_ext_key_backtab_hex-}" \
    "${term_ext_key_enter_hex-}" \
    "${term_ext_key_backspace_hex-}"
  do
    [ -n "$_term_ext_sequence" ] || continue
    [ "$_term_ext_sequence" != "$_term_ext_prefix" ] || continue

    case $_term_ext_sequence in
      "$_term_ext_prefix"*)
        unset _term_ext_prefix _term_ext_sequence
        return 0
        ;;
    esac
  done

  unset _term_ext_prefix _term_ext_sequence
  return 1
}

_term_ext_append_current_byte()
{
  _term_ext_oct=$(printf '%03o' "$term_ext_byte_dec") || return 1
  _term_ext_text_esc="${_term_ext_text_esc}\\${_term_ext_oct}"
  term_ext_key_hex=${term_ext_key_hex}${term_ext_byte_hex}
  unset _term_ext_oct
}

_term_ext_read_continuation()
{
  [ "$#" -eq 2 ] || return 2

  term_ext_read_byte || return 1
  [ "$term_ext_byte_dec" -ge "$1" ] 2>/dev/null || return 1
  [ "$term_ext_byte_dec" -le "$2" ] 2>/dev/null || return 1
  _term_ext_append_current_byte
}

#-------------------------------------------------------------------------------

term_ext_tty_use()
{
  [ "$#" -eq 1 ] || return 2
  [ -r "$1" ] && [ -w "$1" ] || return 1
  command -v stty >/dev/null 2>&1 || return 1
  stty -g < "$1" >/dev/null 2>&1 || return 1

  term_ext_tty_device=$1
}

term_ext_tty_available()
{
  [ "$#" -eq 0 ] || return 2
  [ -r "$term_ext_tty_device" ] && [ -w "$term_ext_tty_device" ] || return 1
  command -v stty >/dev/null 2>&1 || return 1
  stty -g < "$term_ext_tty_device" >/dev/null 2>&1
}

term_ext_tty_save()
{
  [ "$#" -le 1 ] || return 2
  [ "$term_ext_tty_saved" = "false" ] || return 1

  if [ "$#" -eq 1 ]
  then
    term_ext_tty_use "$1" || return $?
  else
    term_ext_tty_available || return 1
  fi

  term_ext_saved_stty=$(stty -g < "$term_ext_tty_device" 2>/dev/null) || return 1
  [ -n "$term_ext_saved_stty" ] || return 1
  term_ext_tty_saved=true
}

term_ext_tty_restore()
{
  [ "$#" -eq 0 ] || return 2
  [ "$term_ext_tty_saved" = "true" ] || return 1
  [ -n "$term_ext_saved_stty" ] || return 1

  stty "$term_ext_saved_stty" < "$term_ext_tty_device" 2>/dev/null || return 1
  term_ext_saved_stty=
  term_ext_tty_saved=false
}

term_ext_tty_blocking()
{
  [ "$#" -eq 0 ] || return 2
  term_ext_tty_available || return 1
  stty -echo -icanon min 1 time 0 < "$term_ext_tty_device" 2>/dev/null
}

term_ext_tty_timed()
{
  [ "$#" -eq 1 ] || return 2
  _term_ext_is_uint "$1" || return 2
  [ "$1" -le 255 ] 2>/dev/null || return 2
  term_ext_tty_available || return 1
  stty -echo -icanon min 0 time "$1" < "$term_ext_tty_device" 2>/dev/null
}

term_ext_tty_nowait()
{
  [ "$#" -eq 0 ] || return 2
  term_ext_tty_timed 0
}

term_ext_size_update()
{
  [ "$#" -eq 0 ] || return 2
  term_ext_tty_available || return 1

  _term_ext_rows=
  _term_ext_cols=

  if command -v tput >/dev/null 2>&1 && [ -n "${TERM-}" ] && [ "$TERM" != "dumb" ]
  then
    _term_ext_rows=$(tput lines 2>/dev/null) || _term_ext_rows=
    _term_ext_cols=$(tput cols 2>/dev/null) || _term_ext_cols=
  fi

  if ! _term_ext_is_uint "$_term_ext_rows" || ! _term_ext_is_uint "$_term_ext_cols" || \
     [ "$_term_ext_rows" -eq 0 ] 2>/dev/null || [ "$_term_ext_cols" -eq 0 ] 2>/dev/null
  then
    _term_ext_size=$(stty size < "$term_ext_tty_device" 2>/dev/null) || _term_ext_size=
    _term_ext_old_ifs=$IFS
    IFS=' '
    set -- $_term_ext_size
    IFS=$_term_ext_old_ifs

    [ "$#" -eq 2 ] || {
      unset _term_ext_rows _term_ext_cols _term_ext_size _term_ext_old_ifs
      return 1
    }

    _term_ext_rows=$1
    _term_ext_cols=$2
  fi

  _term_ext_is_uint "$_term_ext_rows" || return 1
  _term_ext_is_uint "$_term_ext_cols" || return 1
  [ "$_term_ext_rows" -gt 0 ] 2>/dev/null || return 1
  [ "$_term_ext_cols" -gt 0 ] 2>/dev/null || return 1

  term_ext_rows=$_term_ext_rows
  term_ext_cols=$_term_ext_cols
  unset _term_ext_rows _term_ext_cols _term_ext_size _term_ext_old_ifs
}

term_ext_screen_enter()
{
  [ "$#" -eq 0 ] || return 2
  _term_ext_tput smcup
}

term_ext_screen_leave()
{
  [ "$#" -eq 0 ] || return 2
  _term_ext_tput rmcup
}

term_ext_keypad_enable()
{
  [ "$#" -eq 0 ] || return 2
  _term_ext_tput smkx
}

term_ext_keypad_disable()
{
  [ "$#" -eq 0 ] || return 2
  _term_ext_tput rmkx
}

term_ext_cursor_hide()
{
  [ "$#" -eq 0 ] || return 2
  _term_ext_tput civis
}

term_ext_cursor_show()
{
  [ "$#" -eq 0 ] || return 2
  _term_ext_tput cnorm
}

term_ext_cursor_move()
{
  [ "$#" -eq 2 ] || return 2
  _term_ext_is_uint "$1" || return 2
  _term_ext_is_uint "$2" || return 2
  _term_ext_tput cup "$1" "$2"
}

term_ext_clear()
{
  [ "$#" -eq 0 ] || return 2
  _term_ext_tput clear
}

term_ext_read_byte()
{
  [ "$#" -eq 0 ] || return 2
  term_ext_tty_available || return 1
  command -v dd >/dev/null 2>&1 || return 1
  command -v od >/dev/null 2>&1 || return 1
  command -v tr >/dev/null 2>&1 || return 1

  term_ext_byte_dec=$(dd if="$term_ext_tty_device" bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d '[:space:]')
  [ -n "$term_ext_byte_dec" ] || {
    term_ext_byte_hex=
    return 3
  }

  _term_ext_is_uint "$term_ext_byte_dec" || return 1
  [ "$term_ext_byte_dec" -le 255 ] 2>/dev/null || return 1
  term_ext_byte_hex=$(printf '%02x' "$term_ext_byte_dec") || return 1
}

term_ext_keymap_init()
{
  [ "$#" -eq 0 ] || return 2

  term_ext_key_up_hex=$(_term_ext_cap_hex kcuu1 2>/dev/null) || term_ext_key_up_hex=
  term_ext_key_down_hex=$(_term_ext_cap_hex kcud1 2>/dev/null) || term_ext_key_down_hex=
  term_ext_key_left_hex=$(_term_ext_cap_hex kcub1 2>/dev/null) || term_ext_key_left_hex=
  term_ext_key_right_hex=$(_term_ext_cap_hex kcuf1 2>/dev/null) || term_ext_key_right_hex=
  term_ext_key_home_hex=$(_term_ext_cap_hex khome 2>/dev/null) || term_ext_key_home_hex=
  term_ext_key_end_hex=$(_term_ext_cap_hex kend 2>/dev/null) || term_ext_key_end_hex=
  term_ext_key_page_up_hex=$(_term_ext_cap_hex kpp 2>/dev/null) || term_ext_key_page_up_hex=
  term_ext_key_page_down_hex=$(_term_ext_cap_hex knp 2>/dev/null) || term_ext_key_page_down_hex=
  term_ext_key_insert_hex=$(_term_ext_cap_hex kich1 2>/dev/null) || term_ext_key_insert_hex=
  term_ext_key_delete_hex=$(_term_ext_cap_hex kdch1 2>/dev/null) || term_ext_key_delete_hex=
  term_ext_key_backtab_hex=$(_term_ext_cap_hex kcbt 2>/dev/null) || term_ext_key_backtab_hex=
  term_ext_key_enter_hex=$(_term_ext_cap_hex kent 2>/dev/null) || term_ext_key_enter_hex=
  term_ext_key_backspace_hex=$(_term_ext_cap_hex kbs 2>/dev/null) || term_ext_key_backspace_hex=

  term_ext_keymap_ready=true
}

term_ext_read_key()
{
  [ "$#" -eq 0 ] || return 2
  _term_ext_is_uint "$term_ext_escape_time" || return 2
  [ "$term_ext_escape_time" -le 255 ] 2>/dev/null || return 2

  [ "$term_ext_keymap_ready" = "true" ] || term_ext_keymap_init || return 1

  term_ext_key=
  term_ext_key_hex=
  term_ext_key_text=

  term_ext_read_byte
  _term_ext_status=$?
  if [ "$_term_ext_status" -ne 0 ]
  then
    if [ "$_term_ext_status" -eq 3 ]
    then
      unset _term_ext_status
      return 3
    fi

    unset _term_ext_status
    return 1
  fi

  _term_ext_first_dec=$term_ext_byte_dec
  term_ext_key_hex=$term_ext_byte_hex

  if [ "$term_ext_byte_hex" = "1b" ]
  then
    _term_ext_key_stty=$(stty -g < "$term_ext_tty_device" 2>/dev/null) || return 1
    term_ext_tty_timed "$term_ext_escape_time" || return 1

    _term_ext_count=1
    while _term_ext_key_has_longer_prefix "$term_ext_key_hex"
    do
      term_ext_read_byte
      _term_ext_status=$?

      if [ "$_term_ext_status" -eq 3 ]
      then
        break
      fi

      if [ "$_term_ext_status" -ne 0 ]
      then
        stty "$_term_ext_key_stty" < "$term_ext_tty_device" 2>/dev/null
        unset _term_ext_key_stty _term_ext_count _term_ext_status _term_ext_first_dec
        return 1
      fi

      term_ext_key_hex=${term_ext_key_hex}${term_ext_byte_hex}
      _term_ext_count=$((_term_ext_count + 1))
      [ "$_term_ext_count" -lt 32 ] || break
    done

    stty "$_term_ext_key_stty" < "$term_ext_tty_device" 2>/dev/null || {
      unset _term_ext_key_stty _term_ext_count _term_ext_status _term_ext_first_dec
      return 1
    }

    if term_ext_key=$(_term_ext_key_name "$term_ext_key_hex")
    then
      :
    else
      term_ext_key=unknown
    fi

    unset _term_ext_key_stty _term_ext_count _term_ext_status _term_ext_first_dec
    return 0
  fi

  if term_ext_key=$(_term_ext_key_name "$term_ext_key_hex")
  then
    unset _term_ext_status _term_ext_first_dec
    return 0
  fi

  if [ "$_term_ext_first_dec" -ge 32 ] 2>/dev/null && [ "$_term_ext_first_dec" -le 126 ] 2>/dev/null
  then
    _term_ext_oct=$(printf '%03o' "$_term_ext_first_dec") || return 1
    term_ext_key_text=$(printf '%b' "\\$_term_ext_oct") || return 1
    term_ext_key=text
    unset _term_ext_oct _term_ext_status _term_ext_first_dec
    return 0
  fi

  _term_ext_text_esc=
  term_ext_key_hex=
  _term_ext_append_current_byte || return 1

  case $_term_ext_first_dec in
    194|195|196|197|198|199|200|201|202|203|204|205|206|207|208|209|210|211|212|213|214|215|216|217|218|219|220|221|222|223)
      _term_ext_read_continuation 128 191 || return 1
      ;;
    224)
      _term_ext_read_continuation 160 191 || return 1
      _term_ext_read_continuation 128 191 || return 1
      ;;
    225|226|227|228|229|230|231|232|233|234|235|236|238|239)
      _term_ext_read_continuation 128 191 || return 1
      _term_ext_read_continuation 128 191 || return 1
      ;;
    237)
      _term_ext_read_continuation 128 159 || return 1
      _term_ext_read_continuation 128 191 || return 1
      ;;
    240)
      _term_ext_read_continuation 144 191 || return 1
      _term_ext_read_continuation 128 191 || return 1
      _term_ext_read_continuation 128 191 || return 1
      ;;
    241|242|243)
      _term_ext_read_continuation 128 191 || return 1
      _term_ext_read_continuation 128 191 || return 1
      _term_ext_read_continuation 128 191 || return 1
      ;;
    244)
      _term_ext_read_continuation 128 143 || return 1
      _term_ext_read_continuation 128 191 || return 1
      _term_ext_read_continuation 128 191 || return 1
      ;;
    *)
      term_ext_key=control
      unset _term_ext_text_esc _term_ext_status _term_ext_first_dec
      return 0
      ;;
  esac

  term_ext_key_text=$(printf '%b' "$_term_ext_text_esc") || return 1
  term_ext_key=text
  unset _term_ext_text_esc _term_ext_status _term_ext_first_dec
}

term_ext_read_secret()
{
  [ "$#" -le 1 ] || return 2
  term_ext_tty_available || return 1

  _term_ext_secret_prompt=${1-}
  _term_ext_secret_stty=$(stty -g < "$term_ext_tty_device" 2>/dev/null) || return 1

  if [ -n "$_term_ext_secret_prompt" ]
  then
    printf '%s' "$_term_ext_secret_prompt" > "$term_ext_tty_device" || {
      unset _term_ext_secret_prompt _term_ext_secret_stty
      return 1
    }
  fi

  stty -echo < "$term_ext_tty_device" 2>/dev/null || {
    unset _term_ext_secret_prompt _term_ext_secret_stty
    return 1
  }

  IFS= read -r _term_ext_secret_value < "$term_ext_tty_device"
  _term_ext_secret_status=$?

  stty "$_term_ext_secret_stty" < "$term_ext_tty_device" 2>/dev/null || {
    unset _term_ext_secret_prompt _term_ext_secret_stty _term_ext_secret_value _term_ext_secret_status
    return 1
  }

  printf '\n' > "$term_ext_tty_device" || {
    unset _term_ext_secret_prompt _term_ext_secret_stty _term_ext_secret_value _term_ext_secret_status
    return 1
  }

  [ "$_term_ext_secret_status" -eq 0 ] || {
    unset _term_ext_secret_prompt _term_ext_secret_stty _term_ext_secret_value _term_ext_secret_status
    return 1
  }

  printf '%s\n' "$_term_ext_secret_value"
  unset _term_ext_secret_prompt _term_ext_secret_stty _term_ext_secret_value _term_ext_secret_status
}
