# POSIX-sh terminal-menu engine with pluggable list providers.
#
# Dependencies:
#   term.lib.sh   terminal/TTY/terminfo lifecycle and key decoding
#   array.lib.sh  array-backed provider support
#   map.lib.sh    custom-key set
#   arg.lib.sh    quote(), sourced by array.lib.sh/map.lib.sh
#
# The menu layer deliberately contains no direct stty/tput/dd/od handling.
# Terminal control and input are delegated to term.lib.sh; menu.lib.sh owns only
# menu policy, provider dispatch, layout and rendering of ordinary text.
#
# Public configuration variables:
#   menu_header
#   menu_footer
#   menu_bottom_footer
#   menu_array_values   array name used by menu_array_provider
#   menu_array_labels   array name used by menu_array_provider
#
# Public result variables set by menu_run_provider:
#   menu_result_key
#   menu_result_value
#   menu_error
#
# Public functions:
#   menu_reset
#   menu_key_clear
#   menu_key_add KEY
#   menu_run_provider PROVIDER
#   menu_array_provider
#
# Provider contract
# -----------------
# PROVIDER is a shell function called with one of:
#
#   PROVIDER count
#     Set menu_provider_count to a positive integer.
#
#   PROVIDER item INDEX
#     Set menu_provider_value and menu_provider_label.
#     Values may contain embedded or trailing newlines. Labels are single-line
#     because the renderer uses one terminal row per item.
#
#   PROVIDER event KEY INDEX VALUE LABEL
#     The engine sets menu_provider_action=return before the call. The provider
#     may leave it unchanged or set it to:
#
#       return  finish and return KEY + VALUE
#       reload  query the provider again, preserving/clamping selection
#       reset   query the provider again and select index 0
#       ignore  continue without redrawing
#       cancel  finish as a user cancellation
#
# Enter is always delivered as an event. Escape and up/down/pageup/pagedown/
# home/end are owned by the engine and cannot be configured. Other named keys
# returned by term_read_key (including left/right, insert/delete, tab/backtab,
# backspace, nul and f1..f20) and one text key can be configured with
# menu_key_add.
#
# Array-backed provider
# ---------------------
# menu_array_provider exposes two parallel arrays:
#
#   menu_array_values=VALUES_ARRAY_NAME
#   menu_array_labels=LABELS_ARRAY_NAME
#
# Both arrays must have the same size. Values are copied directly, preserving
# embedded and trailing newlines. POSIX shell variables cannot represent NUL.
#
# Terminal ownership
# ------------------
# menu_run_provider uses the terminal currently selected by term_tty_device.
# Call term_tty_use DEVICE before menu_run_provider to select another TTY.
# Each menu session saves/restores the exact TTY state and uses term.lib.sh for
# alternate-screen, keypad, cursor, size and key operations. The session owns
# its signal traps; term.lib.sh itself installs none.
#
# Status convention:
#   0  provider returned a selection/event result
#   1  user/provider cancellation
#   2  invalid API usage or menu/provider/terminal failure
#   signal-derived statuses are propagated by the session

. array.lib.sh
. map.lib.sh
. term.lib.sh

#-------------------------------------------------------------------------------

menu_reset()
{
  menu_header=
  menu_footer=
  menu_bottom_footer=
  menu_array_values=
  menu_array_labels=
  menu_result_key=
  menu_result_value=
  menu_error=

  map menu__custom_keys || return 1
}

menu_key_clear()
{
  map menu__custom_keys
}

menu_array_provider()
{
  case "$1" in
    count)
      [ "$#" -eq 1 ] || return 2
      [ -n "$menu_array_values" ] || return 2
      [ -n "$menu_array_labels" ] || return 2

      array "$menu_array_values" size menu__array_values_size || return "$?"
      array "$menu_array_labels" size menu__array_labels_size || return "$?"

      [ "$menu__array_values_size" = "$menu__array_labels_size" ] || return 1
      menu_provider_count=$menu__array_values_size
      ;;
    item)
      [ "$#" -eq 2 ] || return 2

      array "$menu_array_values" get "$2" menu_provider_value || return "$?"
      array "$menu_array_labels" get "$2" menu_provider_label || return "$?"
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

menu__key_is_reserved()
{
  [ "$#" -eq 1 ] || return 2

  case "$1" in
    escape|enter|up|down|pageup|pagedown|home|end)
      return 0
      ;;
  esac

  return 1
}

menu__key_is_named_custom()
{
  [ "$#" -eq 1 ] || return 2

  case "$1" in
    nul|backspace|tab|backtab|left|right|insert|delete|f1|f2|f3|f4|f5|f6|f7|f8|f9|f10|f11|f12|f13|f14|f15|f16|f17|f18|f19|f20)
      return 0
      ;;
  esac

  return 1
}

menu__key_is_configured()
{
  [ "$#" -eq 1 ] || return 2

  if map menu__custom_keys get "$1" menu__configured_value >/dev/null 2>&1
  then
    unset menu__configured_value
    return 0
  fi

  unset menu__configured_value
  return 1
}

menu_key_add()
{
  if [ "$#" -ne 1 ] || [ -z "$1" ]
  then
    menu_error="menu_key_add requires one non-empty key"
    return 2
  fi

  if menu__key_is_reserved "$1"
  then
    menu_error="key is reserved: $1"
    return 2
  fi

  if ! menu__key_is_named_custom "$1" && ! term_key_is_text "$1"
  then
    menu_error="invalid custom key: $1"
    return 2
  fi

  if menu__key_is_configured "$1"
  then
    menu_error="duplicate custom key: $1"
    return 2
  fi

  map menu__custom_keys put "$1" "1" || {
    menu_error="cannot store custom key"
    return 1
  }

  menu_error=
  return 0
}

#-------------------------------------------------------------------------------

menu__fail()
{
  menu__session_error=$1
  return 2
}

menu__read_key()
{
  [ "$#" -eq 1 ] || return 2

  case "$1" in
    blocking)
      term_tty_blocking || return 1
      ;;
    nowait)
      term_tty_nowait || return 1
      ;;
    *)
      return 2
      ;;
  esac

  term_read_key
  menu__read_term_status=$?

  case "$menu__read_term_status" in
    0) ;;
    3)
      unset menu__read_term_status
      return 3
      ;;
    *)
      unset menu__read_term_status
      return 1
      ;;
  esac

  case "$term_key" in
    text)
      menu__key=$term_key_text
      ;;
    unknown|control)
      unset menu__read_term_status
      return 2
      ;;
    *)
      menu__key=$term_key
      ;;
  esac

  unset menu__read_term_status
  return 0
}

menu__line_count()
{
  [ "$#" -eq 1 ] || return 2

  if [ -z "$1" ]
  then
    printf '%s\n' "0"
  else
    printf '%s\n' "$1" | command -p awk 'END { print NR }'
  fi
}

menu__print_block()
{
  [ "$#" -eq 3 ] || return 2

  printf '%s\n' "$1" |
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
    ' > "$term_tty_device"
}

menu__safe_item_text()
{
  [ "$#" -eq 2 ] || return 2

  printf '%s\n' "$1" |
    command -p awk -v width="$2" '
      {
        gsub(/[[:cntrl:]]/, "?")
        printf "%s", substr($0, 1, width)
        exit
      }
    '
}

#-------------------------------------------------------------------------------

menu__provider_count_get()
{
  menu_provider_count=

  "$menu__provider" count >/dev/null || {
    menu__fail "provider count operation failed"
    return 2
  }

  case "$menu_provider_count" in
    ''|*[!0-9]*)
      menu__fail "provider returned an invalid count"
      return 2
      ;;
  esac

  if [ "$menu_provider_count" -lt 1 ] 2>/dev/null
  then
    menu__fail "provider returned an empty list"
    return 2
  fi

  menu__item_count=$menu_provider_count
  return 0
}

menu__provider_item_get()
{
  [ "$#" -eq 1 ] || return 2

  menu_provider_value=
  menu_provider_label=

  "$menu__provider" item "$1" >/dev/null || {
    menu__fail "provider item operation failed at index $1"
    return 2
  }

  case "$menu_provider_label" in
    *"$menu__newline"*)
      menu__fail "provider label contains a newline at index $1"
      return 2
      ;;
  esac

  return 0
}

menu__provider_event()
{
  [ "$#" -eq 2 ] || return 2

  menu__event_key=$1
  menu__event_index=$2

  menu__provider_item_get "$menu__event_index" || return 2

  menu__event_value=$menu_provider_value
  menu__event_label=$menu_provider_label
  menu_provider_action=return

  "$menu__provider" event "$menu__event_key" "$menu__event_index" \
    "$menu__event_value" "$menu__event_label" >/dev/null || {
      menu__fail "provider event operation failed"
      return 2
    }

  case "$menu_provider_action" in
    return|reload|reset|ignore|cancel) ;;
    *)
      menu__fail "provider returned an invalid event action"
      return 2
      ;;
  esac

  case "$menu_provider_action" in
    return)
      menu__session_result_key=$menu__event_key
      menu__session_result_value=$menu__event_value
      return 10
      ;;
    reload)
      menu__provider_count_get || return 2

      if [ "$menu__selected" -ge "$menu__item_count" ]
      then
        menu__selected=$((menu__item_count - 1))
      fi

      [ "$menu__selected" -ge 0 ] || menu__selected=0
      menu__render_needed=1
      return 0
      ;;
    reset)
      menu__provider_count_get || return 2
      menu__selected=0
      menu__top=0
      menu__render_needed=1
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

#-------------------------------------------------------------------------------

menu__update_geometry()
{
  term_size_update || {
    menu__fail "cannot read terminal size"
    return 2
  }

  menu__term_lines=$term_rows
  menu__term_cols=$term_cols
  menu__header_lines=$(menu__line_count "$menu_header") || return 2
  menu__footer_lines=$(menu__line_count "$menu_footer") || return 2
  menu__bottom_footer_lines=$(menu__line_count "$menu_bottom_footer") || return 2

  menu__visible_rows=$((menu__term_lines - menu__header_lines - menu__footer_lines - menu__bottom_footer_lines))

  if [ "$menu__visible_rows" -lt 1 ] || [ "$menu__term_cols" -lt 3 ]
  then
    menu__fail "terminal is too small"
    return 2
  fi

  return 0
}

menu__render()
{
  term_clear || {
    menu__fail "terminal does not support clear"
    return 2
  }

  if [ -n "$menu_header" ]
  then
    menu__print_block "$menu_header" "$menu__term_cols" "1" || {
      menu__fail "cannot render menu header"
      return 2
    }
  fi

  menu__remaining=$((menu__item_count - menu__top))

  if [ "$menu__remaining" -lt "$menu__visible_rows" ]
  then
    menu__render_rows=$menu__remaining
  else
    menu__render_rows=$menu__visible_rows
  fi

  menu__row=0
  menu__index=$menu__top
  menu__last_menu_row=$((menu__render_rows - 1))
  menu__text_width=$((menu__term_cols - 2))

  while [ "$menu__row" -lt "$menu__render_rows" ]
  do
    menu__provider_item_get "$menu__index" || return 2
    menu__text=$(menu__safe_item_text "$menu_provider_label" "$menu__text_width") || {
      menu__fail "cannot render menu item"
      return 2
    }

    if [ "$menu__index" -eq "$menu__selected" ]
    then
      printf '> %s' "$menu__text" > "$term_tty_device" || return 2
    else
      printf '  %s' "$menu__text" > "$term_tty_device" || return 2
    fi

    if [ "$menu__row" -lt "$menu__last_menu_row" ] || [ -n "$menu_footer" ]
    then
      printf '\n' > "$term_tty_device" || return 2
    fi

    menu__row=$((menu__row + 1))
    menu__index=$((menu__index + 1))
  done

  if [ -n "$menu_footer" ]
  then
    menu__print_block "$menu_footer" "$menu__term_cols" "0" || {
      menu__fail "cannot render menu footer"
      return 2
    }
  fi

  if [ -n "$menu_bottom_footer" ]
  then
    menu__bottom_footer_row=$((menu__term_lines - menu__bottom_footer_lines))
    term_cursor_move "$menu__bottom_footer_row" 0 || {
      menu__fail "terminal does not support cursor positioning"
      return 2
    }

    menu__print_block "$menu_bottom_footer" "$menu__term_cols" "0" || {
      menu__fail "cannot render bottom footer"
      return 2
    }
  fi

  term_cursor_move 0 0 || {
    menu__fail "terminal does not support cursor positioning"
    return 2
  }

  return 0
}

#-------------------------------------------------------------------------------

menu__apply_key()
{
  menu__action=ignore

  case "$menu__key" in
    escape)
      menu__action=cancel
      ;;
    up)
      if [ "$menu__selected" -gt 0 ]
      then
        menu__selected=$((menu__selected - 1))
        menu__action=move
      fi
      ;;
    down)
      if [ "$menu__selected" -lt "$((menu__item_count - 1))" ]
      then
        menu__selected=$((menu__selected + 1))
        menu__action=move
      fi
      ;;
    pageup)
      if [ "$menu__selected" -gt 0 ]
      then
        menu__selected=$((menu__selected - menu__visible_rows))
        [ "$menu__selected" -ge 0 ] || menu__selected=0
        menu__action=move
      fi
      ;;
    pagedown)
      if [ "$menu__selected" -lt "$((menu__item_count - 1))" ]
      then
        menu__selected=$((menu__selected + menu__visible_rows))
        if [ "$menu__selected" -ge "$menu__item_count" ]
        then
          menu__selected=$((menu__item_count - 1))
        fi
        menu__action=move
      fi
      ;;
    home)
      if [ "$menu__selected" -ne 0 ]
      then
        menu__selected=0
        menu__action=move
      fi
      ;;
    end)
      if [ "$menu__selected" -ne "$((menu__item_count - 1))" ]
      then
        menu__selected=$((menu__item_count - 1))
        menu__action=move
      fi
      ;;
    enter)
      menu__action=event
      ;;
  esac

  if [ "$menu__action" = "ignore" ] && menu__key_is_configured "$menu__key"
  then
    menu__action=event
  fi
}

#-------------------------------------------------------------------------------

menu__cleanup()
{
  menu__cleanup_status=$?
  trap - 0 HUP INT QUIT TERM PIPE TSTP

  if [ "$menu__cursor_hidden" -eq 1 ]
  then
    term_cursor_show || :
    menu__cursor_hidden=0
  fi

  if [ "$menu__keypad" -eq 1 ]
  then
    term_keypad_disable || :
    menu__keypad=0
  fi

  if [ "$menu__alt_screen" -eq 1 ]
  then
    term_screen_leave || :
    menu__alt_screen=0
  fi

  if [ "$menu__tty_saved" -eq 1 ]
  then
    term_tty_restore || :
    menu__tty_saved=0
  fi

  return "$menu__cleanup_status"
}

menu__terminal_init()
{
  term_tty_available || {
    menu__fail "no usable terminal is available"
    return 2
  }

  term_tty_save || {
    menu__fail "cannot save terminal settings"
    return 2
  }
  menu__tty_saved=1

  term_size_update || {
    menu__fail "cannot read terminal size"
    return 2
  }

  term_tty_blocking || {
    menu__fail "cannot configure terminal"
    return 2
  }

  term_keymap_init || {
    menu__fail "cannot build terminal keymap"
    return 2
  }

  if term_keypad_enable
  then
    menu__keypad=1
  fi

  if term_screen_enter
  then
    menu__alt_screen=1
  fi

  if term_cursor_hide
  then
    menu__cursor_hidden=1
  fi

  return 0
}

#-------------------------------------------------------------------------------

menu__handle_event()
{
  menu__provider_event "$menu__key" "$menu__selected"
  menu__event_status=$?

  case "$menu__event_status" in
    0) return 0 ;;
    10) return 10 ;;
    11) return 11 ;;
    *) return 2 ;;
  esac
}

menu__main_loop()
{
  menu__provider_count_get || return 2
  menu__selected=0
  menu__top=0
  menu__render_needed=1

  while :
  do
    if [ "$menu__render_needed" -eq 1 ]
    then
      menu__update_geometry || return 2

      if [ "$menu__selected" -lt "$menu__top" ]
      then
        menu__top=$menu__selected
      elif [ "$menu__selected" -ge "$((menu__top + menu__visible_rows))" ]
      then
        menu__top=$((menu__selected - menu__visible_rows + 1))
      fi

      menu__render || return 2
      menu__render_needed=0
    fi

    menu__read_key blocking
    menu__read_status=$?

    case "$menu__read_status" in
      0) ;;
      2) continue ;;
      *)
        menu__fail "cannot read from terminal"
        return 2
        ;;
    esac

    menu__apply_key

    case "$menu__action" in
      cancel)
        return 1
        ;;
      event)
        menu__handle_event
        menu__event_status=$?

        case "$menu__event_status" in
          0) ;;
          10) return 0 ;;
          11) return 1 ;;
          *) return 2 ;;
        esac
        ;;
      move)
        menu__pending=0

        while [ "$menu__pending" -lt 64 ]
        do
          menu__read_key nowait
          menu__read_status=$?

          case "$menu__read_status" in
            0) ;;
            2)
              menu__pending=$((menu__pending + 1))
              continue
              ;;
            3)
              break
              ;;
            *)
              menu__fail "cannot read queued terminal input"
              return 2
              ;;
          esac

          menu__apply_key

          case "$menu__action" in
            cancel)
              return 1
              ;;
            event)
              menu__handle_event
              menu__event_status=$?

              case "$menu__event_status" in
                0)
                  if [ "$menu__render_needed" -eq 1 ]
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

          menu__pending=$((menu__pending + 1))
        done

        menu__render_needed=1
        ;;
    esac
  done
}

#-------------------------------------------------------------------------------

menu__session()
{
  menu__provider=$1
  menu__tty_saved=0
  menu__keypad=0
  menu__alt_screen=0
  menu__cursor_hidden=0
  menu__session_result_key=
  menu__session_result_value=
  menu__session_error=

  trap 'menu__cleanup' 0
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 131' QUIT
  trap 'exit 141' PIPE
  trap 'exit 143' TERM
  trap 'exit 148' TSTP

  menu__terminal_init
  menu__status=$?

  if [ "$menu__status" -eq 0 ]
  then
    menu__main_loop
    menu__status=$?
  fi

  case "$menu__status" in
    0)
      menu__session_record=$(quote "$menu__session_result_key" "$menu__session_result_value") || {
        printf '%s\n' "cannot serialize menu result"
        return 2
      }
      printf '%s\n' "$menu__session_record"
      ;;
    2)
      printf '%s\n' "$menu__session_error"
      ;;
  esac

  return "$menu__status"
}

menu_run_provider()
{
  menu_result_key=
  menu_result_value=
  menu_error=

  if [ "$#" -ne 1 ] || [ -z "$1" ]
  then
    menu_error="menu_run_provider requires one provider function"
    return 2
  fi

  menu__record=$(menu__session "$1")
  menu__status=$?

  case "$menu__status" in
    0)
      # menu__record is produced only by quote(), so eval reparses a shell-safe
      # serialized argument list rather than provider data as code.
      if ! eval "set -- $menu__record"
      then
        menu_error="invalid internal menu result"
        return 2
      fi

      if [ "$#" -ne 2 ]
      then
        menu_error="invalid internal menu result"
        return 2
      fi

      menu_result_key=$1
      menu_result_value=$2
      return 0
      ;;
    1)
      return 1
      ;;
    2)
      menu_error=$menu__record
      [ -n "$menu_error" ] || menu_error="menu engine failed"
      return 2
      ;;
    *)
      return "$menu__status"
      ;;
  esac
}

menu__newline='
'

menu_reset
