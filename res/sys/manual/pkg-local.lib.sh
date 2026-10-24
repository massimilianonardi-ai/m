NAME
    pkg-local.lib.sh - internal local package request and class helpers

DESCRIPTION
    pkg-local.lib.sh provides internal parsing and installed-package-class
    selection used by local pkg operations.

    The library defines no public callable functions. All functions in this
    library are underscore-prefixed implementation-private helpers and are not
    part of the callable library API.

DEPENDENCIES
    The library uses the shared package identity validators from
    pkg-common.lib.sh.

SEE ALSO
    pkg
    pkg-common.lib.sh
