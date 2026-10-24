if [ "${m_SHELL_ZDOTDIR+x}" = "x" ]
then
  ZDOTDIR="$m_SHELL_ZDOTDIR"
  export ZDOTDIR

  if [ -r "$ZDOTDIR/.zshrc" ]
  then
    . "$ZDOTDIR/.zshrc"
  fi
else
  unset ZDOTDIR

  if [ -r "$HOME/.zshrc" ]
  then
    . "$HOME/.zshrc"
  fi
fi

unset m_SHELL_ZDOTDIR
unset m_SHELL_ZDOTDIR_INIT

if [[ -o aliases ]]
then
  \builtin unsetopt aliases
  . "$m_LIB_DIR/sys/sh/core.lib.sh"
  \builtin setopt aliases
else
  . "$m_LIB_DIR/sys/sh/core.lib.sh"
fi

# PS1="$(tput setaf 7)$(tput bold)${m_SHELL_NAME}$(tput sgr0) $(tput setaf 2)%n$(tput setaf 7)@$(tput setaf 2)%m$(tput setaf 7):$(tput setaf 2)%~$(tput setaf 4) %#$(tput sgr0) "
# PS1="%{$(tput setaf 7)$(tput bold)%}${m_SHELL_NAME}%{$(tput sgr0)%} %{$(tput setaf 2)%}%n%{$(tput setaf 7)%}@%{$(tput setaf 2)%}%m%{$(tput setaf 7)%}:%{$(tput setaf 2)%}%~%{$(tput setaf 4)%}%#%{$(tput sgr0)%} "
PS1="%F{7}%B${m_SHELL_NAME}%b%f %F{2}%n%F{7}@%F{2}%m%F{7}:%F{2}%~%F{4}%#%f "

if [ -f "$m_SHELL_EXT" ] && [ -r "$m_SHELL_EXT" ]
then
  . "$m_SHELL_EXT"
fi
