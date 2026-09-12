#!/bin/sh

# Reusable terminal, TTY and terminfo helpers.
#
# This library collects terminal-specific primitives that are useful outside a
# single interactive command. It is deliberately independent from menu,
# logging and layout policy: callers decide how to render their UI and how to
# handle signals.
#
# Public functions:
#   term_tty_use DEVICE
#       Select the TTY device used by this library (default: /dev/tty).
#   term_tty_available
#       Return success when the selected device is a usable terminal.
#   term_tty_save [DEVICE]
#       Save the current TTY settings. An optional DEVICE also selects it.
#   term_tty_restore
#       Restore settings saved by term_tty_save.
#   term_tty_blocking
#       Character-at-a-time, no-echo input; reads block for one byte.
#   term_tty_timed TENTHS
#       Character-at-a-time, no-echo input; reads wait at most TENTHS of a
#       second as understood by stty time.
#   term_tty_nowait
#       Character-at-a-time, no-echo input; reads return immediately.
#   term_size_update
#       Update term_rows and term_cols from the selected terminal.
#   term_screen_enter / term_screen_leave
#       Enter/leave the terminal alternate screen when supported.
#   term_keypad_enable / term_keypad_disable
#       Enable/disable application keypad mode when supported.
#   term_cursor_hide / term_cursor_show
#       Hide/show the cursor when supported.
#   term_cursor_move ROW COL
#       Move the cursor using zero-based terminal coordinates.
#   term_clear
#       Clear the selected terminal using its terminfo capability.
#   term_key_is_text KEY
#       Return success when KEY is one complete text key: printable ASCII or
#       one valid non-ASCII UTF-8 scalar value.
#   term_read_byte
#       Read one byte from the selected TTY without storing the raw byte in a
#       shell variable. Sets term_byte_dec and term_byte_hex.
#   term_keymap_init
#       Load common navigation/function-key sequences from terminfo.
#   term_read_key
#       Read and decode one key. Sets term_key, term_key_hex and, for text
#       input, term_key_text. The caller should already have put the TTY in
#       character mode with term_tty_blocking (normally after term_tty_save).
#       Escape-sequence reads temporarily use timed mode.
#   term_read_secret [PROMPT]
#       Read one line from the selected TTY with echo disabled and print it to
#       stdout, restoring the exact previous TTY state before returning.
#
# Public state:
#   term_tty_device       selected terminal device, default /dev/tty
#   term_rows             rows reported by term_size_update
#   term_cols             columns reported by term_size_update
#   term_byte_dec         last byte as unsigned decimal 0..255
#   term_byte_hex         last byte as two lowercase hexadecimal digits
#   term_key              decoded key name: text, nul, tab, enter, escape,
#                         backspace, up, down, left, right, home, end, pageup,
#                         pagedown, insert, delete, backtab, f1..f20, control
#                         or unknown
#   term_key_hex          complete key sequence in lowercase hexadecimal
#   term_key_text         decoded text for term_key=text
#   term_escape_time      escape-sequence timeout in stty tenths (default 1)
#
# Return status convention:
#   0  success
#   1  runtime/terminal/input error or unsupported operation
#   2  invalid function arguments
#   3  no byte available / end of input (term_read_byte/term_read_key)
#
# Design constraints:
#   - POSIX /bin/sh; no shell arrays, [[ ... ]], brace expansion or eval.
#   - No traps are installed and no function calls exit; lifecycle and signal
#     handling remain the caller's responsibility.
#   - Terminal control sequences are emitted directly to term_tty_device,
#     never to stdout/stderr, so command output remains composable.
#   - stty state is restored exactly rather than reconstructed from assumptions.
#   - tput capabilities are queried at runtime; unsupported capabilities fail
#     cleanly instead of embedding terminal-specific escape sequences.
#   - External utilities used: stty, tput, dd, od and tr.

: "${term_tty_device:=/dev/tty}"
: "${term_escape_time:=1}"

term_rows=
term_cols=
term_byte_dec=
term_byte_hex=
term_key=
term_key_hex=
term_key_text=
term_saved_stty=
term_tty_saved=false
term_keymap_ready=false

#-------------------------------------------------------------------------------

_term_is_uint()
{
  case ${1-} in
    ''|*[!0-9]*) return 1 ;;
  esac

  return 0
}

_term_tput()
{
  [ "$#" -ge 1 ] || return 2
  term_tty_available || return 1
  command -v tput >/dev/null 2>&1 || return 1
  [ -n "${TERM-}" ] || return 1
  [ "$TERM" != "dumb" ] || return 1

  tput "$@" > "$term_tty_device" 2>/dev/null
}

_term_hex_of()
{
  [ "$#" -eq 1 ] || return 2
  command -v od >/dev/null 2>&1 || return 1
  command -v tr >/dev/null 2>&1 || return 1

  printf '%s' "$1" |
    od -An -tx1 2>/dev/null |
    tr -d '[:space:]'
}

_term_cap_hex()
{
  [ "$#" -eq 1 ] || return 2
  command -v tput >/dev/null 2>&1 || return 1
  command -v od >/dev/null 2>&1 || return 1
  command -v tr >/dev/null 2>&1 || return 1
  [ -n "${TERM-}" ] || return 1
  [ "$TERM" != "dumb" ] || return 1

  tput "$1" 2>/dev/null | od -An -tx1 | tr -d '[:space:]'
}

_term_key_name()
{
  [ "$#" -eq 1 ] || return 2

  case "$1" in
    00) printf '%s\n' nul; return 0 ;;
    09) printf '%s\n' tab; return 0 ;;
    0a|0d) printf '%s\n' enter; return 0 ;;
    1b) printf '%s\n' escape; return 0 ;;
    08|7f) printf '%s\n' backspace; return 0 ;;
  esac

  [ -n "${term_key_up_hex-}" ] && [ "$1" = "$term_key_up_hex" ] && { printf '%s\n' up; return 0; }
  [ -n "${term_key_down_hex-}" ] && [ "$1" = "$term_key_down_hex" ] && { printf '%s\n' down; return 0; }
  [ -n "${term_key_left_hex-}" ] && [ "$1" = "$term_key_left_hex" ] && { printf '%s\n' left; return 0; }
  [ -n "${term_key_right_hex-}" ] && [ "$1" = "$term_key_right_hex" ] && { printf '%s\n' right; return 0; }
  [ -n "${term_key_home_hex-}" ] && [ "$1" = "$term_key_home_hex" ] && { printf '%s\n' home; return 0; }
  [ -n "${term_key_end_hex-}" ] && [ "$1" = "$term_key_end_hex" ] && { printf '%s\n' end; return 0; }
  [ -n "${term_key_pageup_hex-}" ] && [ "$1" = "$term_key_pageup_hex" ] && { printf '%s\n' pageup; return 0; }
  [ -n "${term_key_pagedown_hex-}" ] && [ "$1" = "$term_key_pagedown_hex" ] && { printf '%s\n' pagedown; return 0; }
  [ -n "${term_key_insert_hex-}" ] && [ "$1" = "$term_key_insert_hex" ] && { printf '%s\n' insert; return 0; }
  [ -n "${term_key_delete_hex-}" ] && [ "$1" = "$term_key_delete_hex" ] && { printf '%s\n' delete; return 0; }
  [ -n "${term_key_backtab_hex-}" ] && [ "$1" = "$term_key_backtab_hex" ] && { printf '%s\n' backtab; return 0; }
  [ -n "${term_key_enter_hex-}" ] && [ "$1" = "$term_key_enter_hex" ] && { printf '%s\n' enter; return 0; }
  [ -n "${term_key_backspace_hex-}" ] && [ "$1" = "$term_key_backspace_hex" ] && { printf '%s\n' backspace; return 0; }
  [ -n "${term_key_f1_hex-}" ] && [ "$1" = "$term_key_f1_hex" ] && { printf '%s\n' f1; return 0; }
  [ -n "${term_key_f2_hex-}" ] && [ "$1" = "$term_key_f2_hex" ] && { printf '%s\n' f2; return 0; }
  [ -n "${term_key_f3_hex-}" ] && [ "$1" = "$term_key_f3_hex" ] && { printf '%s\n' f3; return 0; }
  [ -n "${term_key_f4_hex-}" ] && [ "$1" = "$term_key_f4_hex" ] && { printf '%s\n' f4; return 0; }
  [ -n "${term_key_f5_hex-}" ] && [ "$1" = "$term_key_f5_hex" ] && { printf '%s\n' f5; return 0; }
  [ -n "${term_key_f6_hex-}" ] && [ "$1" = "$term_key_f6_hex" ] && { printf '%s\n' f6; return 0; }
  [ -n "${term_key_f7_hex-}" ] && [ "$1" = "$term_key_f7_hex" ] && { printf '%s\n' f7; return 0; }
  [ -n "${term_key_f8_hex-}" ] && [ "$1" = "$term_key_f8_hex" ] && { printf '%s\n' f8; return 0; }
  [ -n "${term_key_f9_hex-}" ] && [ "$1" = "$term_key_f9_hex" ] && { printf '%s\n' f9; return 0; }
  [ -n "${term_key_f10_hex-}" ] && [ "$1" = "$term_key_f10_hex" ] && { printf '%s\n' f10; return 0; }
  [ -n "${term_key_f11_hex-}" ] && [ "$1" = "$term_key_f11_hex" ] && { printf '%s\n' f11; return 0; }
  [ -n "${term_key_f12_hex-}" ] && [ "$1" = "$term_key_f12_hex" ] && { printf '%s\n' f12; return 0; }
  [ -n "${term_key_f13_hex-}" ] && [ "$1" = "$term_key_f13_hex" ] && { printf '%s\n' f13; return 0; }
  [ -n "${term_key_f14_hex-}" ] && [ "$1" = "$term_key_f14_hex" ] && { printf '%s\n' f14; return 0; }
  [ -n "${term_key_f15_hex-}" ] && [ "$1" = "$term_key_f15_hex" ] && { printf '%s\n' f15; return 0; }
  [ -n "${term_key_f16_hex-}" ] && [ "$1" = "$term_key_f16_hex" ] && { printf '%s\n' f16; return 0; }
  [ -n "${term_key_f17_hex-}" ] && [ "$1" = "$term_key_f17_hex" ] && { printf '%s\n' f17; return 0; }
  [ -n "${term_key_f18_hex-}" ] && [ "$1" = "$term_key_f18_hex" ] && { printf '%s\n' f18; return 0; }
  [ -n "${term_key_f19_hex-}" ] && [ "$1" = "$term_key_f19_hex" ] && { printf '%s\n' f19; return 0; }
  [ -n "${term_key_f20_hex-}" ] && [ "$1" = "$term_key_f20_hex" ] && { printf '%s\n' f20; return 0; }

  return 1
}

_term_key_has_longer_prefix()
{
  [ "$#" -eq 1 ] || return 2
  _term_prefix=$1

  for _term_sequence in \
    "${term_key_up_hex-}" \
    "${term_key_down_hex-}" \
    "${term_key_left_hex-}" \
    "${term_key_right_hex-}" \
    "${term_key_home_hex-}" \
    "${term_key_end_hex-}" \
    "${term_key_pageup_hex-}" \
    "${term_key_pagedown_hex-}" \
    "${term_key_insert_hex-}" \
    "${term_key_delete_hex-}" \
    "${term_key_backtab_hex-}" \
    "${term_key_enter_hex-}" \
    "${term_key_backspace_hex-}" \
    "${term_key_f1_hex-}" \
    "${term_key_f2_hex-}" \
    "${term_key_f3_hex-}" \
    "${term_key_f4_hex-}" \
    "${term_key_f5_hex-}" \
    "${term_key_f6_hex-}" \
    "${term_key_f7_hex-}" \
    "${term_key_f8_hex-}" \
    "${term_key_f9_hex-}" \
    "${term_key_f10_hex-}" \
    "${term_key_f11_hex-}" \
    "${term_key_f12_hex-}" \
    "${term_key_f13_hex-}" \
    "${term_key_f14_hex-}" \
    "${term_key_f15_hex-}" \
    "${term_key_f16_hex-}" \
    "${term_key_f17_hex-}" \
    "${term_key_f18_hex-}" \
    "${term_key_f19_hex-}" \
    "${term_key_f20_hex-}"
  do
    [ -n "$_term_sequence" ] || continue
    [ "$_term_sequence" != "$_term_prefix" ] || continue

    case "$_term_sequence" in
      "$_term_prefix"*)
        unset _term_prefix _term_sequence
        return 0
        ;;
    esac
  done

  unset _term_prefix _term_sequence
  return 1
}

_term_append_current_byte()
{
  _term_oct=$(printf '%03o' "$term_byte_dec") || return 1
  _term_text_esc="${_term_text_esc}\\${_term_oct}"
  term_key_hex=${term_key_hex}${term_byte_hex}
  unset _term_oct
}

_term_read_continuation()
{
  [ "$#" -eq 2 ] || return 2

  term_read_byte || return 1
  [ "$term_byte_dec" -ge "$1" ] 2>/dev/null || return 1
  [ "$term_byte_dec" -le "$2" ] 2>/dev/null || return 1
  _term_append_current_byte
}

#-------------------------------------------------------------------------------

term_tty_use()
{
  [ "$#" -eq 1 ] || return 2
  [ -r "$1" ] && [ -w "$1" ] || return 1
  command -v stty >/dev/null 2>&1 || return 1
  stty -g < "$1" >/dev/null 2>&1 || return 1

  term_tty_device=$1
}

term_tty_available()
{
  [ "$#" -eq 0 ] || return 2
  [ -r "$term_tty_device" ] && [ -w "$term_tty_device" ] || return 1
  command -v stty >/dev/null 2>&1 || return 1
  stty -g < "$term_tty_device" >/dev/null 2>&1
}

term_tty_save()
{
  [ "$#" -le 1 ] || return 2
  [ "$term_tty_saved" = "false" ] || return 1

  if [ "$#" -eq 1 ]
  then
    term_tty_use "$1" || return $?
  else
    term_tty_available || return 1
  fi

  term_saved_stty=$(stty -g < "$term_tty_device" 2>/dev/null) || return 1
  [ -n "$term_saved_stty" ] || return 1
  term_tty_saved=true
}

term_tty_restore()
{
  [ "$#" -eq 0 ] || return 2
  [ "$term_tty_saved" = "true" ] || return 1
  [ -n "$term_saved_stty" ] || return 1

  stty "$term_saved_stty" < "$term_tty_device" 2>/dev/null || return 1
  term_saved_stty=
  term_tty_saved=false
}

term_tty_blocking()
{
  [ "$#" -eq 0 ] || return 2
  term_tty_available || return 1
  stty -echo -icanon min 1 time 0 < "$term_tty_device" 2>/dev/null
}

term_tty_timed()
{
  [ "$#" -eq 1 ] || return 2
  _term_is_uint "$1" || return 2
  [ "$1" -le 255 ] 2>/dev/null || return 2
  term_tty_available || return 1
  stty -echo -icanon min 0 time "$1" < "$term_tty_device" 2>/dev/null
}

term_tty_nowait()
{
  [ "$#" -eq 0 ] || return 2
  term_tty_timed 0
}

term_size_update()
{
  [ "$#" -eq 0 ] || return 2
  term_tty_available || return 1

  _term_rows=
  _term_cols=

  if command -v tput >/dev/null 2>&1 && [ -n "${TERM-}" ] && [ "$TERM" != "dumb" ]
  then
    _term_rows=$(tput lines 2>/dev/null) || _term_rows=
    _term_cols=$(tput cols 2>/dev/null) || _term_cols=
  fi

  if ! _term_is_uint "$_term_rows" || ! _term_is_uint "$_term_cols" ||
     [ "$_term_rows" -eq 0 ] 2>/dev/null || [ "$_term_cols" -eq 0 ] 2>/dev/null
  then
    _term_size=$(stty size < "$term_tty_device" 2>/dev/null) || _term_size=
    _term_old_ifs=$IFS
    IFS=' '
    set -- $_term_size
    IFS=$_term_old_ifs

    [ "$#" -eq 2 ] || {
      unset _term_rows _term_cols _term_size _term_old_ifs
      return 1
    }

    _term_rows=$1
    _term_cols=$2
  fi

  _term_is_uint "$_term_rows" || return 1
  _term_is_uint "$_term_cols" || return 1
  [ "$_term_rows" -gt 0 ] 2>/dev/null || return 1
  [ "$_term_cols" -gt 0 ] 2>/dev/null || return 1

  term_rows=$_term_rows
  term_cols=$_term_cols
  unset _term_rows _term_cols _term_size _term_old_ifs
}

term_screen_enter()
{
  [ "$#" -eq 0 ] || return 2
  _term_tput smcup
}

term_screen_leave()
{
  [ "$#" -eq 0 ] || return 2
  _term_tput rmcup
}

term_keypad_enable()
{
  [ "$#" -eq 0 ] || return 2
  _term_tput smkx
}

term_keypad_disable()
{
  [ "$#" -eq 0 ] || return 2
  _term_tput rmkx
}

term_cursor_hide()
{
  [ "$#" -eq 0 ] || return 2
  _term_tput civis
}

term_cursor_show()
{
  [ "$#" -eq 0 ] || return 2
  _term_tput cnorm
}

term_cursor_move()
{
  [ "$#" -eq 2 ] || return 2
  _term_is_uint "$1" || return 2
  _term_is_uint "$2" || return 2
  _term_tput cup "$1" "$2"
}

term_clear()
{
  [ "$#" -eq 0 ] || return 2
  _term_tput clear
}

term_key_is_text()
{
  [ "$#" -eq 1 ] || return 2
  [ -n "$1" ] || return 1

  _term_key_text_hex=$(_term_hex_of "$1") || return 1

  case "$_term_key_text_hex" in
    2[0-9a-f]|[3-6][0-9a-f]|7[0-e]|c[2-9a-f][89ab][0-9a-f]|d[0-9a-f][89ab][0-9a-f]|e0[ab][0-9a-f][89ab][0-9a-f]|e[1-9abcef][89ab][0-9a-f][89ab][0-9a-f]|ed[89][0-9a-f][89ab][0-9a-f]|f0[9ab][0-9a-f][89ab][0-9a-f][89ab][0-9a-f]|f[1-3][89ab][0-9a-f][89ab][0-9a-f][89ab][0-9a-f]|f4[8][0-9a-f][89ab][0-9a-f][89ab][0-9a-f])
      unset _term_key_text_hex
      return 0
      ;;
  esac

  unset _term_key_text_hex
  return 1
}

term_read_byte()
{
  [ "$#" -eq 0 ] || return 2
  term_tty_available || return 1
  command -v dd >/dev/null 2>&1 || return 1
  command -v od >/dev/null 2>&1 || return 1
  command -v tr >/dev/null 2>&1 || return 1

  term_byte_dec=$(dd if="$term_tty_device" bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d '[:space:]')
  [ -n "$term_byte_dec" ] || {
    term_byte_hex=
    return 3
  }

  _term_is_uint "$term_byte_dec" || return 1
  [ "$term_byte_dec" -le 255 ] 2>/dev/null || return 1
  term_byte_hex=$(printf '%02x' "$term_byte_dec") || return 1
}

term_keymap_init()
{
  [ "$#" -eq 0 ] || return 2

  term_key_up_hex=$(_term_cap_hex kcuu1 2>/dev/null) || term_key_up_hex=
  term_key_down_hex=$(_term_cap_hex kcud1 2>/dev/null) || term_key_down_hex=
  term_key_left_hex=$(_term_cap_hex kcub1 2>/dev/null) || term_key_left_hex=
  term_key_right_hex=$(_term_cap_hex kcuf1 2>/dev/null) || term_key_right_hex=
  term_key_home_hex=$(_term_cap_hex khome 2>/dev/null) || term_key_home_hex=
  term_key_end_hex=$(_term_cap_hex kend 2>/dev/null) || term_key_end_hex=
  term_key_pageup_hex=$(_term_cap_hex kpp 2>/dev/null) || term_key_pageup_hex=
  term_key_pagedown_hex=$(_term_cap_hex knp 2>/dev/null) || term_key_pagedown_hex=
  term_key_insert_hex=$(_term_cap_hex kich1 2>/dev/null) || term_key_insert_hex=
  term_key_delete_hex=$(_term_cap_hex kdch1 2>/dev/null) || term_key_delete_hex=
  term_key_backtab_hex=$(_term_cap_hex kcbt 2>/dev/null) || term_key_backtab_hex=
  term_key_enter_hex=$(_term_cap_hex kent 2>/dev/null) || term_key_enter_hex=
  term_key_backspace_hex=$(_term_cap_hex kbs 2>/dev/null) || term_key_backspace_hex=
  term_key_f1_hex=$(_term_cap_hex kf1 2>/dev/null) || term_key_f1_hex=
  term_key_f2_hex=$(_term_cap_hex kf2 2>/dev/null) || term_key_f2_hex=
  term_key_f3_hex=$(_term_cap_hex kf3 2>/dev/null) || term_key_f3_hex=
  term_key_f4_hex=$(_term_cap_hex kf4 2>/dev/null) || term_key_f4_hex=
  term_key_f5_hex=$(_term_cap_hex kf5 2>/dev/null) || term_key_f5_hex=
  term_key_f6_hex=$(_term_cap_hex kf6 2>/dev/null) || term_key_f6_hex=
  term_key_f7_hex=$(_term_cap_hex kf7 2>/dev/null) || term_key_f7_hex=
  term_key_f8_hex=$(_term_cap_hex kf8 2>/dev/null) || term_key_f8_hex=
  term_key_f9_hex=$(_term_cap_hex kf9 2>/dev/null) || term_key_f9_hex=
  term_key_f10_hex=$(_term_cap_hex kf10 2>/dev/null) || term_key_f10_hex=
  term_key_f11_hex=$(_term_cap_hex kf11 2>/dev/null) || term_key_f11_hex=
  term_key_f12_hex=$(_term_cap_hex kf12 2>/dev/null) || term_key_f12_hex=
  term_key_f13_hex=$(_term_cap_hex kf13 2>/dev/null) || term_key_f13_hex=
  term_key_f14_hex=$(_term_cap_hex kf14 2>/dev/null) || term_key_f14_hex=
  term_key_f15_hex=$(_term_cap_hex kf15 2>/dev/null) || term_key_f15_hex=
  term_key_f16_hex=$(_term_cap_hex kf16 2>/dev/null) || term_key_f16_hex=
  term_key_f17_hex=$(_term_cap_hex kf17 2>/dev/null) || term_key_f17_hex=
  term_key_f18_hex=$(_term_cap_hex kf18 2>/dev/null) || term_key_f18_hex=
  term_key_f19_hex=$(_term_cap_hex kf19 2>/dev/null) || term_key_f19_hex=
  term_key_f20_hex=$(_term_cap_hex kf20 2>/dev/null) || term_key_f20_hex=

  term_keymap_ready=true
}

term_read_key()
{
  [ "$#" -eq 0 ] || return 2
  _term_is_uint "$term_escape_time" || return 2
  [ "$term_escape_time" -le 255 ] 2>/dev/null || return 2

  [ "$term_keymap_ready" = "true" ] || term_keymap_init || return 1

  term_key=
  term_key_hex=
  term_key_text=

  term_read_byte
  _term_status=$?
  if [ "$_term_status" -ne 0 ]
  then
    if [ "$_term_status" -eq 3 ]
    then
      unset _term_status
      return 3
    fi

    unset _term_status
    return 1
  fi

  _term_first_dec=$term_byte_dec
  term_key_hex=$term_byte_hex

  if [ "$term_byte_hex" = "1b" ]
  then
    _term_key_stty=$(stty -g < "$term_tty_device" 2>/dev/null) || return 1
    term_tty_timed "$term_escape_time" || return 1

    _term_count=1
    while _term_key_has_longer_prefix "$term_key_hex"
    do
      term_read_byte
      _term_status=$?

      if [ "$_term_status" -eq 3 ]
      then
        break
      fi

      if [ "$_term_status" -ne 0 ]
      then
        stty "$_term_key_stty" < "$term_tty_device" 2>/dev/null
        unset _term_key_stty _term_count _term_status _term_first_dec
        return 1
      fi

      term_key_hex=${term_key_hex}${term_byte_hex}
      _term_count=$((_term_count + 1))
      [ "$_term_count" -lt 32 ] || break
    done

    stty "$_term_key_stty" < "$term_tty_device" 2>/dev/null || {
      unset _term_key_stty _term_count _term_status _term_first_dec
      return 1
    }

    if term_key=$(_term_key_name "$term_key_hex")
    then
      :
    else
      term_key=unknown
    fi

    unset _term_key_stty _term_count _term_status _term_first_dec
    return 0
  fi

  if term_key=$(_term_key_name "$term_key_hex")
  then
    unset _term_status _term_first_dec
    return 0
  fi

  if [ "$_term_first_dec" -ge 32 ] 2>/dev/null && [ "$_term_first_dec" -le 126 ] 2>/dev/null
  then
    _term_oct=$(printf '%03o' "$_term_first_dec") || return 1
    term_key_text=$(printf '%b' "\\$_term_oct") || return 1
    term_key=text
    unset _term_oct _term_status _term_first_dec
    return 0
  fi

  _term_text_esc=
  term_key_hex=
  _term_append_current_byte || return 1

  case "$_term_first_dec" in
    194|195|196|197|198|199|200|201|202|203|204|205|206|207|208|209|210|211|212|213|214|215|216|217|218|219|220|221|222|223)
      _term_read_continuation 128 191 || return 1
      ;;
    224)
      _term_read_continuation 160 191 || return 1
      _term_read_continuation 128 191 || return 1
      ;;
    225|226|227|228|229|230|231|232|233|234|235|236|238|239)
      _term_read_continuation 128 191 || return 1
      _term_read_continuation 128 191 || return 1
      ;;
    237)
      _term_read_continuation 128 159 || return 1
      _term_read_continuation 128 191 || return 1
      ;;
    240)
      _term_read_continuation 144 191 || return 1
      _term_read_continuation 128 191 || return 1
      _term_read_continuation 128 191 || return 1
      ;;
    241|242|243)
      _term_read_continuation 128 191 || return 1
      _term_read_continuation 128 191 || return 1
      _term_read_continuation 128 191 || return 1
      ;;
    244)
      _term_read_continuation 128 143 || return 1
      _term_read_continuation 128 191 || return 1
      _term_read_continuation 128 191 || return 1
      ;;
    *)
      term_key=control
      unset _term_text_esc _term_status _term_first_dec
      return 0
      ;;
  esac

  term_key_text=$(printf '%b' "$_term_text_esc") || return 1
  term_key=text
  unset _term_text_esc _term_status _term_first_dec
}

term_read_secret()
{
  [ "$#" -le 1 ] || return 2
  term_tty_available || return 1

  _term_secret_prompt=${1-}
  _term_secret_stty=$(stty -g < "$term_tty_device" 2>/dev/null) || return 1

  if [ -n "$_term_secret_prompt" ]
  then
    printf '%s' "$_term_secret_prompt" > "$term_tty_device" || {
      unset _term_secret_prompt _term_secret_stty
      return 1
    }
  fi

  stty -echo < "$term_tty_device" 2>/dev/null || {
    unset _term_secret_prompt _term_secret_stty
    return 1
  }

  IFS= read -r _term_secret_value < "$term_tty_device"
  _term_secret_status=$?

  stty "$_term_secret_stty" < "$term_tty_device" 2>/dev/null || {
    unset _term_secret_prompt _term_secret_stty _term_secret_value _term_secret_status
    return 1
  }

  printf '\n' > "$term_tty_device" || {
    unset _term_secret_prompt _term_secret_stty _term_secret_value _term_secret_status
    return 1
  }

  [ "$_term_secret_status" -eq 0 ] || {
    unset _term_secret_prompt _term_secret_stty _term_secret_value _term_secret_status
    return 1
  }

  printf '%s\n' "$_term_secret_value"
  unset _term_secret_prompt _term_secret_stty _term_secret_value _term_secret_status
}
