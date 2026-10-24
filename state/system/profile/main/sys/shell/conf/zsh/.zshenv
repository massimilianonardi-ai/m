if [ "${m_SHELL_ZDOTDIR+x}" = "x" ]
then
  ZDOTDIR="$m_SHELL_ZDOTDIR"
  export ZDOTDIR

  if [ -r "$ZDOTDIR/.zshenv" ]
  then
    . "$ZDOTDIR/.zshenv"
  fi
else
  unset ZDOTDIR

  if [ -r "$HOME/.zshenv" ]
  then
    . "$HOME/.zshenv"
  fi
fi

unset m_SHELL_ZDOTDIR

if [ "${ZDOTDIR+x}" = "x" ]
then
  m_SHELL_ZDOTDIR="$ZDOTDIR"
  export m_SHELL_ZDOTDIR
fi

case "$-" in
  *i*)
    ZDOTDIR="$m_SHELL_ZDOTDIR_INIT"
    export ZDOTDIR
    ;;
  *)
    if [ "${m_SHELL_ZDOTDIR+x}" = "x" ]
    then
      ZDOTDIR="$m_SHELL_ZDOTDIR"
      export ZDOTDIR
    else
      unset ZDOTDIR
    fi

    unset m_SHELL_ZDOTDIR
    unset m_SHELL_ZDOTDIR_INIT
    ;;
esac
