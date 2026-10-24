NAME
    pkg-uninstall.lib.sh - remove installed package concretes

DESCRIPTION
    pkg-uninstall.lib.sh implements local package uninstall. It resolves each
    requested installed package concrete, clears its package default when
    necessary, checks provider references and delegates concrete removal to
    pkg-integration.lib.sh.

FUNCTIONS
    pkg_uninstall <package>[@<version>][!<osarch>] [...]
        Uninstall one or more local package operands. An explicitly requested
        version selects that concrete. Without a version, the current concrete
        is selected when present; otherwise a single installed concrete may be
        selected unambiguously.

RETURN STATUS
    0   Every requested package operand was uninstalled successfully.
    1   At least one requested package could not be resolved or removed.
    2   The invocation or a package operand is invalid.

DEPENDENCIES
    The library uses pkg-local.lib.sh for local package/class resolution and
    pkg-integration.lib.sh for default/deintegration operations.

SEE ALSO
    pkg
    pkg-local.lib.sh
    pkg-integration.lib.sh
