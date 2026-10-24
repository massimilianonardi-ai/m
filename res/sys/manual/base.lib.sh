NAME
    base.lib.sh - common m shell runtime facilities

DESCRIPTION
    base.lib.sh establishes the common shell runtime loaded by core.lib.sh.
    It provides system-library loading, common validators, diagnostics,
    pathname helpers, shell support and small execution utilities.

FUNCTIONS
    loadsyslib <system-shell-library-reference>
        Load one m-owned system shell library relative to lib/sys/sh through
        the active loadlib implementation.

    valid_integer <value> [...]
        Validate one or more non-empty unsigned decimal integer strings.
        Return 1 when no operands are supplied and 2 when any value is invalid.

    valid_shell_identifier <value> [...]
        Validate one or more portable shell-style identifiers consisting of
        letters, digits and underscore and not beginning with a digit.
        Return 1 when no operands are supplied and 2 when any value is invalid.

    valid_cli_name <value> [...]
        Validate one or more command-line names. A valid name begins with a
        letter, contains only letters, digits, underscore or hyphen, and does
        not end in underscore or hyphen.
        Return 1 when no operands are supplied and 2 when any value is invalid.

    valid_namespace_name <value> [...]
        Validate one or more namespace names. A valid name begins with a
        letter, contains only letters, digits, underscore, hyphen or dot, and
        does not end in underscore, hyphen or dot.
        Return 1 when no operands are supplied and 2 when any value is invalid.

    valid_dir <path>
        Validate that path names an existing directory and that the pathname
        itself is not a symbolic link.
        Return 1 for invalid invocation and 2 when path is not a real directory.

    log_base_print [<field> ...]
        Write a minimal fallback diagnostic line to standard error.

    log <severity> <domain> <message-id> [<field> <value>]...
        Emit one localized structured diagnostic subject to m_LOG_LEVEL.

    fatal [<exit-status>] <domain> <message-id> [<field> <value>]...
        Emit a fatal diagnostic and terminate the current process. When the
        optional first operand is a valid non-zero shell exit status, use it;
        otherwise the default exit status is 1.

    readpathce <variable> <path-or-command>
        Resolve an existing pathname or command to a canonical real pathname
        and assign it to variable. The destination variable must be a valid
        shell identifier other than PATH.

    lang <domain> <message-id>
        Print the localized message from the current language tree, fall back
        to the configured fallback language, or finally print domain.message-id.

    shell [<argument> ...]
        Replace the current process with the selected interactive/user shell,
        preparing the m-managed shell configuration required by supported
        shells.

    quote [<argument> ...]
        Print shell-safe single-quoted representations of the supplied
        arguments suitable for later restoration with eval.

    pathsearch <variable> <path-or-command>
        Resolve a file pathname directly or search PATH for a file, canonicalize
        the result and assign it to variable.

    exist_function <name>
        Return success only when name currently resolves to a shell function,
        not an external pathname, alias or reserved word.

    exec_if_exist_function <name> [<argument> ...]
        Invoke the named function with the supplied arguments only when
        exist_function confirms that the function exists.

    waituser
        When execution appears to have been launched outside an active shell,
        prompt for ENTER before returning.

PUBLIC STATE
    m_LOG_LEVEL
        Exported logging threshold. The default is info.

    shell()
        May export m_SHELL_NAME, m_SHELL_EXT and shell-specific environment
        such as m_SHELL_ZDOTDIR, m_SHELL_ZDOTDIR_INIT, m_SHELL_ENV and ENV.

DEPENDENCIES
    base.lib.sh is loaded by core.lib.sh after loadlib has been established.
    Some facilities call standard POSIX utilities and current m commands such
    as state-path.

SEE ALSO
    m
    core.lib.sh
