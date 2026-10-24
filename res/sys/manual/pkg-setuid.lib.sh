NAME
    pkg-setuid.lib.sh - internal privileged package integration handling

DESCRIPTION
    Internal validation and materialization of the declared setuid-root
    subset of package files, including rollback and cleanup. Authorization
    remains subject to the package/host permission contract.

FUNCTIONS
    No public functions. Every function in this library is internal and
    begins with an underscore. Its helpers are not a supported command
    or library interface for package consumers.

DEPENDENCIES
    pkg-state.lib.sh, package integration runtime, POSIX host privileges.

SEE ALSO
    pkg-integration.lib.sh
    pkg-state.lib.sh
