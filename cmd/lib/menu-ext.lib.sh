# menu-ext.lib.sh
#
# POSIX-sh terminal-menu engine with pluggable list providers.
#
# Dependencies:
#   array.lib.sh (which provides array() and sources arg.lib.sh for quote())
#
# Public configuration variables:
#   menu_ext_header
#   menu_ext_footer
#   menu_ext_bottom_footer
#   menu_ext_array_values   array name used by menu_ext_array_provider
#   menu_ext_array_labels   array name used by menu_ext_array_provider
#
# Public result variables set by menu_ext_run_provider:
#   menu_ext_result_key
#   menu_ext_result_value
#   menu_ext_error
#
# Public functions:
#   menu_ext_reset
#   menu_ext_key_clear
#   menu_ext_key_add KEY
#   menu_ext_run_provider PROVIDER
#   menu_ext_array_provider
#
# Provider contract
# -----------------
# PROVIDER is a shell function called with one of:
#
#   PROVIDER count
#     Set menu_ext_provider_count to a positive integer.
#
#   PROVIDER item INDEX
#     Set menu_ext_provider_value and menu_ext_provider_label.
#     Values may contain embedded or trailing newlines. Labels are currently
#     single-line because the renderer still uses one terminal row per item.
#     POSIX shell variables cannot represent NUL bytes.
#
#   PROVIDER event KEY INDEX VALUE LABEL
#     The engine sets menu_ext_provider_action=return before the call.
#     The provider may leave it unchanged or set it to:
#
#       return  finish and return KEY + VALUE
#       reload  query the provider again, preserving/clamping selection
#       reset   query the provider again and select index 0
#       ignore  continue without redrawing
#       cancel  finish as a user cancellation
#
# Enter is always delivered as an event. Configured custom keys are delivered
# the same way. Escape and up/down/pageup/pagedown/home/end are owned by the
# engine and cannot be configured.
#
# Array-backed provider
# ---------------------
# menu_ext_array_provider exposes two parallel arrays created through array():
#
#   menu_ext_array_values=VALUES_ARRAY_NAME
#   menu_ext_array_labels=LABELS_ARRAY_NAME
#
# Both arrays must have the same size. The size equality is checked whenever
# the engine loads/reloads the provider. Array values are copied directly into
# the provider output variables, preserving embedded and trailing newlines.
# Labels remain subject to the current single-line renderer contract.
#
# The input vocabulary intentionally follows RumiAI OS read-key:
#   escape, up, down, left, right, home, end, insert, delete,
#   pageup, pagedown, backspace, tab, backtab, enter, nul, f1..f20,
#   plus literal printable ASCII/UTF-8 characters. Space is a literal " ".
#
# The low-level decoder is adapted from RumiAI OS read-key. Unlike the command,
# it does not initialize and restore the TTY for every key: one menu session
# owns the TTY state and terminfo keymap for its whole lifetime.

. array.lib.sh

menu_ext_reset()
{
  menu_ext_header=""
  menu_ext_footer=""
  menu_ext_bottom_footer=""
  menu_ext_custom_keys=""
  menu_ext_array_values=""
  menu_ext_array_labels=""
  menu_ext_result_key=""
  menu_ext_result_value=""
  menu_ext_error=""
}

menu_ext_key_clear()
{
  menu_ext_custom_keys=""
}

menu_ext_array_provider()
{
  case "$1" in
    count)
      [ "$#" -eq 1 ] || return 2
      [ -n "$menu_ext_array_values" ] || return 2
      [ -n "$menu_ext_array_labels" ] || return 2

      array "$menu_ext_array_values" size menu_ext__array_values_size || return "$?"
      array "$menu_ext_array_labels" size menu_ext__array_labels_size || return "$?"

      [ "$menu_ext__array_values_size" = "$menu_ext__array_labels_size" ] || return 1

      menu_ext_provider_count="$menu_ext__array_values_size"
      ;;
    item)
      [ "$#" -eq 2 ] || return 2

      array "$menu_ext_array_values" get "$2" menu_ext_provider_value || return "$?"
      array "$menu_ext_array_labels" get "$2" menu_ext_provider_label || return "$?"
      ;;
    event)
      [ "$#" -eq 5 ] || return 2
      ;;
    *)
      return 2
      ;;
  esac

  return 0
}

menu_ext__key_is_reserved()
{
  case "$1" in
    escape|enter|up|down|pageup|pagedown|home|end)
      return 0
      ;;
  esac

  return 1
}

menu_ext__key_is_configured()
{
  case "$menu_ext__newline$menu_ext_custom_keys$menu_ext__newline" in
    *"$menu_ext__newline$1$menu_ext__newline"*)
      return 0
      ;;
  esac

  return 1
}

menu_ext__key_is_named_custom()
{
  case "$1" in
    nul|backspace|tab|backtab|left|right|insert|delete|f1|f2|f3|f4|f5|f6|f7|f8|f9|f10|f11|f12|f13|f14|f15|f16|f17|f18|f19|f20)
      return 0
      ;;
  esac

  return 1
}

menu_ext__key_is_printable_character()
{
  menu_ext__candidate_hex="$(menu_ext__hex_of "$1")" || return 1

  case "$menu_ext__candidate_hex" in
    2[0-9a-f]|[3-6][0-9a-f]|7[0-e])
      return 0
      ;;
    c[2-9a-f][89ab][0-9a-f]|d[0-9a-f][89ab][0-9a-f])
      return 0
      ;;
    e0[ab][0-9a-f][89ab][0-9a-f]|e[1-9abcef][89ab][0-9a-f][89ab][0-9a-f]|ed[89][0-9a-f][89ab][0-9a-f])
      return 0
      ;;
    f0[9ab][0-9a-f][89ab][0-9a-f][89ab][0-9a-f]|f[1-3][89ab][0-9a-f][89ab][0-9a-f][89ab][0-9a-f]|f4[8][0-9a-f][89ab][0-9a-f][89ab][0-9a-f])
      return 0
      ;;
  esac

  return 1
}

menu_ext_key_add()
{
  if [ "$#" -ne 1 ] || [ -z "$1" ]
  then
    menu_ext_error="menu_ext_key_add requires one non-empty key"
    return 2
  fi

  case "$1" in
    *"$menu_ext__newline"*)
      menu_ext_error="custom key must not contain a newline"
      return 2
      ;;
  esac

  if menu_ext__key_is_reserved "$1"
  then
    menu_ext_error="key is reserved: $1"
    return 2
  fi

  if ! menu_ext__key_is_named_custom "$1" &&
     ! menu_ext__key_is_printable_character "$1"
  then
    menu_ext_error="invalid custom key: $1"
    return 2
  fi

  if menu_ext__key_is_configured "$1"
  then
    menu_ext_error="duplicate custom key: $1"
    return 2
  fi

  if [ -z "$menu_ext_custom_keys" ]
  then
    menu_ext_custom_keys="$1"
  else
    menu_ext_custom_keys="$menu_ext_custom_keys$menu_ext__newline$1"
  fi

  menu_ext_error=""
  return 0
}

menu_ext__fail()
{
  menu_ext__session_error="$1"
  return 2
}

menu_ext__read_byte()
{
  menu_ext__byte="$(
    command -p dd bs=1 count=1 2>/dev/null < "$menu_ext__tty_device"
    menu_ext__status=$?
    printf -- 'x'
    exit "$menu_ext__status"
  )" || return 1

  menu_ext__byte=${menu_ext__byte%x}
}

menu_ext__hex_of()
{
  printf -- '%s' "$1" |
    command -p od -A n -t x1 2>/dev/null |
    command -p tr -d ' \n' 2>/dev/null
}

menu_ext__map_add()
{
  while IFS=: read -r menu_ext__hex menu_ext__name
  do
    [ "$menu_ext__hex" = "$1" ] && return 0
  done << EOF_MENU_EXT_MAP
$menu_ext__keymap
EOF_MENU_EXT_MAP

  menu_ext__keymap="${menu_ext__keymap}${menu_ext__keymap:+
}$1:$2"
}

menu_ext__cap_add()
{
  menu_ext__value="$(command tput "$1" 2>/dev/null; printf -- 'x')"
  menu_ext__value=${menu_ext__value%x}

  [ -n "$menu_ext__value" ] || return 0

  menu_ext__hex="$(menu_ext__hex_of "$menu_ext__value")" || return 1
  menu_ext__map_add "$menu_ext__hex" "$2"
}

menu_ext__map_lookup()
{
  menu_ext__key_name=""

  while IFS=: read -r menu_ext__hex menu_ext__name
  do
    if [ "$menu_ext__hex" = "$1" ]
    then
      menu_ext__key_name=$menu_ext__name
      return 0
    fi
  done << EOF_MENU_EXT_MAP
$menu_ext__keymap
EOF_MENU_EXT_MAP

  return 1
}

menu_ext__map_has_longer()
{
  while IFS=: read -r menu_ext__hex menu_ext__name
  do
    case "$menu_ext__hex" in
      "$1"*)
        [ "$menu_ext__hex" != "$1" ] && return 0
        ;;
    esac
  done << EOF_MENU_EXT_MAP
$menu_ext__keymap
EOF_MENU_EXT_MAP

  return 1
}

menu_ext__tty_blocking()
{
  command -p stty -echo -icanon min 1 time 0 \
    2>/dev/null < "$menu_ext__tty_device"
}

menu_ext__tty_timed()
{
  command -p stty -echo -icanon min 0 time "$menu_ext__interbyte_time" \
    2>/dev/null < "$menu_ext__tty_device"
}

menu_ext__tty_nowait()
{
  command -p stty -echo -icanon min 0 time 0 \
    2>/dev/null < "$menu_ext__tty_device"
}

menu_ext__read_key()
{
  case "$1" in
    blocking)
      menu_ext__tty_blocking || return 1
      ;;
    nowait)
      menu_ext__tty_nowait || return 1
      ;;
    *)
      return 1
      ;;
  esac

  menu_ext__read_byte || return 1

  if [ -z "$menu_ext__byte" ]
  then
    if [ "$1" = "blocking" ]
    then
      menu_ext__key="nul"
      return 0
    fi

    return 3
  fi

  menu_ext__key=$menu_ext__byte
  menu_ext__key_hex="$(menu_ext__hex_of "$menu_ext__key")" || return 1

  if menu_ext__map_lookup "$menu_ext__key_hex"
  then
    menu_ext__exact=$menu_ext__key_name
  else
    menu_ext__exact=""
  fi

  if menu_ext__map_has_longer "$menu_ext__key_hex"
  then
    menu_ext__tty_timed || return 1

    while menu_ext__map_has_longer "$menu_ext__key_hex"
    do
      menu_ext__read_byte || return 1
      [ -n "$menu_ext__byte" ] || break

      menu_ext__key=$menu_ext__key$menu_ext__byte
      menu_ext__byte_hex="$(menu_ext__hex_of "$menu_ext__byte")" || return 1
      menu_ext__key_hex=$menu_ext__key_hex$menu_ext__byte_hex

      if menu_ext__map_lookup "$menu_ext__key_hex"
      then
        menu_ext__exact=$menu_ext__key_name
      else
        menu_ext__exact=""
      fi

      if [ -z "$menu_ext__exact" ] &&
         ! menu_ext__map_has_longer "$menu_ext__key_hex"
      then
        return 2
      fi
    done

    if [ -n "$menu_ext__exact" ]
    then
      menu_ext__key=$menu_ext__exact
      return 0
    fi

    return 2
  fi

  if [ -n "$menu_ext__exact" ]
  then
    menu_ext__key=$menu_ext__exact
    return 0
  fi

  case "$menu_ext__key_hex" in
    2[0-9a-f]|[3-6][0-9a-f]|7[0-e])
      return 0
      ;;
  esac

  menu_ext__first_hex=$menu_ext__key_hex

  case "$menu_ext__first_hex" in
    c[2-9a-f]|d[0-9a-f]) menu_ext__remaining="1" ;;
    e[0-9a-f]) menu_ext__remaining="2" ;;
    f[0-4]) menu_ext__remaining="3" ;;
    *) return 2 ;;
  esac

  menu_ext__tty_timed || return 1
  menu_ext__position="2"

  while [ "$menu_ext__remaining" -gt 0 ]
  do
    menu_ext__read_byte || return 1
    [ -n "$menu_ext__byte" ] || return 2

    menu_ext__byte_hex="$(menu_ext__hex_of "$menu_ext__byte")" || return 1

    case "$menu_ext__byte_hex" in
      [89ab][0-9a-f]) ;;
      *) return 2 ;;
    esac

    if [ "$menu_ext__position" -eq 2 ]
    then
      case "$menu_ext__first_hex:$menu_ext__byte_hex" in
        e0:8[0-9a-f]|e0:9[0-9a-f]|ed:a[0-9a-f]|ed:b[0-9a-f]|f0:8[0-9a-f]|f4:9[0-9a-f]|f4:a[0-9a-f]|f4:b[0-9a-f])
          return 2
          ;;
      esac
    fi

    menu_ext__key=$menu_ext__key$menu_ext__byte
    menu_ext__remaining=$((menu_ext__remaining - 1))
    menu_ext__position=$((menu_ext__position + 1))
  done

  return 0
}

menu_ext__build_keymap()
{
  menu_ext__keymap=""

  menu_ext__cap_add kbs backspace || return 1
  menu_ext__cap_add kent enter || return 1
  menu_ext__cap_add kcbt backtab || return 1
  menu_ext__cap_add kcuu1 up || return 1
  menu_ext__cap_add kcud1 down || return 1
  menu_ext__cap_add kcub1 left || return 1
  menu_ext__cap_add kcuf1 right || return 1
  menu_ext__cap_add khome home || return 1
  menu_ext__cap_add kend end || return 1
  menu_ext__cap_add kich1 insert || return 1
  menu_ext__cap_add kdch1 delete || return 1
  menu_ext__cap_add kpp pageup || return 1
  menu_ext__cap_add knp pagedown || return 1

  menu_ext__f="1"
  while [ "$menu_ext__f" -le 20 ]
  do
    menu_ext__cap_add "kf$menu_ext__f" "f$menu_ext__f" || return 1
    menu_ext__f=$((menu_ext__f + 1))
  done

  menu_ext__map_add 08 backspace
  menu_ext__map_add 09 tab
  menu_ext__map_add 0a enter
  menu_ext__map_add 0d enter
  menu_ext__map_add 1b escape
  menu_ext__map_add 7f backspace
}

menu_ext__line_count()
{
  if [ -z "$1" ]
  then
    printf -- '%s\n' "0"
  else
    printf -- '%s\n' "$1" | command -p awk 'END { print NR }'
  fi
}

menu_ext__print_block()
{
  printf -- '%s\n' "$1" |
    command -p awk -v width="$2" -v trailing_newline="$3" '
      NR > 1 { printf "\n" }
      {
        gsub(/[[:cntrl:]]/, "?")
        printf "%s", substr($0, 1, width)
      }
      END {
        if (trailing_newline == "1") {
          printf "\n"
        }
      }
    ' > "$menu_ext__tty_device"
}

menu_ext__safe_item_text()
{
  printf -- '%s\n' "$1" |
    command -p awk -v width="$2" '
      {
        gsub(/[[:cntrl:]]/, "?")
        printf "%s", substr($0, 1, width)
        exit
      }
    '
}

menu_ext__provider_count_get()
{
  menu_ext_provider_count=""

  "$menu_ext__provider" count >/dev/null || {
    menu_ext__fail "provider count operation failed"
    return 2
  }

  case "$menu_ext_provider_count" in
    ''|*[!0-9]*)
      menu_ext__fail "provider returned an invalid count"
      return 2
      ;;
  esac

  if [ "$menu_ext_provider_count" -lt 1 ]
  then
    menu_ext__fail "provider returned an empty list"
    return 2
  fi

  menu_ext__item_count=$menu_ext_provider_count
  return 0
}

menu_ext__provider_item_get()
{
  menu_ext_provider_value=""
  menu_ext_provider_label=""

  "$menu_ext__provider" item "$1" >/dev/null || {
    menu_ext__fail "provider item operation failed at index $1"
    return 2
  }

  case "$menu_ext_provider_label" in
    *"$menu_ext__newline"*)
      menu_ext__fail "provider label contains a newline at index $1"
      return 2
      ;;
  esac

  return 0
}

menu_ext__provider_event()
{
  menu_ext__event_key="$1"
  menu_ext__event_index="$2"

  menu_ext__provider_item_get "$menu_ext__event_index" || return 2

  menu_ext__event_value="$menu_ext_provider_value"
  menu_ext__event_label="$menu_ext_provider_label"
  menu_ext_provider_action="return"

  "$menu_ext__provider" event "$menu_ext__event_key" "$menu_ext__event_index" \
    "$menu_ext__event_value" "$menu_ext__event_label" >/dev/null || {
      menu_ext__fail "provider event operation failed"
      return 2
    }

  case "$menu_ext_provider_action" in
    return|reload|reset|ignore|cancel) ;;
    *)
      menu_ext__fail "provider returned an invalid event action"
      return 2
      ;;
  esac

  case "$menu_ext_provider_action" in
    return)
      menu_ext__session_result_key="$menu_ext__event_key"
      menu_ext__session_result_value="$menu_ext__event_value"
      return 10
      ;;
    reload)
      menu_ext__provider_count_get || return 2
      if [ "$menu_ext__selected" -ge "$menu_ext__item_count" ]
      then
        menu_ext__selected=$((menu_ext__item_count - 1))
      fi
      [ "$menu_ext__selected" -ge 0 ] || menu_ext__selected="0"
      menu_ext__render_needed="1"
      return 0
      ;;
    reset)
      menu_ext__provider_count_get || return 2
      menu_ext__selected="0"
      menu_ext__top="0"
      menu_ext__render_needed="1"
      return 0
      ;;
    ignore)
      return 0
      ;;
    cancel)
      return 11
      ;;
  esac
}

menu_ext__update_geometry()
{
  menu_ext__term_lines="$(command tput lines 2>/dev/null)" || {
    menu_ext__fail "cannot read terminal height"
    return 2
  }

  menu_ext__term_cols="$(command tput cols 2>/dev/null)" || {
    menu_ext__fail "cannot read terminal width"
    return 2
  }

  case "$menu_ext__term_lines" in
    ''|*[!0-9]*)
      menu_ext__fail "invalid terminal height"
      return 2
      ;;
  esac

  case "$menu_ext__term_cols" in
    ''|*[!0-9]*)
      menu_ext__fail "invalid terminal width"
      return 2
      ;;
  esac

  menu_ext__header_lines="$(menu_ext__line_count "$menu_ext_header")"
  menu_ext__footer_lines="$(menu_ext__line_count "$menu_ext_footer")"
  menu_ext__bottom_footer_lines="$(menu_ext__line_count "$menu_ext_bottom_footer")"
  menu_ext__visible_rows=$((menu_ext__term_lines - menu_ext__header_lines - menu_ext__footer_lines - menu_ext__bottom_footer_lines))

  if [ "$menu_ext__visible_rows" -lt 1 ] || [ "$menu_ext__term_cols" -lt 3 ]
  then
    menu_ext__fail "terminal is too small"
    return 2
  fi

  return 0
}

menu_ext__render()
{
  command tput clear 2>/dev/null > "$menu_ext__tty_device" || {
    menu_ext__fail "terminal does not support clear"
    return 2
  }

  if [ -n "$menu_ext_header" ]
  then
    menu_ext__print_block "$menu_ext_header" "$menu_ext__term_cols" "1" || return 2
  fi

  menu_ext__remaining=$((menu_ext__item_count - menu_ext__top))
  if [ "$menu_ext__remaining" -lt "$menu_ext__visible_rows" ]
  then
    menu_ext__render_rows=$menu_ext__remaining
  else
    menu_ext__render_rows=$menu_ext__visible_rows
  fi

  menu_ext__row="0"
  menu_ext__index=$menu_ext__top
  menu_ext__last_menu_row=$((menu_ext__render_rows - 1))
  menu_ext__text_width=$((menu_ext__term_cols - 2))

  while [ "$menu_ext__row" -lt "$menu_ext__render_rows" ]
  do
    menu_ext__provider_item_get "$menu_ext__index" || return 2
    menu_ext__text="$(menu_ext__safe_item_text "$menu_ext_provider_label" "$menu_ext__text_width")" || return 2

    if [ "$menu_ext__index" -eq "$menu_ext__selected" ]
    then
      command tput rev 2>/dev/null > "$menu_ext__tty_device" || :
      printf -- '> %s' "$menu_ext__text" > "$menu_ext__tty_device"
      command tput sgr0 2>/dev/null > "$menu_ext__tty_device" || :
    else
      printf -- '  %s' "$menu_ext__text" > "$menu_ext__tty_device"
    fi

    if [ "$menu_ext__row" -lt "$menu_ext__last_menu_row" ] ||
       [ -n "$menu_ext_footer" ]
    then
      printf -- '\n' > "$menu_ext__tty_device"
    fi

    menu_ext__row=$((menu_ext__row + 1))
    menu_ext__index=$((menu_ext__index + 1))
  done

  if [ -n "$menu_ext_footer" ]
  then
    menu_ext__print_block "$menu_ext_footer" "$menu_ext__term_cols" "0" || return 2
  fi

  if [ -n "$menu_ext_bottom_footer" ]
  then
    menu_ext__bottom_footer_row=$((menu_ext__term_lines - menu_ext__bottom_footer_lines))
    command tput cup "$menu_ext__bottom_footer_row" 0 2>/dev/null > "$menu_ext__tty_device" || {
      menu_ext__fail "terminal does not support cursor positioning"
      return 2
    }
    menu_ext__print_block "$menu_ext_bottom_footer" "$menu_ext__term_cols" "0" || return 2
  fi

  command tput cup 0 0 2>/dev/null > "$menu_ext__tty_device" || {
    menu_ext__fail "terminal does not support cursor positioning"
    return 2
  }

  return 0
}

menu_ext__apply_key()
{
  menu_ext__action=""

  case "$menu_ext__key" in
    escape)
      menu_ext__action="cancel"
      return 0
      ;;
    up)
      if [ "$menu_ext__selected" -gt 0 ]
      then
        menu_ext__selected=$((menu_ext__selected - 1))
        menu_ext__action="move"
      fi
      return 0
      ;;
    down)
      if [ "$menu_ext__selected" -lt "$((menu_ext__item_count - 1))" ]
      then
        menu_ext__selected=$((menu_ext__selected + 1))
        menu_ext__action="move"
      fi
      return 0
      ;;
    pageup)
      menu_ext__page_step=$((menu_ext__visible_rows - 1))
      [ "$menu_ext__page_step" -ge 1 ] || menu_ext__page_step="1"
      if [ "$menu_ext__selected" -gt 0 ]
      then
        menu_ext__selected=$((menu_ext__selected - menu_ext__page_step))
        [ "$menu_ext__selected" -ge 0 ] || menu_ext__selected="0"
        menu_ext__action="move"
      fi
      return 0
      ;;
    pagedown)
      menu_ext__page_step=$((menu_ext__visible_rows - 1))
      [ "$menu_ext__page_step" -ge 1 ] || menu_ext__page_step="1"
      if [ "$menu_ext__selected" -lt "$((menu_ext__item_count - 1))" ]
      then
        menu_ext__selected=$((menu_ext__selected + menu_ext__page_step))
        if [ "$menu_ext__selected" -gt "$((menu_ext__item_count - 1))" ]
        then
          menu_ext__selected=$((menu_ext__item_count - 1))
        fi
        menu_ext__action="move"
      fi
      return 0
      ;;
    home)
      if [ "$menu_ext__selected" -ne 0 ]
      then
        menu_ext__selected="0"
        menu_ext__action="move"
      fi
      return 0
      ;;
    end)
      if [ "$menu_ext__selected" -ne "$((menu_ext__item_count - 1))" ]
      then
        menu_ext__selected=$((menu_ext__item_count - 1))
        menu_ext__action="move"
      fi
      return 0
      ;;
    enter)
      menu_ext__action="event"
      return 0
      ;;
  esac

  if menu_ext__key_is_configured "$menu_ext__key"
  then
    menu_ext__action="event"
  fi
}

menu_ext__cleanup()
{
  menu_ext__cleanup_status=$?
  trap - 0 HUP INT QUIT TERM PIPE TSTP

  if [ "$menu_ext__keypad" -eq 1 ]
  then
    command tput rmkx 2>/dev/null > "$menu_ext__tty_device" || :
    menu_ext__keypad="0"
  fi

  command tput sgr0 2>/dev/null > "$menu_ext__tty_device" || :

  if [ "$menu_ext__alt_screen" -eq 1 ]
  then
    command tput rmcup 2>/dev/null > "$menu_ext__tty_device" || :
    menu_ext__alt_screen="0"
  fi

  if [ "$menu_ext__cursor_hidden" -eq 1 ]
  then
    command tput cnorm 2>/dev/null > "$menu_ext__tty_device" || :
    menu_ext__cursor_hidden="0"
  fi

  if [ -n "$menu_ext__tty_saved" ]
  then
    command -p stty "$menu_ext__tty_saved" 2>/dev/null < "$menu_ext__tty_device" || :
    menu_ext__tty_saved=""
  fi

  return "$menu_ext__cleanup_status"
}

menu_ext__terminal_init()
{
  menu_ext__tty_saved="$(command -p stty -g 2>/dev/null < "$menu_ext__tty_device")" || {
    menu_ext__fail "no controlling terminal is available"
    return 2
  }

  [ -n "$menu_ext__tty_saved" ] || {
    menu_ext__fail "cannot read terminal settings"
    return 2
  }

  command -v tput >/dev/null 2>&1 || {
    menu_ext__fail "tput is required"
    return 2
  }

  command tput cols >/dev/null 2>&1 || {
    menu_ext__fail "terminal has no usable terminfo entry"
    return 2
  }

  menu_ext__tty_blocking || {
    menu_ext__fail "cannot configure terminal"
    return 2
  }

  if command tput smkx 2>/dev/null > "$menu_ext__tty_device"
  then
    menu_ext__keypad="1"
  fi

  menu_ext__build_keymap || {
    menu_ext__fail "cannot build terminal keymap"
    return 2
  }

  if command tput smcup 2>/dev/null > "$menu_ext__tty_device"
  then
    menu_ext__alt_screen="1"
  fi

  if command tput civis 2>/dev/null > "$menu_ext__tty_device"
  then
    menu_ext__cursor_hidden="1"
  fi

  return 0
}

menu_ext__main_loop()
{
  menu_ext__provider_count_get || return 2
  menu_ext__selected="0"
  menu_ext__top="0"
  menu_ext__render_needed="1"

  while :
  do
    if [ "$menu_ext__render_needed" = "1" ]
    then
      menu_ext__update_geometry || return 2

      if [ "$menu_ext__selected" -lt "$menu_ext__top" ]
      then
        menu_ext__top=$menu_ext__selected
      elif [ "$menu_ext__selected" -ge "$((menu_ext__top + menu_ext__visible_rows))" ]
      then
        menu_ext__top=$((menu_ext__selected - menu_ext__visible_rows + 1))
      fi

      menu_ext__render || return 2
      menu_ext__render_needed="0"
    fi

    menu_ext__read_key blocking
    menu_ext__read_status=$?

    case "$menu_ext__read_status" in
      0) ;;
      2) continue ;;
      *)
        menu_ext__fail "cannot read from terminal"
        return 2
        ;;
    esac

    menu_ext__apply_key

    case "$menu_ext__action" in
      cancel)
        return 1
        ;;
      event)
        menu_ext__provider_event "$menu_ext__key" "$menu_ext__selected"
        menu_ext__event_status=$?
        case "$menu_ext__event_status" in
          0) ;;
          10) return 0 ;;
          11) return 1 ;;
          *) return 2 ;;
        esac
        ;;
      move)
        menu_ext__pending="0"

        while [ "$menu_ext__pending" -lt 64 ]
        do
          menu_ext__read_key nowait
          menu_ext__read_status=$?

          case "$menu_ext__read_status" in
            0) ;;
            2)
              menu_ext__pending=$((menu_ext__pending + 1))
              continue
              ;;
            3) break ;;
            *)
              menu_ext__fail "cannot read queued terminal input"
              return 2
              ;;
          esac

          menu_ext__apply_key

          case "$menu_ext__action" in
            cancel)
              return 1
              ;;
            event)
              menu_ext__provider_event "$menu_ext__key" "$menu_ext__selected"
              menu_ext__event_status=$?
              case "$menu_ext__event_status" in
                0)
                  if [ "$menu_ext__render_needed" = "1" ]
                  then
                    break
                  fi
                  ;;
                10) return 0 ;;
                11) return 1 ;;
                *) return 2 ;;
              esac
              ;;
          esac

          menu_ext__pending=$((menu_ext__pending + 1))
        done

        menu_ext__render_needed="1"
        ;;
    esac
  done
}

menu_ext__session()
{
  menu_ext__provider="$1"
  menu_ext__tty_device="/dev/tty"
  menu_ext__interbyte_time="1"
  menu_ext__tty_saved=""
  menu_ext__keypad="0"
  menu_ext__alt_screen="0"
  menu_ext__cursor_hidden="0"
  menu_ext__keymap=""
  menu_ext__session_result_key=""
  menu_ext__session_result_value=""
  menu_ext__session_error=""

  trap 'menu_ext__cleanup' 0
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 131' QUIT
  trap 'exit 141' PIPE
  trap 'exit 143' TERM
  trap 'exit 148' TSTP

  menu_ext__terminal_init
  menu_ext__status="$?"

  if [ "$menu_ext__status" -eq 0 ]
  then
    menu_ext__main_loop
    menu_ext__status="$?"
  fi

  case "$menu_ext__status" in
    0)
      menu_ext__session_record="$(quote "$menu_ext__session_result_key" "$menu_ext__session_result_value")" || {
        printf -- '%s\n' "cannot serialize menu result"
        return 2
      }
      printf -- '%s\n' "$menu_ext__session_record"
      ;;
    2)
      printf -- '%s\n' "$menu_ext__session_error"
      ;;
  esac

  return "$menu_ext__status"
}

menu_ext_run_provider()
{
  menu_ext_result_key=""
  menu_ext_result_value=""
  menu_ext_error=""

  if [ "$#" -ne 1 ] || [ -z "$1" ]
  then
    menu_ext_error="menu_ext_run_provider requires one provider function"
    return 2
  fi

  menu_ext__record="$(menu_ext__session "$1")"
  menu_ext__status="$?"

  case "$menu_ext__status" in
    0)
      # menu_ext__record is produced only by quote(), so eval reparses a
      # shell-safe serialized argument list rather than provider data as code.
      if ! eval "set -- $menu_ext__record"
      then
        menu_ext_error="invalid internal menu result"
        return 2
      fi

      if [ "$#" -ne 2 ]
      then
        menu_ext_error="invalid internal menu result"
        return 2
      fi

      menu_ext_result_key="$1"
      menu_ext_result_value="$2"
      return 0
      ;;
    1)
      return 1
      ;;
    2)
      menu_ext_error="$menu_ext__record"
      [ -n "$menu_ext_error" ] || menu_ext_error="menu engine failed"
      return 2
      ;;
    *)
      return "$menu_ext__status"
      ;;
  esac
}

menu_ext__newline='
'

menu_ext_reset
