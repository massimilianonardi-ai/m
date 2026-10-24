NAME
    pkg-default.lib.sh - query and select the local package default

DESCRIPTION
    pkg-default.lib.sh implements the local package-default operation used by
    the pkg command. It resolves the requested local package/platform class and
    delegates default publication to pkg-integration.lib.sh.

FUNCTIONS
    pkg_default [-u] [--] <package>[@<version>][!<osarch>]
        With a version, select that installed concrete as the default for the
        package/platform class.

        Without a version, print the current concrete identity. With -u, clear
        the current default for the selected package/platform class.

RETURN STATUS
    0   The query or requested default transition succeeded.
    1   The local package class/default state could not be resolved or changed.
    2   The invocation or package operand is invalid.

DEPENDENCIES
    The library uses pkg-local.lib.sh for local package/class resolution and
    pkg-integration.lib.sh for applying package defaults.

SEE ALSO
    pkg
    pkg-local.lib.sh
    pkg-integration.lib.sh
